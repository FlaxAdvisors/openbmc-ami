/*
 * Native test for the flax-hi-inventory mapping layer.
 *
 * Runs against real BIOS payloads captured off the BMC (see samples/), so the
 * property table can be checked without a build, a flash, or a host boot.
 *
 *   make -C tools/hi-inventory test
 */
#include "inventory_map.hpp"

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <string>

using namespace flax::inventory;

namespace
{

int failures = 0;
int checks = 0;

std::string show(const Value& v)
{
    return std::visit(
        [](const auto& x) -> std::string {
            using T = std::decay_t<decltype(x)>;
            if constexpr (std::is_same_v<T, std::string>)
            {
                return "\"" + x + "\"";
            }
            else if constexpr (std::is_same_v<T, bool>)
            {
                return x ? "true" : "false";
            }
            else if constexpr (std::is_same_v<T, std::vector<uint16_t>>)
            {
                std::string s = "[";
                for (size_t i = 0; i < x.size(); ++i)
                {
                    s += (i ? "," : "") + std::to_string(x[i]);
                }
                return s + "]";
            }
            else
            {
                return std::to_string(static_cast<uint64_t>(x));
            }
        },
        v);
}

/* Type tag, so a property that would be marshalled as the wrong D-Bus type is
 * caught here rather than showing up as a zero on the BMC. */
std::string typeOf(const Value& v)
{
    return std::visit(
        [](const auto& x) -> std::string {
            using T = std::decay_t<decltype(x)>;
            if constexpr (std::is_same_v<T, bool>) return "b";
            else if constexpr (std::is_same_v<T, uint8_t>) return "y";
            else if constexpr (std::is_same_v<T, uint16_t>) return "q";
            else if constexpr (std::is_same_v<T, uint32_t>) return "u";
            else if constexpr (std::is_same_v<T, uint64_t>) return "t";
            else if constexpr (std::is_same_v<T, int64_t>) return "x";
            else if constexpr (std::is_same_v<T, std::string>) return "s";
            else return "aq";
        },
        v);
}

void check(bool ok, const std::string& what)
{
    ++checks;
    if (!ok)
    {
        ++failures;
        std::cout << "  FAIL: " << what << "\n";
    }
}

void expectProp(const Object& obj, const char* iface, const char* prop,
                const Value& expected)
{
    auto i = obj.interfaces.find(iface);
    if (i == obj.interfaces.end())
    {
        check(false, std::string(obj.path) + " missing interface " + iface);
        return;
    }
    auto p = i->second.find(prop);
    if (p == i->second.end())
    {
        check(false, std::string(obj.path) + " " + iface + " missing " + prop);
        return;
    }
    if (p->second != expected)
    {
        check(false, std::string(obj.path) + " " + prop + " = " +
                         show(p->second) + " (" + typeOf(p->second) +
                         "), expected " + show(expected) + " (" +
                         typeOf(expected) + ")");
        return;
    }
    ++checks;
}

nlohmann::json load(const std::string& path)
{
    std::ifstream in(path);
    if (!in)
    {
        std::cerr << "cannot open " << path << "\n";
        exit(2);
    }
    return nlohmann::json::parse(in);
}

void dump(const Object& obj)
{
    std::cout << obj.path << "\n";
    for (const auto& [iface, props] : obj.interfaces)
    {
        std::cout << "  " << iface << "\n";
        for (const auto& [name, value] : props)
        {
            std::cout << "    " << name << " (" << typeOf(value)
                      << ") = " << show(value) << "\n";
        }
    }
}

} // namespace

int main(int argc, char** argv)
{
    const std::string samples =
        (argc > 1) ? argv[1] : "samples/collections";

    /* ---- slot index derivation ------------------------------------------ */
    check(dimmIndexFromLocator("DIMM A0") == 0u, "A0 -> 0");
    check(dimmIndexFromLocator("DIMM A5") == 5u, "A5 -> 5");
    check(dimmIndexFromLocator("DIMM B0") == 6u, "B0 -> 6");
    check(dimmIndexFromLocator("DIMM B5") == 11u, "B5 -> 11");
    check(!dimmIndexFromLocator("Onboard").has_value(), "junk -> nullopt");
    check(!dimmIndexFromLocator("DIMM A9").has_value(), "A9 out of range");

    /* ---- DIMM ------------------------------------------------------------ */
    const auto dimm0 = mapDimm(load(samples + "/memory/0.json"), 99);
    check(dimm0.has_value(), "memory/0.json maps");
    if (dimm0)
    {
        check(dimm0->path == "/system/chassis/motherboard/dimm0",
              "dimm0 path, got " + dimm0->path);
        expectProp(*dimm0, ifaceDimm, "MemorySizeInKB", uint32_t{33554432});
        expectProp(*dimm0, ifaceDimm, "MemoryDataWidth", uint16_t{64});
        expectProp(*dimm0, ifaceDimm, "MemoryTotalWidth", uint16_t{72});
        expectProp(*dimm0, ifaceDimm, "MemoryConfiguredSpeedInMhz",
                   uint16_t{2400});
        expectProp(*dimm0, ifaceDimm, "MaxMemorySpeedInMhz", uint16_t{2400});
        expectProp(*dimm0, ifaceDimm, "MemoryAttributes", uint32_t{2});
        expectProp(*dimm0, ifaceDimm, "MemoryType",
                   std::string("xyz.openbmc_project.Inventory.Item.Dimm."
                               "DeviceType.DDR4"));
        expectProp(*dimm0, ifaceDimm, "FormFactor",
                   std::string("xyz.openbmc_project.Inventory.Item.Dimm."
                               "FormFactor.RDIMM"));
        expectProp(*dimm0, ifaceDimm, "MemoryMedia",
                   std::string("xyz.openbmc_project.Inventory.Item.Dimm."
                               "MemoryTech.DRAM"));
        expectProp(*dimm0, ifaceDimm, "AllowedSpeedsMT",
                   std::vector<uint16_t>{2400});
        /* 72-bit bus over a 64-bit data path: the extra bits are ECC. */
        expectProp(*dimm0, ifaceDimm, "ECC",
                   std::string("xyz.openbmc_project.Inventory.Item.Dimm.Ecc."
                               "MultiBitECC"));
        expectProp(*dimm0, ifaceMemoryLocation, "Socket", uint8_t{0});
        expectProp(*dimm0, ifaceMemoryLocation, "MemoryController", uint8_t{0});
        expectProp(*dimm0, ifaceMemoryLocation, "Channel", uint8_t{0});
        expectProp(*dimm0, ifaceMemoryLocation, "Slot", uint8_t{0});
        expectProp(*dimm0, ifaceAsset, "Manufacturer", std::string("Hynix"));
        /* the BIOS pads the part number to 20 chars */
        expectProp(*dimm0, ifaceAsset, "PartNumber",
                   std::string("HMA84GR7MFR4N-UH"));
        expectProp(*dimm0, ifaceAsset, "SerialNumber", std::string("28DCDD40"));
        expectProp(*dimm0, ifaceLocationCode, "LocationCode",
                   std::string("DIMM A0"));
        expectProp(*dimm0, ifaceItem, "Present", true);
        expectProp(*dimm0, ifaceOperationalStatus, "Functional", true);
    }

    /* The B bank must land in the second half of the slot map even though the
     * file that carries it arrives 12th and the BIOS reports Socket 0. */
    const auto dimm11 = mapDimm(load(samples + "/memory/11.json"), 99);
    check(dimm11 && dimm11->path == "/system/chassis/motherboard/dimm11",
          "DIMM B5 -> dimm11");
    if (dimm11)
    {
        expectProp(*dimm11, ifaceLocationCode, "LocationCode",
                   std::string("DIMM B5"));
        expectProp(*dimm11, ifaceMemoryLocation, "MemoryController",
                   uint8_t{1});
        expectProp(*dimm11, ifaceMemoryLocation, "Channel", uint8_t{5});
    }

    /* ---- CPU ------------------------------------------------------------- */
    const auto cpu0 = mapCpu(load(samples + "/processors/0.json"), 99);
    check(cpu0.has_value(), "processors/0.json maps");
    if (cpu0)
    {
        check(cpu0->path == "/system/chassis/motherboard/cpu0",
              "cpu0 path, got " + cpu0->path);
        expectProp(*cpu0, ifaceCpu, "CoreCount", uint16_t{20});
        expectProp(*cpu0, ifaceCpu, "ThreadCount", uint16_t{40});
        expectProp(*cpu0, ifaceCpu, "MaxSpeedInMhz", uint32_t{2000});
        expectProp(*cpu0, ifaceCpu, "Socket", std::string("0"));
        expectProp(*cpu0, ifaceCpu, "Id", uint64_t{0x00050654BFEBFBFFULL});
        /* Skylake-SP: family 6, model 0x55, stepping 4 */
        expectProp(*cpu0, ifaceCpu, "EffectiveFamily", uint16_t{6});
        expectProp(*cpu0, ifaceCpu, "EffectiveModel", uint16_t{0x55});
        expectProp(*cpu0, ifaceCpu, "Step", uint16_t{4});
        expectProp(*cpu0, ifaceAsset, "Manufacturer",
                   std::string("Intel(R) Corporation"));
        expectProp(*cpu0, ifaceAsset, "Model",
                   std::string("Intel(R) Xeon(R) Gold 6138 CPU @ 2.00GHz"));
        expectProp(*cpu0, ifaceItem, "Present", true);
        expectProp(*cpu0, ifaceOperationalStatus, "Functional", true);
    }

    const auto cpu1 = mapCpu(load(samples + "/processors/1.json"), 99);
    check(cpu1 && cpu1->path == "/system/chassis/motherboard/cpu1",
          "socket 1 -> cpu1");

    /* ---- Notify-carriable split ------------------------------------------
     * Notify()'s argument type is fixed by the Inventory.Manager yaml; a value
     * outside it is silently dropped by sdbusplus, so exactly the byte /
     * uint64 / array[uint16] properties must be routed through a property Set
     * instead.  Anything else showing up here means a mapping change would
     * quietly publish a zero. */
    {
        std::set<std::string> deferred;
        for (const Object* obj : {&*dimm0, &*cpu0})
        {
            for (const auto& [iface, props] : obj->interfaces)
            {
                for (const auto& [name, value] : props)
                {
                    if (!notifiable(value))
                    {
                        deferred.insert(name + " (" + typeOf(value) + ")");
                    }
                }
            }
        }
        const std::set<std::string> expected = {
            "AllowedSpeedsMT (aq)", "Channel (y)", "Id (t)",
            "MemoryController (y)", "Slot (y)",    "Socket (y)"};
        check(deferred == expected, [&] {
            std::string s = "deferred set is {";
            for (const auto& d : deferred) s += d + ", ";
            return s + "}";
        }());
    }

    /* ---- absent ---------------------------------------------------------- */
    const Object gone = absentObject("/system/chassis/motherboard/dimm7");
    expectProp(gone, ifaceItem, "Present", false);
    expectProp(gone, ifaceOperationalStatus, "Functional", false);

    /* ---- full dump for eyeballing ---------------------------------------- */
    if (getenv("DUMP") != nullptr)
    {
        if (dimm0) dump(*dimm0);
        if (cpu0) dump(*cpu0);
    }

    std::cout << (failures ? "FAILED " : "ok ") << (checks - failures) << "/"
              << checks << " checks\n";
    return failures ? 1 : 0;
}
