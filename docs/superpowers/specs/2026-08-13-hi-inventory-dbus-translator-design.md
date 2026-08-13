# Phase 2: HI inventory → D-Bus translator

Design, 2026-08-13. **Architecture section APPROVED. Property mapping below is
drafted but NOT yet reviewed — pick up there.**

Prerequisite (done, committed `94510872d8`): the BIOS pushes inventory over the
host interface and bmcweb persists it under
`/var/lib/flax-inventory/collections/{memory,processors,pcie}/*.json`. Nothing
publishes it yet — this design is that step.

## Architecture (APPROVED)

New recipe `flax-hi-inventory`: a **oneshot** C++ binary plus a systemd path
unit. Not a daemon — it runs, publishes, exits.

```
bmcweb POST/DELETE  ->  writes collections/<group>/*.json
                        touches collections/.updated
                               |
               systemd .path unit (PathModified)
                               |
     flax-hi-inventory (oneshot): read ALL files -> one Notify() call
                               |
         phosphor-inventory-manager hosts the objects
                               |
               bmcweb enumerates -> Redfish Memory / Processors
```

Three deliberate properties:

- **Full republish every run.** Reads the whole tree and sends one `Notify` with
  every object rather than diffing. Idempotent, cannot drift from the files, and
  trivial at ~15 objects.
- **Also runs at boot** (`WantedBy=multi-user.target`). This is the main reason
  it is a separate service rather than living in bmcweb: the JSON is on the
  persistent overlay, so inventory survives a BMC reboot without waiting for the
  host to push again.
- **Debounce is free.** A systemd path unit will not start a second instance
  while one runs; it re-triggers once afterwards. Twelve rapid DIMM POSTs cost
  one or two runs, and since every run republishes everything, the last is
  always correct.

Only bmcweb change needed: touch `.updated` after each collection write — a
couple of lines added to patch 0013.

## Key facts established (do not re-derive)

- `phosphor-inventory-manager` **is running** on the BMC as
  `xyz.openbmc_project.Inventory.Manager`, and exposes at
  `/xyz/openbmc_project/inventory`:

      .Notify   method   a{oa{sa{sv}}}

  i.e. object path -> interface -> property -> variant. **We do not need to
  write a D-Bus object server** — PIM hosts the objects and bmcweb finds them
  via ObjectMapper.
- **No python on the BMC.** Anything we ship is C++ or POSIX shell. Building
  `a{oa{sa{sv}}}` via `busctl` in shell is impractical, hence C++.
- Ground is clear — no collision with the SMBIOS path: 0 `Item.Dimm` objects,
  0 `Item.Cpu`, `smbios-mdr` inactive, `/var/lib/smbios` empty, and Redfish
  Memory/Processors both report `Members@odata.count: 0`.

## Property mapping (DRAFT — needs review)

Property names below were extracted from the bmcweb sources actually in our
build (`redfish-core/lib/memory.hpp`, `processor.hpp`), not from upstream docs.

### DIMM — `xyz.openbmc_project.Inventory.Item.Dimm`

| our JSON | D-Bus property | note |
|---|---|---|
| `CapacityMiB` (32768) | `MemorySizeInKB` | ×1024 |
| `DataWidthBits` (64) | `MemoryDataWidth` | |
| `BusWidthBits` (72) | `MemoryTotalWidth` | |
| `MemoryDeviceType` ("DDR4") | `MemoryType` | map to `...Item.Dimm.DeviceType.DDR4` enum |
| `OperatingSpeedMhz` (2400) | `MemoryConfiguredSpeedInMhz` | |
| `AllowedSpeedsMHz` ([2400]) | `AllowedSpeedsMHz` | |
| `MemoryLocation.Socket/MemoryController/Channel/Slot` | `Socket`, `MemoryController`, `Channel`, `Slot` | |
| `DeviceLocator` ("DIMM A0") | `LocationCode` | on `Decorator.LocationCode` |

Plus `xyz.openbmc_project.Inventory.Decorator.Asset`: `Manufacturer`,
`PartNumber`, `SerialNumber`. Plus `Inventory.Item` `Present=true` and
`State.Decorator.OperationalStatus` `Functional=true`.

Other names bmcweb reads and we have no source for yet: `ECC`,
`MemoryAttributes`, `RevisionCode`, `SparePartNumber`, `Model`.

### CPU — `xyz.openbmc_project.Inventory.Item.Cpu`

| our JSON | D-Bus property |
|---|---|
| `TotalCores` (20) | `CoreCount` |
| `TotalThreads` (40) | `ThreadCount` |
| `MaxSpeedMHz` (2000) | `MaxSpeedInMhz` |
| `Model` (full brand string) | `Model` |
| `Manufacturer` | `Decorator.Asset.Manufacturer` |

Others bmcweb reads: `EffectiveFamily`, `EffectiveModel`, `Microcode`, `Step`,
`Version`, `Id`, `PartNumber`, `SerialNumber`, `Present`, `Functional`. The CPU
JSON is ~14 KB with a `SubProcessors` array — inspect it for these before
deciding what to drop.

## Open questions for the next session

1. **Object paths / naming.** Proposal:
   `/xyz/openbmc_project/inventory/system/memory/dimm<N>` and
   `.../system/processor/cpu<N>`, derived from `MemoryLocation`/`Socket` rather
   than file order so ids are stable across pushes. Needs deciding.
2. **PCIe.** `collections/pcie/` has real data but bmcweb's PCIeDevice rendering
   path was not investigated. Possibly defer — DIMMs and CPUs are the stated
   goal in CLAUDE.md.
3. **Removal semantics.** `Notify` adds/updates; it does not delete. If a DIMM
   disappears between pushes its stale object persists. Options: accept it,
   or have the translator mark absent objects `Present=false`.
4. Whether to populate the fields we have no source for, or omit them.

## Testing

Testable without a host boot — the files are already on disk:

- run the oneshot by hand, then
  `busctl call ... GetSubTreePaths ... Item.Dimm` should return 12
- `curl /redfish/v1/Systems/system/Memory` → `Members@odata.count: 12`
- one member should render Hynix `HMA84GR7MFR4N-UH`, 32 GiB, `DIMM A0`
- `curl /redfish/v1/Systems/system/Processors` → 2, Xeon Gold 6138 20C/40T
- reboot the BMC with the host off → inventory should still be there
