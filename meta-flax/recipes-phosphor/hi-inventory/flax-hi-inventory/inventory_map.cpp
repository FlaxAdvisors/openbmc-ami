#include "inventory_map.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>

namespace flax::inventory
{

namespace
{

std::string trim(const std::string& s)
{
    const auto b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos)
    {
        return {};
    }
    const auto e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

/* Fetch helpers.  The BIOS omits fields it has no data for, so every read is
 * optional and a missing field simply leaves the property unpublished. */
std::optional<std::string> getString(const nlohmann::json& j, const char* key)
{
    auto it = j.find(key);
    if (it == j.end() || !it->is_string())
    {
        return std::nullopt;
    }
    std::string v = trim(it->get<std::string>());
    if (v.empty())
    {
        return std::nullopt;
    }
    return v;
}

std::optional<uint64_t> getUint(const nlohmann::json& j, const char* key)
{
    auto it = j.find(key);
    if (it == j.end() || !it->is_number_unsigned())
    {
        return std::nullopt;
    }
    return it->get<uint64_t>();
}

const nlohmann::json* getObject(const nlohmann::json& j, const char* key)
{
    auto it = j.find(key);
    if (it == j.end() || !it->is_object())
    {
        return nullptr;
    }
    return &(*it);
}

/* Status -> Present / Functional.  Anything other than an explicit "Absent" /
 * non-OK health is treated as a healthy, populated part. */
bool statusPresent(const nlohmann::json& j)
{
    const nlohmann::json* status = getObject(j, "Status");
    if (status == nullptr)
    {
        return true;
    }
    auto state = getString(*status, "State");
    return !(state && *state == "Absent");
}

bool statusFunctional(const nlohmann::json& j)
{
    const nlohmann::json* status = getObject(j, "Status");
    if (status == nullptr)
    {
        return true;
    }
    auto health = getString(*status, "Health");
    return !(health && *health != "OK");
}

void addAsset(Object& obj, const nlohmann::json& j)
{
    Properties asset;
    if (auto v = getString(j, "Manufacturer"))
    {
        asset["Manufacturer"] = *v;
    }
    if (auto v = getString(j, "PartNumber"))
    {
        asset["PartNumber"] = *v;
    }
    if (auto v = getString(j, "SerialNumber"))
    {
        asset["SerialNumber"] = *v;
    }
    if (!asset.empty())
    {
        obj.interfaces[ifaceAsset] = std::move(asset);
    }
}

/* MemoryDeviceType string -> Item.Dimm.DeviceType enum.  Only the types this
 * BIOS can actually report are listed; an unknown string leaves MemoryType
 * unset rather than guessing, which bmcweb renders as no MemoryDeviceType. */
std::optional<std::string> deviceTypeEnum(const std::string& type)
{
    static const std::map<std::string, std::string> map = {
        {"DDR", "DDR"},          {"DDR2", "DDR2"},
        {"DDR3", "DDR3"},        {"DDR4", "DDR4"},
        {"DDR5", "DDR5"},        {"DDR4E_SDRAM", "DDR4E_SDRAM"},
        {"LPDDR3", "LPDDR3_SDRAM"}, {"LPDDR4", "LPDDR4_SDRAM"},
        {"LPDDR5", "LPDDR5_SDRAM"}, {"HBM", "HBM"},
        {"HBM2", "HBM2"},        {"HBM3", "HBM3"},
    };
    auto it = map.find(type);
    if (it == map.end())
    {
        return std::nullopt;
    }
    return std::string(ifaceDimm) + ".DeviceType." + it->second;
}

/* BaseModuleType string -> Item.Dimm.FormFactor enum. */
std::optional<std::string> formFactorEnum(const std::string& form)
{
    static const std::map<std::string, std::string> map = {
        {"RDIMM", "RDIMM"},   {"UDIMM", "UDIMM"},
        {"LRDIMM", "LRDIMM"}, {"SO_DIMM", "SO_DIMM"},
        {"SO-DIMM", "SO_DIMM"}, {"SODIMM", "SO_DIMM"},
        {"Mini_RDIMM", "Mini_RDIMM"}, {"Mini_UDIMM", "Mini_UDIMM"},
        {"Die", "Die"},
    };
    auto it = map.find(form);
    if (it == map.end())
    {
        return std::nullopt;
    }
    return std::string(ifaceDimm) + ".FormFactor." + it->second;
}

/* Parse "0x00050654BFEBFBFF" (Redfish ProcessorId.IdentificationRegisters).
 * The high word is CPUID leaf 1 EAX, the low word EDX. */
std::optional<uint64_t> parseIdentificationRegisters(const std::string& s)
{
    const char* p = s.c_str();
    if (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
    {
        p += 2;
    }
    if (*p == '\0')
    {
        return std::nullopt;
    }
    char* end = nullptr;
    const uint64_t v = std::strtoull(p, &end, 16);
    if (end == nullptr || *end != '\0')
    {
        return std::nullopt;
    }
    return v;
}

} // namespace

bool notifiable(const Value& value)
{
    return std::visit(
        [](const auto& v) {
            using T = std::decay_t<decltype(v)>;
            return std::is_same_v<T, bool> || std::is_same_v<T, uint16_t> ||
                   std::is_same_v<T, uint32_t> || std::is_same_v<T, int64_t> ||
                   std::is_same_v<T, std::string>;
        },
        value);
}

std::optional<unsigned> dimmIndexFromLocator(const std::string& locator)
{
    /* Take the last whitespace-separated token: "DIMM A0" -> "A0". */
    const auto pos = locator.find_last_of(" \t");
    const std::string tag =
        (pos == std::string::npos) ? locator : locator.substr(pos + 1);
    if (tag.size() != 2)
    {
        return std::nullopt;
    }
    const char letter = static_cast<char>(std::toupper(tag[0]));
    if (letter < 'A' || letter > 'Z' || !std::isdigit(tag[1]))
    {
        return std::nullopt;
    }
    /* Six slots per channel-group letter on TiogaPass: A0-A5 then B0-B5. */
    constexpr unsigned slotsPerLetter = 6;
    const unsigned digit = static_cast<unsigned>(tag[1] - '0');
    if (digit >= slotsPerLetter)
    {
        return std::nullopt;
    }
    return static_cast<unsigned>(letter - 'A') * slotsPerLetter + digit;
}

std::optional<Object> mapDimm(const nlohmann::json& j, unsigned fallbackIndex)
{
    if (!j.is_object())
    {
        return std::nullopt;
    }

    const auto locator = getString(j, "DeviceLocator");
    unsigned index = fallbackIndex;
    if (locator)
    {
        if (auto derived = dimmIndexFromLocator(*locator))
        {
            index = *derived;
        }
    }

    Object obj;
    obj.path = std::string(dimmPrefix) + std::to_string(index);

    Properties dimm;
    if (auto v = getUint(j, "CapacityMiB"))
    {
        /* Despite the name, MemorySizeInKB is KiB: bmcweb renders
         * CapacityMiB = MemorySizeInKB >> 10 (memory.hpp). */
        dimm["MemorySizeInKB"] = static_cast<uint32_t>(*v * 1024);
    }
    if (auto v = getUint(j, "DataWidthBits"))
    {
        dimm["MemoryDataWidth"] = static_cast<uint16_t>(*v);
    }
    if (auto v = getUint(j, "BusWidthBits"))
    {
        dimm["MemoryTotalWidth"] = static_cast<uint16_t>(*v);
    }
    if (auto v = getUint(j, "OperatingSpeedMhz"))
    {
        dimm["MemoryConfiguredSpeedInMhz"] = static_cast<uint16_t>(*v);
    }

    /* The BIOS does not report an error-correction type over the host
     * interface, but leaving ECC unset is not neutral: the property still
     * exists with its enum default and Redfish renders ErrorCorrection:
     * "NoECC" on a module that plainly has ECC.  Derive it the way SMBIOS
     * defines the fields -- the total width carries the check bits, so a bus
     * wider than the data path means ECC. */
    {
        const auto data = getUint(j, "DataWidthBits");
        const auto bus = getUint(j, "BusWidthBits");
        if (data && bus)
        {
            dimm["ECC"] = std::string(ifaceDimm) + ".Ecc." +
                          (*bus > *data ? "MultiBitECC" : "NoECC");
        }
    }
    if (auto v = getUint(j, "RankCount"))
    {
        /* bmcweb reads RankCount out of MemoryAttributes. */
        dimm["MemoryAttributes"] = static_cast<uint32_t>(*v);
    }
    if (auto v = getString(j, "MemoryDeviceType"))
    {
        if (auto e = deviceTypeEnum(*v))
        {
            dimm["MemoryType"] = *e;
        }
        if (v->rfind("DDR", 0) == 0 || v->rfind("LPDDR", 0) == 0)
        {
            dimm["MemoryMedia"] = std::string(ifaceDimm) + ".MemoryTech.DRAM";
        }
    }
    if (auto v = getString(j, "BaseModuleType"))
    {
        if (auto e = formFactorEnum(*v))
        {
            dimm["FormFactor"] = *e;
        }
    }
    if (locator)
    {
        dimm["MemoryDeviceLocator"] = *locator;
    }

    auto speeds = j.find("AllowedSpeedsMHz");
    if (speeds != j.end() && speeds->is_array())
    {
        std::vector<uint16_t> allowed;
        uint16_t fastest = 0;
        for (const auto& s : *speeds)
        {
            if (!s.is_number_unsigned())
            {
                continue;
            }
            const auto mhz = static_cast<uint16_t>(s.get<uint64_t>());
            allowed.push_back(mhz);
            fastest = std::max(fastest, mhz);
        }
        if (!allowed.empty())
        {
            dimm["AllowedSpeedsMT"] = allowed;
            dimm["MaxMemorySpeedInMhz"] = fastest;
        }
    }

    if (!dimm.empty())
    {
        obj.interfaces[ifaceDimm] = std::move(dimm);
    }

    /* MemoryLocation is passed through exactly as the BIOS reports it.  Note
     * this BIOS flattens Socket to 0 for every DIMM including the B bank; the
     * bank is still distinguishable via MemoryController and the service
     * label, so the raw values are published rather than second-guessed. */
    if (const nlohmann::json* loc = getObject(j, "MemoryLocation"))
    {
        Properties location;
        for (const char* key :
             {"Socket", "MemoryController", "Channel", "Slot"})
        {
            if (auto v = getUint(*loc, key))
            {
                location[key] = static_cast<uint8_t>(*v);
            }
        }
        if (!location.empty())
        {
            obj.interfaces[ifaceMemoryLocation] = std::move(location);
        }
    }

    addAsset(obj, j);

    if (locator)
    {
        /* Redfish Location.PartLocation.ServiceLabel -- the silkscreen name
         * the customer reads off the board. */
        obj.interfaces[ifaceLocationCode] = {{"LocationCode", *locator}};
    }

    Properties item;
    item["Present"] = statusPresent(j);
    if (locator)
    {
        item["PrettyName"] = *locator;
    }
    obj.interfaces[ifaceItem] = std::move(item);

    obj.interfaces[ifaceOperationalStatus] = {
        {"Functional", statusFunctional(j)}};

    return obj;
}

std::optional<Object> mapCpu(const nlohmann::json& j, unsigned fallbackIndex)
{
    if (!j.is_object())
    {
        return std::nullopt;
    }

    const auto socket = getString(j, "Socket");
    unsigned index = fallbackIndex;
    if (socket && !socket->empty() &&
        socket->find_first_not_of("0123456789") == std::string::npos)
    {
        index = static_cast<unsigned>(std::strtoul(socket->c_str(), nullptr, 10));
    }

    Object obj;
    obj.path = std::string(cpuPrefix) + std::to_string(index);

    Properties cpu;
    if (auto v = getUint(j, "TotalCores"))
    {
        cpu["CoreCount"] = static_cast<uint16_t>(*v);
    }
    if (auto v = getUint(j, "TotalThreads"))
    {
        cpu["ThreadCount"] = static_cast<uint16_t>(*v);
    }
    if (auto v = getUint(j, "MaxSpeedMHz"))
    {
        cpu["MaxSpeedInMhz"] = static_cast<uint32_t>(*v);
    }
    if (socket)
    {
        cpu["Socket"] = *socket;
    }

    if (const nlohmann::json* pid = getObject(j, "ProcessorId"))
    {
        if (auto regs = getString(*pid, "IdentificationRegisters"))
        {
            if (auto id = parseIdentificationRegisters(*regs))
            {
                cpu["Id"] = *id;

                /* Decode CPUID leaf 1 EAX (the high word) into the fields
                 * Redfish reports separately.  This is a decode of the value
                 * the BIOS gave us, not an inference about the part. */
                const uint32_t eax = static_cast<uint32_t>(*id >> 32);
                const uint16_t baseFamily = (eax >> 8) & 0xF;
                const uint16_t baseModel = (eax >> 4) & 0xF;
                uint16_t family = baseFamily;
                uint16_t model = baseModel;
                if (baseFamily == 0xF)
                {
                    family = static_cast<uint16_t>(baseFamily +
                                                   ((eax >> 20) & 0xFF));
                }
                if (baseFamily == 0x6 || baseFamily == 0xF)
                {
                    model = static_cast<uint16_t>(
                        baseModel | ((eax >> 12) & 0xF0));
                }
                cpu["EffectiveFamily"] = family;
                cpu["EffectiveModel"] = model;
                cpu["Step"] = static_cast<uint16_t>(eax & 0xF);
            }
        }
    }

    if (!cpu.empty())
    {
        obj.interfaces[ifaceCpu] = std::move(cpu);
    }

    addAsset(obj, j);

    /* The BIOS packs the brand string together with a core/thread summary:
     * "Intel(R) Xeon(R) Gold 6138 CPU @ 2.00GHz, 2000 Mhz, 20 Core(s), 40
     * Logical Processor(s)".  Redfish Model is the brand string, and the
     * trailing counts are already reported as TotalCores/TotalThreads. */
    if (auto model = getString(j, "Model"))
    {
        const auto comma = model->find(',');
        std::string brand =
            (comma == std::string::npos) ? *model : model->substr(0, comma);
        brand = trim(brand);
        if (!brand.empty())
        {
            obj.interfaces[ifaceAsset]["Model"] = brand;
        }
    }

    Properties item;
    item["Present"] = statusPresent(j);
    item["PrettyName"] = "cpu" + std::to_string(index);
    obj.interfaces[ifaceItem] = std::move(item);

    obj.interfaces[ifaceOperationalStatus] = {
        {"Functional", statusFunctional(j)}};

    return obj;
}

std::string sanitizeId(const std::string& raw, const std::string& fallback)
{
    std::string out;
    for (char c : raw)
    {
        if (std::isalnum(static_cast<unsigned char>(c)) != 0 || c == '_')
        {
            out.push_back(c);
        }
        else if (c == '-' || c == '.' || c == ' ' || c == '/')
        {
            out.push_back('_');
        }
    }
    return out.empty() ? fallback : out;
}

std::optional<Object> mapPcieDevice(const nlohmann::json& j,
                                    const std::string& fallbackId)
{
    if (!j.is_object())
    {
        return std::nullopt;
    }

    std::string id = fallbackId;
    if (auto v = getString(j, "Id"))
    {
        id = *v;
    }

    Object obj;
    obj.path = std::string(pciePrefix) + sanitizeId(id, fallbackId);

    Properties dev;

    /* The BIOS nests the functions under Links.PCIeFunctions; bmcweb wants
     * them flattened onto the device as Function<N><Field>, all strings. */
    const nlohmann::json* links = getObject(j, "Links");
    if (links != nullptr)
    {
        auto fns = links->find("PCIeFunctions");
        if (fns != links->end() && fns->is_array())
        {
            constexpr unsigned maxFunctions = 8; // bmcweb scans 0..7
            unsigned n = 0;
            for (const auto& fn : *fns)
            {
                if (!fn.is_object() || n >= maxFunctions)
                {
                    break;
                }
                const std::string p = "Function" + std::to_string(n);
                /* DeviceId is the existence marker bmcweb keys on: without it
                 * the function is not rendered at all, so a record that lacks
                 * one contributes nothing and is skipped. */
                auto deviceId = getString(fn, "DeviceId");
                if (!deviceId)
                {
                    continue;
                }
                dev[p + "DeviceId"] = *deviceId;
                for (const auto& [src, dst] :
                     {std::pair<const char*, const char*>{"VendorId",
                                                          "VendorId"},
                      {"ClassCode", "ClassCode"},
                      {"RevisionId", "RevisionId"},
                      {"SubsystemId", "SubsystemId"},
                      {"SubsystemVendorId", "SubsystemVendorId"},
                      {"DeviceClass", "DeviceClass"},
                      {"FunctionType", "FunctionType"}})
                {
                    if (auto v = getString(fn, src))
                    {
                        dev[p + dst] = *v;
                    }
                }
                ++n;
            }
        }
    }

    if (auto v = getString(j, "DeviceType"))
    {
        dev["DeviceType"] = *v;
    }
    obj.interfaces[ifacePcieDevice] = std::move(dev);

    /* Adapter firmware, where the BIOS reports it -- the Mellanox gives
     * "14.27.26.06".  Item.PCIeDevice has no firmware field, so it goes on
     * Decorator.Revision, which is the interface bmcweb already reads for a
     * processor's Version. */
    if (auto v = getString(j, "FirmwareVersion"))
    {
        obj.interfaces[ifaceRevision] = {{"Version", *v}};
    }

    /* Manufacturer here is the BIOS's concatenated vendor+device id
     * ("8086F1A8"), not a vendor name, so it is deliberately NOT published as
     * Decorator.Asset.Manufacturer -- the per-function VendorId carries that
     * information properly. */
    Properties item;
    item["Present"] = statusPresent(j);
    if (auto v = getString(j, "Description"))
    {
        item["PrettyName"] = *v; // e.g. "8086 MASS Slot 3"
    }
    obj.interfaces[ifaceItem] = std::move(item);
    obj.interfaces[ifaceOperationalStatus] = {
        {"Functional", statusFunctional(j)}};

    return obj;
}

std::optional<std::string> slotFromDescription(const std::string& description)
{
    /* The BIOS appends a placement to its PCIe descriptions: "15B3 NIC Slot 2"
     * for an add-in card, "8086 A1A1 MEM Onboard" for something soldered
     * down.  Only the former is a location worth publishing. */
    const auto pos = description.rfind("Slot ");
    if (pos == std::string::npos)
    {
        return std::nullopt;
    }
    std::string slot = description.substr(pos);
    /* Guard against a description that merely ends with the word. */
    if (slot.size() <= 5)
    {
        return std::nullopt;
    }
    return slot;
}

std::optional<Object> mapFabricAdapter(const nlohmann::json& j,
                                       const std::string& fallbackId)
{
    if (!j.is_object())
    {
        return std::nullopt;
    }

    /* Only a device presenting a network-controller function is an adapter.
     * This is what keeps the 25-device list from turning into 25 "adapters":
     * on this machine exactly one qualifies, the Mellanox in slot 2. */
    bool isNetwork = false;
    const nlohmann::json* links = getObject(j, "Links");
    if (links != nullptr)
    {
        auto fns = links->find("PCIeFunctions");
        if (fns != links->end() && fns->is_array())
        {
            for (const auto& fn : *fns)
            {
                if (!fn.is_object())
                {
                    continue;
                }
                auto cls = getString(fn, "DeviceClass");
                if (cls && *cls == "NetworkController")
                {
                    isNetwork = true;
                    break;
                }
            }
        }
    }
    if (!isNetwork)
    {
        return std::nullopt;
    }

    std::string id = fallbackId;
    if (auto v = getString(j, "Id"))
    {
        id = *v;
    }

    Object obj;
    obj.path = std::string(nicPrefix) + sanitizeId(id, fallbackId);

    /* Marker interface -- no properties of its own, but it must be present for
     * bmcweb to enumerate the adapter at all. */
    obj.interfaces[ifaceFabricAdapter] = {};

    const auto description = getString(j, "Description");
    if (description)
    {
        if (auto slot = slotFromDescription(*description))
        {
            obj.interfaces[ifaceLocationCode] = {{"LocationCode", *slot}};
        }
    }

    /* No Model/PartNumber/SerialNumber: the BIOS gives none for the card, and
     * its "Manufacturer" field is a vendor+device id rather than a name.  The
     * identity lives on the matching PCIe device, which carries VendorId,
     * DeviceId and the firmware version. */
    Properties item;
    item["Present"] = statusPresent(j);
    if (description)
    {
        item["PrettyName"] = *description;
    }
    obj.interfaces[ifaceItem] = std::move(item);
    obj.interfaces[ifaceOperationalStatus] = {
        {"Functional", statusFunctional(j)}};

    if (auto v = getString(j, "FirmwareVersion"))
    {
        obj.interfaces[ifaceRevision] = {{"Version", *v}};
    }

    return obj;
}

std::optional<Object> mapDrive(const nlohmann::json& j,
                               const std::string& fallbackId)
{
    if (!j.is_object())
    {
        return std::nullopt;
    }

    std::string id = fallbackId;
    if (auto v = getString(j, "Id"))
    {
        id = *v;
    }

    Object obj;
    obj.path = std::string(drivePrefix) + sanitizeId(id, fallbackId);

    Properties drive;
    auto capacity = j.find("CapacityBytes");
    if (capacity != j.end() && capacity->is_number_unsigned())
    {
        drive["Capacity"] = capacity->get<uint64_t>();
    }
    if (auto v = getString(j, "Protocol"))
    {
        /* Enum members: SAS, SATA, NVMe, FC, eMMC, Unknown. */
        static const std::map<std::string, std::string> protocols = {
            {"NVMe", "NVMe"}, {"SATA", "SATA"}, {"SAS", "SAS"},
            {"FC", "FC"},     {"eMMC", "eMMC"},
        };
        auto it = protocols.find(*v);
        drive["Protocol"] = std::string(ifaceDrive) + ".DriveProtocol." +
                            (it == protocols.end() ? "Unknown" : it->second);
    }
    if (auto v = getString(j, "MediaType"))
    {
        /* Enum members: HDD, SSD, Unknown. */
        const bool known = (*v == "SSD" || *v == "HDD");
        drive["Type"] = std::string(ifaceDrive) + ".DriveType." +
                        (known ? *v : "Unknown");
    }
    if (!drive.empty())
    {
        obj.interfaces[ifaceDrive] = std::move(drive);
    }

    Properties asset;
    if (auto v = getString(j, "Model"))
    {
        asset["Model"] = *v;
    }
    if (auto v = getString(j, "SerialNumber"))
    {
        asset["SerialNumber"] = *v;
    }
    if (auto v = getString(j, "PartNumber"))
    {
        asset["PartNumber"] = *v;
    }
    /* The BIOS writes "N/A" where it has no vendor string; publishing that
     * verbatim would put "N/A" in front of a customer. */
    if (auto v = getString(j, "Manufacturer"))
    {
        if (*v != "N/A" && *v != "Not Available")
        {
            asset["Manufacturer"] = *v;
        }
    }
    if (!asset.empty())
    {
        obj.interfaces[ifaceAsset] = std::move(asset);
    }

    Properties item;
    item["Present"] = statusPresent(j);
    if (auto v = getString(j, "Model"))
    {
        item["PrettyName"] = *v;
    }
    obj.interfaces[ifaceItem] = std::move(item);

    /* FailurePredicted is the drive's own SMART verdict; fold it into
     * Functional so a dying drive shows as degraded rather than healthy. */
    bool functional = statusFunctional(j);
    auto failing = j.find("FailurePredicted");
    if (failing != j.end() && failing->is_boolean() && failing->get<bool>())
    {
        functional = false;
    }
    obj.interfaces[ifaceOperationalStatus] = {{"Functional", functional}};

    return obj;
}

Object absentObject(const std::string& path)
{
    Object obj;
    obj.path = path;
    obj.interfaces[ifaceItem] = {{"Present", false}};
    obj.interfaces[ifaceOperationalStatus] = {{"Functional", false}};
    return obj;
}

} // namespace flax::inventory
