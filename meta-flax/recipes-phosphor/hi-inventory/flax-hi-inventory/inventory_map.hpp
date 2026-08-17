/*
 * flax-hi-inventory - map host-interface inventory JSON onto D-Bus inventory.
 *
 * This header holds the pure mapping layer: JSON in, D-Bus object/interface/
 * property tables out.  It touches neither the filesystem nor the bus so it can
 * be compiled and exercised natively against captured BIOS payloads (see
 * tools/hi-inventory/).
 */
#pragma once

#include <nlohmann/json.hpp>

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace flax::inventory
{

/* Property values, in the D-Bus type each interface actually declares.
 *
 * Note that Notify() cannot carry all of these.  Its argument type is fixed by
 * the Inventory.Manager interface yaml to
 * variant[boolean,size,int64,uint16,string,array[byte],array[string]] -- byte,
 * uint64 and array[uint16] are not in it, and sdbusplus SKIPS rather than
 * rejects a value it cannot demarshal, so such a property would silently land
 * as zero.  main.cpp splits those out and sets them with
 * org.freedesktop.DBus.Properties.Set after Notify() has created the object,
 * which takes the real type. */
using Value = std::variant<bool, uint8_t, uint16_t, uint32_t, uint64_t, int64_t,
                           std::string, std::vector<uint16_t>>;

/** @brief Whether a value's type is one Notify() can carry. */
bool notifiable(const Value& value);
using Properties = std::map<std::string, Value>;
using Interfaces = std::map<std::string, Properties>;

struct Object
{
    /* Path RELATIVE to /xyz/openbmc_project/inventory -- PIM's updateObjects()
     * prepends its own root, so an absolute path here would be doubled up. */
    std::string path;
    Interfaces interfaces;
};

/* Object path prefixes.  These match what smbios-mdr publishes on Intel
 * platforms, so the Redfish ids come out as dimm0..dimm11 / cpu0, cpu1. */
inline constexpr const char* inventoryRoot = "/xyz/openbmc_project/inventory";
inline constexpr const char* motherboardPath = "/system/chassis/motherboard";
inline constexpr const char* dimmPrefix = "/system/chassis/motherboard/dimm";
inline constexpr const char* cpuPrefix = "/system/chassis/motherboard/cpu";

/* Interface names */
inline constexpr const char* ifaceItem = "xyz.openbmc_project.Inventory.Item";
inline constexpr const char* ifaceDimm =
    "xyz.openbmc_project.Inventory.Item.Dimm";
inline constexpr const char* ifaceMemoryLocation =
    "xyz.openbmc_project.Inventory.Item.Dimm.MemoryLocation";
inline constexpr const char* ifaceCpu = "xyz.openbmc_project.Inventory.Item.Cpu";
inline constexpr const char* ifaceAsset =
    "xyz.openbmc_project.Inventory.Decorator.Asset";
inline constexpr const char* ifaceLocationCode =
    "xyz.openbmc_project.Inventory.Decorator.LocationCode";
inline constexpr const char* ifaceOperationalStatus =
    "xyz.openbmc_project.State.Decorator.OperationalStatus";
inline constexpr const char* ifacePcieDevice =
    "xyz.openbmc_project.Inventory.Item.PCIeDevice";
inline constexpr const char* ifaceDrive =
    "xyz.openbmc_project.Inventory.Item.Drive";

/* PCIe devices and drives hang off the same motherboard path as everything
 * else; bmcweb finds them by interface anywhere under the inventory root and
 * takes the Redfish id from the path leaf. */
inline constexpr const char* pciePrefix =
    "/system/chassis/motherboard/pcie_";
inline constexpr const char* drivePrefix =
    "/system/chassis/motherboard/drive_";

/** @brief DIMM slot index from an SMBIOS device locator.
 *
 *  "DIMM A0" -> 0 ... "DIMM A5" -> 5, "DIMM B0" -> 6 ... "DIMM B5" -> 11.
 *  Deriving the index from the locator rather than from file arrival order is
 *  what keeps dimm<N> pinned to a physical slot across pushes.
 *
 *  @return index, or nullopt if the locator is not in <letter><digit> form.
 */
std::optional<unsigned> dimmIndexFromLocator(const std::string& locator);

/** @brief Map one memory collection member.
 *  @param[in] j - the BIOS's Redfish Memory member.
 *  @param[in] fallbackIndex - slot index to use when the device locator is not
 *                             in the expected form (the file's own number).
 */
std::optional<Object> mapDimm(const nlohmann::json& j, unsigned fallbackIndex);

/** @brief Map one processors collection member. */
std::optional<Object> mapCpu(const nlohmann::json& j, unsigned fallbackIndex);

/** @brief Map one PCIe device (only reachable via the OEM push -- the
 *         generic-Redfish fallback delivers a single stripped record).
 *
 *  bmcweb flattens PCIe functions onto the device object as
 *  Function<N>VendorId / DeviceId / ClassCode / ... , all strings, so a device
 *  with several functions is still one D-Bus object.  Eight is the ceiling
 *  bmcweb scans and the interface defines.
 */
std::optional<Object> mapPcieDevice(const nlohmann::json& j,
                                    const std::string& fallbackId);

/** @brief Map one drive out of the payload's Storage[].Drives[]. */
std::optional<Object> mapDrive(const nlohmann::json& j,
                               const std::string& fallbackId);

/** @brief Sanitise an id into something usable as a D-Bus path element. */
std::string sanitizeId(const std::string& raw, const std::string& fallback);

/** @brief An object marked not-present, for a part that vanished between
 *         pushes.  Redfish renders this as Status.State: Absent. */
Object absentObject(const std::string& path);

} // namespace flax::inventory
