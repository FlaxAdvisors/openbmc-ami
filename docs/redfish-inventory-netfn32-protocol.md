# NetFn 0x32 Inventory Protocol — Findings (Phase 0)

Status: **semantic layer CONFIRMED (live trace 2026-07-23); transport byte-framing PENDING.**

## Executive summary

The TP26 BIOS populates BMC inventory by **tunneling Redis commands over an IPMI
host-interface on NetFn 0x32 / KCS**. IPMIMain on the OEM BMC executes those Redis commands
against a local Redis (unix socket `/var/run/redis/redis.sock`) and returns the replies. A
sync-agent + OEM bmcweb then serve the `Redfish:*` Redis keys as Redfish. There is no
SMBIOS-struct push; the "protocol" is essentially **redis-over-IPMI**.

This means the native receive side we implement is a **Redis-command responder reachable over
the NetFn 0x32 KCS transport**, plus a translator from the resulting inventory into our
OpenBMC inventory model.

## Two Redis databases

- **db1** — OEM/host-interface working set: `Redfish:oem:MappingOut:*`,
  `Redfish:oem:ami:inventory:crc:GroupCrcList`.
- **db0** — main Redfish model: `Redfish:Systems:Self:*`, `Redfish:Chassis:Self:*`,
  `Redfish:Oem:Ami:*`, `Redfish:InventoryData:PostStatus:*`.

## Delta-push conversation (CONFIRMED, live trace, unchanged hardware)

Source: `/vagrant/oem-reference/protocol-reverse/live-2026-07-23/redis-monitor-postcycle.log`
(redis MONITOR during a `chassis power cycle`).

```
db1  smembers Redfish:oem:MappingOut:DeviceList        # cmd 0x2a probe; returns EMPTY → BIOS proceeds
db0  GET      Redfish:InventoryData:PostStatus:Status
db1  HGETALL  Redfish:oem:ami:inventory:crc:GroupCrcList# BIOS reads BMC's cached per-group CRCs
db0  GET      Redfish:Oem:Ami:InventoryData:LastModified
db0  SET      Redfish:InventoryData:PostStatus:Status "Ready"
db0  SET      Redfish:Oem:Ami:InventoryData:LastModified <epoch>   (+ Status:LastModified, Oem:Ami:LastModified, Oem:LastModified)
db0  SET      Redfish:InventoryData:PostStatus:Status "In-Progress"
db1  HMGET    Redfish:oem:ami:inventory:crc:GroupCrcList DIMM CPU PCIE
db1  DEL      Redfish:oem:ami:inventory:crc:GroupCrcList
db1  HSET     Redfish:oem:ami:inventory:crc:GroupCrcList CPU <crc> PCIE <crc> DIMM <crc>   # BIOS writes new CRCs
db0  SET      Redfish:InventoryData:PostStatus:Status "Completed"
db0  SET      Redfish:InventoryData:PostStatus:ProcessingTime "420.00"
db0  HSET     Redfish:InventoryData:PostStatus:Messages 1 "Warning PropertyMissing (Id : Redfish:Chassis)"
db0  HSET     Redfish:InventoryData:PostStatus:Messages 2 "Warning PropertyMissing (Id : Redfish:Systems)"
```

Interpretation: when the BIOS's computed group CRC == the CRC cached in Redis, it pushes **no
data** for that group (the PropertyMissing warnings are the tell). Delta detection is gated on
`Redfish:oem:ami:inventory:crc:GroupCrcList`, which lives **in the BMC's Redis** and is read
by the BIOS at the start of each push.

## Forcing a full push (CONFIRMED mechanism, not yet traced)

`redis-cli -s /var/run/redis/redis.sock -n 1 DEL Redfish:oem:ami:inventory:crc:GroupCrcList`
before a power cycle → the BIOS reads no cached CRC → CRC mismatch → pushes **full** CPU/DIMM
data (HSETs into `Redfish:Systems:Self:Memory:*` / `Processors:*`). This avoids a BIOS NVRAM
clear. (The earlier claim that the gate was only in BIOS NVRAM is superseded: the BMC-side
Redis CRC is the operative gate for this OEM firmware.)

## Full payload schema (CONFIRMED)

`/vagrant/oem-reference/protocol-reverse/live-2026-07-23/inventory-full.json` (108 KB) and the
live Redis state (3567 keys). Redfish-shaped. Processors[2] and Memory[12] fully populated;
PCIeDevices[25] = @odata.id refs only; Chassis.NetworkAdapters[2] populated (Mellanox) —
source TBD.

## SCOPE REVISION (full-push capture 2026-07-23) — richer than SMBIOS

Forced a full push (`DEL` GroupCrcList + cycle); capture in
`live-2026-07-23/redis-monitor-fullpush.log`. The full push writes granular per-field Redis
keys for the complete Redfish model, bracketed by
`SET Redfish:BIOSInventoryTransferComplete false … true`:

- **Processors** `Redfish:Systems:Self:Processors:DevType1_CPU0:*` — Model, Manufacturer,
  MaxSpeedMHz, ProcessorId:{IdentificationRegisters,EffectiveFamily}, Socket, SubProcessors. ✅
- **Memory** `Redfish:Systems:Self:Memory:DevType2_DIMM0..11:*` — CapacityMiB, BaseModuleType,
  DeviceLocator, DataWidthBits, AllowedSpeedsMHz, PartNumber, SerialNumber. ✅
- **PCIe / host NIC** `Redfish:Chassis:Self:PCIeDevices:<bdf>:*` — full VendorId/DeviceId/
  DeviceClass/ClassCode per function. Includes the Intel mass-storage controller **and the
  Mellanox host NIC**: `PCIeDevices:00_5E_00:Description "15B3 NIC Slot 2"`, Manufacturer
  `15B31015` (15B3=Mellanox, 1015=ConnectX-4 Lx). ✅

**This supersedes the earlier "PCIe/host NIC not recoverable" scoping** (which was based on the
inline `Systems[].PCIeDevices` being @odata.id refs only). The AMI NetFn 0x32 path carries
PCIe device identity the SMBIOS/MDR path never did.

Architecture nuance confirmed: the granular Redfish key writes are done by the **sync-agent**
after `BIOSInventoryTransferComplete=true` (it reads `inventory.json`), not by the BIOS
directly. The BIOS's own KCS ops are (a) the control handshake (redis-tunneled: smembers
MappingOut, CRC read/write) and (b) a **bulk transfer of inventory.json content over KCS**
that is NOT redis-visible. For our native receiver we replicate the handshake + the bulk
transfer, produce our own `inventory.json`, then run **our own** translator (no OEM
sync-agent, no Redis required by us).

### Design implication (for the spec)

The AMI payload is **Redfish-shaped and richer than SMBIOS** (PCIe functions, NIC identity).
Routing it through `smbios2`/smbios-mdr would be **lossy** (SMBIOS Type 4/17 can't represent
PCIe-function/NIC detail). Reconsider the translator target: publish directly into the
OpenBMC D-Bus inventory model (and/or a Redfish-shaped store) rather than smbios2, so the
PCIe/NIC richness survives. Revisit once the bulk-transfer framing is known.

## KCS byte framing — CAPTURED & DECODED (2026-07-23, LD_PRELOAD kcshook)

Capture: `live-2026-07-23/kcs-bytes-fullpush.txt` (LD_PRELOAD read/write/ioctl logger on
IPMIMain, during a forced full push). KCS message framing at the read()/write() layer:

```
request : [seq] [netfn<<2|lun] [cmd] [data...]
response: [seq] [netfn<<2|lun] [cmd] [cc] [data...]
```
`seq` = AMI kcs.ko match tag (driver artifact; not part of the IPMI message our OpenBMC KCS
bridge would deliver). netfn 0x32 → nl byte 0xC8; response netfn 0x33 → 0xCC.

**The complete NetFn 0x32 conversation is a small CONTROL/bootstrap handshake (~14 msgs):**
- `cmd 0x2a` req `01 00`+ASCII redis cmd `smembers Redfish:oem:MappingOut:DeviceList`;
  resp cc=`0xCC` when the set is empty → BIOS proceeds.
- `cmd 0x3d` req `01 00 07` (Param/Set/BlockSelector); resp cc=`00` + `07 07 07`
  (device-status bytes — **3 bytes here, not the 33 the old memory guessed**).
- `cmd 0x5d` req `01`/`02`/`04`; resp cc=`00` + token, e.g. `0a 0c "HostAutoFWTEaPA4R4OqrX"`,
  `"HostAutoOSECKN6h0qWEQw"` — **Redfish Host Interface session credentials**.
- `cmd 0xaa`/`0xab` — small acks / version (`00 01`).

## KEY DISCOVERY — bulk inventory is Redfish Host Interface, NOT KCS

The 108KB inventory does **not** traverse KCS. The full-push KCS capture had only 284 small
messages (control), none carrying inventory data, yet inventory.json filled to 108KB. The
`cmd 0x5d` `HostAuto*` tokens are **Redfish Host Interface credentials**. Confirmed on the box:
- `usb0` @ `169.254.0.17` = USB virtual-NIC host-interface network.
- redis has the DMTF model `Redfish:Managers:Self:HostInterfaces:Self:*`
  (AuthenticationModes, FirmwareAuthRoleId, ManagerEthernetInterface, ComputerSystems link).
- OEM ships `spx_restservice_hostinterface`.

So the real architecture is **two transports**:
1. **KCS NetFn 0x32** — bootstrap: BIOS gets the device list, device status, and a session
   credential (the `HostAuto*` tokens). Fully captured/decoded above.
2. **Redfish Host Interface over `usb0`** — the BIOS authenticates with that credential and
   PATCHes/POSTs the inventory to the BMC's Redfish over the USB vNIC → redis → inventory.json.

### Implication for our native implementation

The receiver is NOT a KCS→smbios shim. It is:
- (a) a **KCS NetFn 0x32 bootstrap handler** (device list = empty ok, device status 0x3d,
  and issue a host-interface credential via 0x5d), plus
- (b) a **Redfish Host Interface endpoint** (USB vNIC + a Redfish/HTTP surface the BIOS pushes
  inventory to). GOOD NEWS: we already have the USB vNIC working (see
  `topic_inband_virtual_nic` — CDC-ECM gadget, host reaches BMC Redfish over the internal
  link), and OpenBMC bmcweb supports the DMTF Redfish Host Interface. Not starting from zero.

## Redfish Host Interface HTTP layer — RESOLVED (offline RE, 2026-07-23)

Reverse-engineered offline from the OEM's `spx_restservice_hostinterface` + the Redfish HI
handlers/routes (no live capture needed). The BIOS acts as a **Redfish client over `usb0`**,
authenticating as the host-interface firmware account and pushing inventory to standard
Redfish resource URLs. Handlers live in
`usr/local/redfish/extensions/host-interface/hi-handlers/*-hi.lua`; routes in
`extensions/routes/hi_routes.lua` and `oem/ami_hi/route.lua`.

**Auth:** account `HI-FW` under `/redfish/v1/AccountService/Accounts/HI-FW`; the password is
the credential the BMC issues over KCS `cmd 0x5d` (the `HostAuto*` tokens).

**Inventory resource routes the BIOS writes (URL regex → handler):**
- `/Systems/{id}/Processors` , `/Processors/{id}` , nested `/SubProcessors/...` → processor-*-hi
- `/Systems/{id}/Memory` , `/Memory/{id}` , `/MemoryDomains/...` , `/MemoryChunks/...` , `/Memory/{id}/Metrics`
- `/Chassis/{id}/PCIeDevices` , `/PCIeDevices/{id}` , `/PCIeDevices/{id}/Functions/{id}` → pciedevice/pciefunction-hi
- `/Chassis/{id}/NetworkAdapters` , `/NetworkDeviceFunctions/...` → networkadapter-hi (host NIC)
- `/Systems/{id}/Storage/{id}/Drives/{id}` → drives-instance-hi
- `/Systems/{id}/EthernetInterfaces` , `/NetworkInterfaces` , `/Bios` , `/SecureBoot` , `/BootOptions`
- `/Chassis` , `/Systems`

**AMI OEM bulk endpoints (`oem/ami_hi/route.lua`):**
- `/redfish/v1/Oem/Ami/InventoryData` , `/Oem/Ami/InventoryData/Status` → hi-inventory-data,
  inventory-data-status (this is the bulk inventory.json push + its post-status; matches the
  redis `Redfish:Oem:Ami:InventoryData:*` + `InventoryData:PostStatus:*` keys seen in the
  monitor trace, and the `/var/tmp/hi_inventory_files/inventory.json` artifact).
- `/redfish/v1/Oem/Ami/BiosStaticFiles` , `/BiosStaticFiles/PostStatus/{id}` → BIOS uploads
  static files (incl. the inventory blob) via the host interface.

## FULL PROTOCOL SUMMARY (Phase 0 complete)

1. **KCS NetFn 0x32 bootstrap** (captured, byte-exact): BIOS probes device list (`0x2a`),
   reads device status (`0x3d`), and is issued Redfish HI credentials (`0x5d` → `HostAuto*`).
2. **Redfish Host Interface over `usb0`** (schema RE'd): BIOS authenticates as `HI-FW` with
   that credential and pushes inventory — bulk to `/Oem/Ami/InventoryData` (→ inventory.json)
   and/or per-resource to the standard Processors/Memory/PCIeDevices/NetworkAdapters/Drives
   URLs. BMC persists to redis → OEM bmcweb serves Redfish.

**For our native reimplementation** (target: OpenBMC D-Bus inventory, per the design):
- (a) KCS `0x32` bootstrap handler: answer `0x2a` (empty ok), `0x3d` (device status), and
  `0x5d` (issue a credential we then accept on the HI).
- (b) Redfish Host Interface endpoint on our bmcweb over our existing USB vNIC
  ([[topic_inband_virtual_nic]]): an `HI-FW`-style account + accept the BIOS's inventory push
  (bulk `/Oem/Ami/InventoryData` or the per-resource routes) → translate to our D-Bus
  inventory model.
- Open refinement (minor): exact HTTP method (POST vs PATCH) and whether the BIOS prefers the
  bulk `/Oem/Ami/InventoryData` route vs per-resource — resolvable from the `hi-inventory-data.lua`
  handler or a single future access-log line; not a blocker for planning.


MONITOR gives the *semantic* layer (which Redis commands, which keys/values). It does NOT show
how each Redis command/reply is framed inside the NetFn 0x32 KCS messages. Known from the
2026-05-04 KCS capture:
- cmd 0x2a request payload = `01 00` + ASCII redis command (`smembers Redfish:...`) + `00`.
- cmd 0x3d expects a 33-byte `{CC, DevStatus[32]}` response.
- cmd 0x5d (1-byte payload), cmd 0xab (empty) — roles unmapped.

To implement the receiver we must know, byte-for-byte:
1. How a Redis command is carried in the request (cmd 0x2a and possibly others).
2. How the Redis reply is serialized into the response (esp. multi-part replies; likely the
   role of cmd 0x3d / chunked reads).
3. The exact 33-byte cmd 0x3d response contents and how the BIOS uses them.

Capture options (no `strace` on the BMC): (a) LD_PRELOAD read/write logger on the KCS fds,
injected by restarting IPMIMain (ARM cross-toolchain available); (b) IPMIMain NetFn 0x32
handler disassembly (stripped ARM); (c) an AMI IPMIMain packet-debug mode if one exists.

## Live-box access (for resuming)

- OEM BMC: `sshpass -p superuser ssh -o ProxyCommand="ssh -q -W %h:%p brain" sysadmin@192.168.88.248`
- Redis: `redis-cli -s /var/run/redis/redis.sock` (db0 default; inventory CRC in `-n 1`)
- Host power (from BMC): `ipmitool -I lanplus -H 127.0.0.1 -U admin -P admin chassis power cycle|status`
- IPMIMain pid owns `/dev/kcs0..2`.
