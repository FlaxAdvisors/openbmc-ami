/*
 * flax-hi-inventory - publish host-interface inventory on D-Bus.
 *
 * The TP26 BIOS pushes its Memory/Processors inventory over the Redfish host
 * interface; bmcweb persists each collection member as a JSON file under
 * /var/lib/flax-inventory/collections/.  This oneshot reads that tree and
 * hands the whole thing to phosphor-inventory-manager in a single Notify()
 * call, which is what puts the DIMMs and CPUs into Redfish.
 *
 * Deliberately a full republish every run: it is idempotent, it cannot drift
 * from the files, and at ~14 objects the cost is irrelevant.  It runs at boot
 * as well as on push, so inventory survives a BMC reboot with the host off.
 */
#include "inventory_map.hpp"

#include <sdbusplus/bus.hpp>
#include <sdbusplus/message.hpp>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <thread>
#include <vector>

using namespace flax::inventory;

namespace
{

constexpr const char* collectionsRoot = "/var/lib/flax-inventory/collections";

constexpr const char* pimService = "xyz.openbmc_project.Inventory.Manager";
constexpr const char* pimPath = "/xyz/openbmc_project/inventory";
constexpr const char* pimIface = "xyz.openbmc_project.Inventory.Manager";

constexpr const char* mapperService = "xyz.openbmc_project.ObjectMapper";
constexpr const char* mapperPath = "/xyz/openbmc_project/object_mapper";
constexpr const char* mapperIface = "xyz.openbmc_project.ObjectMapper";

/* Read a collection group's members in numeric-ish filename order so the
 * fallback index (used only when a device locator is unusable) is stable. */
std::vector<std::filesystem::path> groupFiles(const std::string& group)
{
    std::vector<std::filesystem::path> files;
    std::error_code ec;
    const std::filesystem::path dir =
        std::filesystem::path(collectionsRoot) / group;
    for (const auto& entry : std::filesystem::directory_iterator(dir, ec))
    {
        if (entry.is_regular_file(ec) && entry.path().extension() == ".json")
        {
            files.push_back(entry.path());
        }
    }
    std::sort(files.begin(), files.end(),
              [](const std::filesystem::path& a, const std::filesystem::path& b) {
                  const std::string as = a.stem().string();
                  const std::string bs = b.stem().string();
                  const bool an =
                      as.find_first_not_of("0123456789") == std::string::npos;
                  const bool bn =
                      bs.find_first_not_of("0123456789") == std::string::npos;
                  if (an && bn)
                  {
                      return std::stoul(as) < std::stoul(bs);
                  }
                  return as < bs;
              });
    return files;
}

std::optional<nlohmann::json> readJson(const std::filesystem::path& path)
{
    std::ifstream in(path);
    if (!in)
    {
        fprintf(stderr, "flax-hi-inventory: cannot open %s\n", path.c_str());
        return std::nullopt;
    }
    nlohmann::json j = nlohmann::json::parse(in, nullptr, false);
    if (j.is_discarded())
    {
        fprintf(stderr, "flax-hi-inventory: %s is not valid JSON\n",
                path.c_str());
        return std::nullopt;
    }
    return j;
}

/* Paths we previously published that are no longer backed by a file.  Asking
 * the mapper rather than keeping our own state file means the answer is always
 * the truth on the bus. */
std::vector<std::string> publishedPaths(sdbusplus::bus_t& bus,
                                        const char* interface)
{
    std::vector<std::string> paths;
    try
    {
        auto m = bus.new_method_call(mapperService, mapperPath, mapperIface,
                                     "GetSubTreePaths");
        m.append(std::string(inventoryRoot) + motherboardPath, 0,
                 std::vector<std::string>{interface});
        bus.call(m).read(paths);
    }
    catch (const std::exception& e)
    {
        /* No objects of this type yet -> the mapper answers with an error.
         * That is the normal first-run case, not a failure. */
        paths.clear();
    }
    return paths;
}

void addAbsentObjects(sdbusplus::bus_t& bus, const char* interface,
                      const std::string& prefix,
                      const std::set<std::string>& current,
                      std::vector<Object>& objects)
{
    const std::string absolutePrefix = std::string(inventoryRoot) + prefix;
    for (const auto& path : publishedPaths(bus, interface))
    {
        if (path.rfind(absolutePrefix, 0) != 0)
        {
            /* Not one of ours (a different producer's object). */
            continue;
        }
        const std::string relative = path.substr(strlen(inventoryRoot));
        if (current.count(relative) == 0)
        {
            fprintf(stderr, "flax-hi-inventory: marking %s absent\n",
                    path.c_str());
            objects.push_back(absentObject(relative));
        }
    }
}

struct DeferredProperty
{
    std::string path; /* absolute */
    std::string interface;
    std::string name;
    Value value;
};

/* Split the mapped objects into what Notify() can carry and what has to follow
 * as a property Set.  An interface whose properties are ALL deferred is still
 * listed in the payload with an empty map -- that is what makes PIM construct
 * the interface, and a Set on an interface that does not exist yet fails. */
std::map<sdbusplus::message::object_path, Interfaces> splitPayload(
    const std::vector<Object>& objects,
    std::vector<DeferredProperty>& deferred)
{
    std::map<sdbusplus::message::object_path, Interfaces> payload;
    for (const auto& obj : objects)
    {
        Interfaces notifiablePart;
        for (const auto& [iface, props] : obj.interfaces)
        {
            Properties keep;
            for (const auto& [name, value] : props)
            {
                if (notifiable(value))
                {
                    keep[name] = value;
                }
                else
                {
                    deferred.push_back({std::string(inventoryRoot) + obj.path,
                                        iface, name, value});
                }
            }
            notifiablePart[iface] = std::move(keep);
        }
        payload[sdbusplus::message::object_path(obj.path)] =
            std::move(notifiablePart);
    }
    return payload;
}

/* Types Notify() cannot carry (byte, uint64, array[uint16]) go in one at a
 * time through the normal property interface, which takes the real type. */
void setDeferred(sdbusplus::bus_t& bus,
                 const std::vector<DeferredProperty>& deferred)
{
    for (const auto& p : deferred)
    {
        try
        {
            auto m = bus.new_method_call(pimService, p.path.c_str(),
                                         "org.freedesktop.DBus.Properties",
                                         "Set");
            m.append(p.interface, p.name, p.value);
            bus.call(m);
        }
        catch (const std::exception& e)
        {
            /* One property is not worth failing the run over; the rest of the
             * object is already published. */
            fprintf(stderr, "flax-hi-inventory: set %s %s on %s: %s\n",
                    p.interface.c_str(), p.name.c_str(), p.path.c_str(),
                    e.what());
        }
    }
}

int notify(sdbusplus::bus_t& bus,
           const std::map<sdbusplus::message::object_path, Interfaces>& payload)
{
    /* PIM is dbus-activatable but may still be coming up on a cold boot. */
    constexpr int attempts = 5;
    for (int attempt = 1; attempt <= attempts; ++attempt)
    {
        try
        {
            auto m = bus.new_method_call(pimService, pimPath, pimIface,
                                         "Notify");
            m.append(payload);
            bus.call(m);
            return 0;
        }
        catch (const std::exception& e)
        {
            fprintf(stderr, "flax-hi-inventory: Notify attempt %d/%d: %s\n",
                    attempt, attempts, e.what());
            if (attempt == attempts)
            {
                return 1;
            }
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    }
    return 1;
}

} // namespace

int main()
{
    std::vector<Object> objects;
    std::set<std::string> memoryPaths;
    std::set<std::string> cpuPaths;

    unsigned index = 0;
    for (const auto& file : groupFiles("memory"))
    {
        auto j = readJson(file);
        if (!j)
        {
            continue;
        }
        if (auto obj = mapDimm(*j, index))
        {
            memoryPaths.insert(obj->path);
            objects.push_back(std::move(*obj));
        }
        ++index;
    }

    index = 0;
    for (const auto& file : groupFiles("processors"))
    {
        auto j = readJson(file);
        if (!j)
        {
            continue;
        }
        if (auto obj = mapCpu(*j, index))
        {
            cpuPaths.insert(obj->path);
            objects.push_back(std::move(*obj));
        }
        ++index;
    }

    /* PCIe and drives only ever arrive via the OEM push; on the generic
     * fallback these directories hold at most one stripped record. */
    std::set<std::string> pciePaths;
    for (const auto& file : groupFiles("pcie"))
    {
        auto j = readJson(file);
        if (!j)
        {
            continue;
        }
        if (auto obj = mapPcieDevice(*j, file.stem().string()))
        {
            pciePaths.insert(obj->path);
            objects.push_back(std::move(*obj));
        }
    }

    std::set<std::string> drivePaths;
    for (const auto& file : groupFiles("drives"))
    {
        auto j = readJson(file);
        if (!j)
        {
            continue;
        }
        if (auto obj = mapDrive(*j, file.stem().string()))
        {
            drivePaths.insert(obj->path);
            objects.push_back(std::move(*obj));
        }
    }

    if (objects.empty())
    {
        /* Nothing pushed yet.  Not an error -- the host may never have booted
         * since the collections were cleared. */
        fprintf(stderr, "flax-hi-inventory: no inventory under %s\n",
                collectionsRoot);
        return 0;
    }

    auto bus = sdbusplus::bus::new_default();

    addAbsentObjects(bus, ifaceDimm, dimmPrefix, memoryPaths, objects);
    addAbsentObjects(bus, ifaceCpu, cpuPrefix, cpuPaths, objects);
    addAbsentObjects(bus, ifacePcieDevice, pciePrefix, pciePaths, objects);
    addAbsentObjects(bus, ifaceDrive, drivePrefix, drivePaths, objects);

    std::vector<DeferredProperty> deferred;
    const auto payload = splitPayload(objects, deferred);

    const int rc = notify(bus, payload);
    if (rc != 0)
    {
        return rc;
    }

    setDeferred(bus, deferred);

    fprintf(stderr,
            "flax-hi-inventory: published %zu DIMM(s), %zu CPU(s), "
            "%zu PCIe device(s), %zu drive(s), %zu deferred propert%s\n",
            memoryPaths.size(), cpuPaths.size(), pciePaths.size(),
            drivePaths.size(), deferred.size(),
            deferred.size() == 1 ? "y" : "ies");
    return 0;
}
