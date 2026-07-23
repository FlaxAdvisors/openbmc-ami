# OEM BMC Inventory Teardown — Findings (2026-07-23)

Task 1 of the Phase-0 discovery plan. Supersedes the "months of engineering / likely
intractable" verdict: the architecture is now understood and a full payload is captured.

## Sources available

1. **Static image** `/vagrant/WTPC_P407.ima` — AMI MegaRAC SPX flash (64MB). Layout (from
   `$MODULE$` FMH headers): boot@0x3ff00, conf@0x50000, conf2@0x250000, **root@0x450000
   (cramfs @0x460000, ~24MB)**, osimage@0x1b00000, dre@0x1db0000, www@0x1e30000,
   wolfpass@0x3ff0000. Root fs is **cramfs** — mounted read-only via
   `sudo mount -t cramfs -o loop,ro,offset=$((0x460000)) /vagrant/WTPC_P407.ima /mnt/oemroot`.
2. **Live OEM BMC** — running on the target, reachable via
   `sshpass -p superuser ssh -o ProxyCommand="ssh -q -W %h:%p brain" sysadmin@192.168.88.248`.
   Has `redis-cli`/`redis-server`. Currently holds a **full** `/var/tmp/hi_inventory_files/inventory.json`.
3. **Extracted artifacts** in `/vagrant/oem-reference/oem-rootfs/` — IPMIMain, the native
   inventory `.so`, the sync-agent Lua tree, redfish oem lua.

## Architecture (revised — this is the important reframing)

The BIOS does **not** push SMBIOS-style binary structs. It tunnels **Redfish-schema JSON /
Redis operations over an IPMI host-interface on NetFn 0x32 over KCS**. Evidence:

- Captured probe (2026-05-04): NetFn 0x32 cmd 0x2a payload = ASCII
  `smembers Redfish:oem:MappingOut:DeviceList` — a literal **Redis command**.
- Host-interface Lua is named `hi-inventory-helper.lua` ("hi" = host interface); it writes
  `/var/tmp/hi_inventory_files/inventory.json`.
- The captured `inventory.json` is **Redfish-shaped** (see Payload below).
- rootfs ships `redis-server`, `redisrsync`; sync-agent processes inventory.json → Redis
  `Redfish:*` keys → OEM bmcweb serves Redfish.

Pipeline: `BIOS → KCS NetFn 0x32 (Redis/HI ops) → IPMIMain → inventory.json → sync-agent Lua
→ Redis Redfish:* keys → OEM bmcweb → Redfish`.

## Native handler `.so` (offline RE)

`/usr/local/lib/libipmiamioeminventory.so.6.0.0` (ELF32 ARM, stripped) exports:
- `AMISetInvenoryInfo` (0xa14), `AMIGetInvenoryInfo` (0xc50) — command handlers.
- `g_Inventory_CmdHndlr` (.rodata @0xeb0) — command→handler table:
  - entry: `{cmd, priv, handler_ptr, flags...}`, 16 bytes each.
  - **cmd 0x5b → AMIGetInvenoryInfo**, **cmd 0x5a → AMISetInvenoryInfo**.
- References strings `/conf/inv.txt`, `/conf/invphypresence.txt`, `/conf/inventory.ini`.

**Important:** these are cmds **0x5a/0x5b**, NOT the BIOS-observed 0x2a/0x3d/0x5d/0xab. So this
`.so` is the *query/store* interface (Redfish/host reads+writes inventory), **not** the
BIOS-facing receiver. The BIOS-facing NetFn 0x32 handlers live in IPMIMain / the sync-agent
host-interface path, not this lib. The NetFn for this lib is bound at registration in IPMIMain
(the lib itself only carries a feature-name string `CONFIG_SPX_FEATURE_INVENTORY_SUPPORT`).

## Payload captured — `inventory-full.json` (108 KB, 2026-07-23)

`/vagrant/oem-reference/protocol-reverse/live-2026-07-23/inventory-full.json`. Structure:
`{ GroupCrcList{DIMM,CPU,PCIE}, Systems[1], Chassis[1] }`.

- **Systems[0].Processors[2]** — FULL: `Model` "Intel(R) Xeon(R) Gold 6138 ... 20 Core(s),
  40 Logical", `Manufacturer`, `MaxSpeedMHz` 2000, `TotalCores` 20, `TotalThreads` 40,
  `ProcessorId.IdentificationRegisters` 0x00050654BFEBFBFF, plus nested SubProcessors
  (cores→threads). ✅
- **Systems[0].Memory[12]** — FULL: `MemoryDeviceType` DDR4, `BaseModuleType` RDIMM,
  `CapacityMiB` 32768, `Manufacturer` Hynix, `SerialNumber`, `PartNumber`
  "HMA84GR7MFR4N-UH", `MemoryLocation{Socket,Controller,Channel,Slot}`, `DeviceLocator`
  "DIMM A0", `OperatingSpeedMhz` 2400. ✅
- **Systems[0].PCIeDevices[25]** — **`@odata.id` references only, NO data.** Confirms the
  BIOS enumerates PCIe but ships no descriptive fields. Host NIC / add-in cards not
  recoverable from this. ✅ (matches user's known BIOS limitation)
- **Chassis[0].NetworkAdapters[2]** — HAS data: `FirmwarePackageVersion` 14.27.26.06
  (Mellanox), NetworkPorts with `LinkStatus` "Up", `ActiveLinkTechnology` Ethernet.
  **OPEN QUESTION:** is this sourced from the BIOS KCS push or from the BMC's own NC-SI/MCTP
  link to the card? Resolve during the golden-trace capture — it decides whether the host NIC
  is achievable after all.

## Capture method decided (for Task 4)

On the live OEM BMC, during a host POST:
1. `redis-cli monitor` — logs every read/write the host-interface performs, in plaintext
   (the *semantic* layer: which Redfish:* keys are read/written and with what values).
2. `strace -f -e trace=read,write -x -p <IPMIMain pid>` on the KCS fd — the *wire* layer
   (exact NetFn 0x32 request/response bytes, incl. the cmd 0x3d 33-byte handshake response).
3. To force a **full** push (not the ~852-byte delta), clear BIOS NVRAM once
   ("Restore Defaults") — the live box currently already holds full data, so a full trace may
   be obtainable on the next natural full-push or after one NVRAM clear.

Both together = the byte layer mapped to the Redis/Redfish semantic layer = the protocol spec.

## Implication for the design spec

The translator target still works: capture the inventory (CPU/DIMM) and route to our
inventory model. But the *receiver* is a Redis/host-interface responder over NetFn 0x32, not a
struct parser — it must answer the BIOS's read ops (smembers/get on Redfish:* keys) correctly
so POST proceeds, and capture its write ops (the CPU/DIMM/NIC values). Whether we terminate
into `smbios2` (reuse smbios-mdr) or publish D-Bus inventory directly is unchanged by this;
the payload is already parsed JSON, which is easier than SMBIOS structs. Revisit the
smbios2-vs-direct-D-Bus decision once the write-op semantics are captured.
