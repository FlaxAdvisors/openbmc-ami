# Phase 2: HI inventory → D-Bus translator

Design 2026-08-13, **implemented and hardware-validated 2026-08-14**.

Prerequisite (committed `94510872d8`): the BIOS pushes inventory over the host
interface and bmcweb persists it under
`/var/lib/flax-inventory/collections/{memory,processors,pcie}/*.json`. This
document is the step that publishes it.

## Result

Redfish now renders the real machine, off the BIOS's own host-interface push:

- `Systems/system/Memory` → 12 members, `dimm0`..`dimm11`, Hynix
  `HMA84GR7MFR4N-UH`, 32 GiB DDR4 RDIMM, per-slot serials, service labels
  `DIMM A0`..`DIMM B5`, MemoryLocation, 2400 MT/s.
- `Systems/system/Processors` → `cpu0`, `cpu1`, Xeon Gold 6138, 20C/40T,
  `ProcessorId.IdentificationRegisters = 0x00050654BFEBFBFF`.
- `Systems/system` summary → `TotalSystemMemoryGiB: 384`, `ProcessorSummary
  {Count: 2, CoreCount: 40}`.

## Architecture (as built)

Recipe `flax-hi-inventory` (`meta-flax/recipes-phosphor/hi-inventory/`): a
**oneshot** C++ binary plus a systemd path unit. Not a daemon — it runs,
publishes, exits.

```
bmcweb POST/DELETE  ->  writes collections/<group>/*.json
                        touches collections/.updated        (patch 0014)
                               |
               systemd .path unit (PathModified)
                               |
     flax-hi-inventory (oneshot): read ALL files -> one Notify() call
                                                -> property Sets for the
                                                   types Notify cannot carry
                               |
         phosphor-inventory-manager hosts the objects
                               |
               bmcweb enumerates -> Redfish Memory / Processors
```

Three deliberate properties:

- **Full republish every run.** Reads the whole tree and sends one `Notify`
  with every object rather than diffing. Idempotent, cannot drift from the
  files, trivial at ~14 objects (a run takes ~2 s).
- **Also runs at boot** (`WantedBy=multi-user.target`), so the files remain the
  source of truth even after the D-Bus objects are lost.
- **Debounce is free.** A systemd path unit will not start a second instance
  while one runs; it re-triggers once afterwards. Twelve rapid DIMM POSTs cost
  one or two runs, and since every run republishes everything, the last is
  always correct.

## The Notify type trap (the one real surprise)

`Notify`'s argument type is fixed by the **interface yaml**, not by PIM:

    dict[object_path,dict[string,dict[string,
        variant[boolean,size,int64,uint16,string,array[byte],array[string]]]]]

`byte`, `uint64` and `array[uint16]` are not in it — and sdbusplus **skips**
rather than rejects a variant it cannot demarshal (`read.hpp`,
`read_single<std::variant>`), so those properties would silently land as zero.
Three properties we need are exactly those types:

| property | type | Redfish field |
|---|---|---|
| `Item.Dimm.MemoryLocation` Socket/MemoryController/Channel/Slot | byte | `MemoryLocation` |
| `Item.Dimm` `AllowedSpeedsMT` | array[uint16] | `AllowedSpeedsMHz` |
| `Item.Cpu` `Id` | uint64 | `ProcessorId.IdentificationRegisters` |

Widening the variant was tried and **rejected**: it means patching
phosphor-dbus-interfaces' yaml (PIM's `types.hpp` only mirrors the generated
signature and fails to compile if it diverges), which rebuilds the whole
phosphor stack.

**What we do instead**: `Notify` creates the objects, then each of those
properties is written with `org.freedesktop.DBus.Properties.Set`, which takes
the property's real type. Every inventory property has a generated
`_callback_set_*`, so this works with stock PIM. An interface whose properties
are *all* deferred (MemoryLocation) is still listed in the Notify payload with
an empty property map — that is what makes PIM construct the interface, and a
Set against a non-existent interface fails. 62 properties are deferred on this
machine; the split is asserted by the native test.

## Property mapping (final)

Names were taken from the bmcweb sources in our build
(`redfish-core/lib/memory.hpp`, `processor.hpp`) and the interface yaml in the
PIM sysroot, then confirmed against the rendered Redfish output.

### DIMM — `/xyz/openbmc_project/inventory/system/chassis/motherboard/dimm<N>`

| our JSON | D-Bus | note |
|---|---|---|
| `CapacityMiB` 32768 | `Item.Dimm.MemorySizeInKB` (u) | ×1024; bmcweb does `>>10`, so this field is KiB despite the name |
| `DataWidthBits` | `Item.Dimm.MemoryDataWidth` (q) | |
| `BusWidthBits` | `Item.Dimm.MemoryTotalWidth` (q) | |
| `MemoryDeviceType` "DDR4" | `Item.Dimm.MemoryType` (enum) | also sets `MemoryMedia = ...MemoryTech.DRAM` |
| `BaseModuleType` "RDIMM" | `Item.Dimm.FormFactor` (enum) | |
| `OperatingSpeedMhz` | `Item.Dimm.MemoryConfiguredSpeedInMhz` (q) | |
| `AllowedSpeedsMHz` | `Item.Dimm.AllowedSpeedsMT` (aq) | **deferred Set**; max also → `MaxMemorySpeedInMhz` |
| `RankCount` | `Item.Dimm.MemoryAttributes` (u) | bmcweb renders this as `RankCount` |
| `DeviceLocator` "DIMM A0" | `Decorator.LocationCode.LocationCode` + `Item.Dimm.MemoryDeviceLocator` + `Item.PrettyName` | → `Location.PartLocation.ServiceLabel` |
| `MemoryLocation.*` | `Item.Dimm.MemoryLocation.*` (y) | **deferred Set** |
| `Manufacturer`/`PartNumber`/`SerialNumber` | `Decorator.Asset.*` | part number is space-padded by the BIOS; trimmed |
| `Status.State`/`Health` | `Item.Present` / `OperationalStatus.Functional` | |
| — | `Item.Dimm.ECC` (enum) | derived: BusWidth > DataWidth ⇒ `MultiBitECC` |

The ECC derivation is not decoration. The BIOS sends no ECC field, but leaving
the property unset is *not* neutral — it keeps its enum default and Redfish
renders `ErrorCorrection: "NoECC"` on a 72-bit ECC RDIMM, which is a wrong
answer rather than a missing one. SMBIOS defines the total width as including
the check bits, so wider-than-data ⇒ ECC.

Fields the BIOS gives us no source for are left unset: `RevisionCode`,
`SparePartNumber`, `Model` (they render as empty strings).

**Slot numbering** comes from the device locator (`A0`..`A5` → dimm0..dimm5,
`B0`..`B5` → dimm6..dimm11), not from file arrival order, so `dimm7` stays the
same physical slot across pushes. Falls back to file order if a locator is not
in `<letter><digit>` form.

**MemoryLocation is passed through as the BIOS reports it**, including its quirk
of flattening `Socket` to 0 for the B bank. The values stay internally
consistent (the B bank is MemoryController 1, channels 3–5) and the service
label carries the truth, so they are published rather than second-guessed.

### CPU — `/xyz/openbmc_project/inventory/system/chassis/motherboard/cpu<N>`

| our JSON | D-Bus |
|---|---|
| `TotalCores` / `TotalThreads` | `Item.Cpu.CoreCount` / `ThreadCount` (q) |
| `MaxSpeedMHz` | `Item.Cpu.MaxSpeedInMhz` (u) |
| `Socket` "0"/"1" | `Item.Cpu.Socket` (s), and picks the object index |
| `ProcessorId.IdentificationRegisters` | `Item.Cpu.Id` (t) — **deferred Set** |
| ″ decoded (CPUID leaf 1 EAX) | `EffectiveFamily` 6, `EffectiveModel` 0x55, `Step` 4 |
| `Manufacturer` | `Decorator.Asset.Manufacturer` |
| `Model` | `Decorator.Asset.Model`, trimmed at the first comma |

The BIOS packs `"Intel(R) Xeon(R) Gold 6138 CPU @ 2.00GHz, 2000 Mhz, 20
Core(s), 40 Logical Processor(s)"` into `Model`; Redfish `Model` is the brand
string and the counts are already reported as TotalCores/TotalThreads, so the
tail is dropped. The `SubProcessors` array (20 cores × 2 threads, ~14 KB of the
file) carries no data not already in the summary and is not mapped.

## Decisions taken on the open questions

1. **Naming** — smbios-mdr's paths and ids (`dimm0`, `cpu0` under
   `system/chassis/motherboard`), so ids match what every other OpenBMC tool
   expects and what CLAUDE.md names as the goal. The human-readable slot lives
   in `Location.PartLocation.ServiceLabel`.
2. **PCIe — deferred.** DIMMs and CPUs are the stated goal; the single PCIe
   record we receive is thin (`Manufacturer: "8086F1A8"`, `Description: "8086
   MASS Slot 3"`) and bmcweb's PCIeDevice path is uninvestigated. The files
   keep accumulating for later.
3. **Removals — marked absent.** Each run asks ObjectMapper which of our
   objects exist and sets `Present=false` / `Functional=false` on any not
   backed by a file; Redfish then shows `Status.State: Absent` instead of a
   phantom part. Verified by removing `memory/11.json` and restoring it.
4. **Unsourced fields — omitted**, except where leaving them unset publishes a
   false value (ECC, above).

## Verified on hardware 2026-08-14

- `flax-hi-inventory` by hand → `published 12 DIMM(s), 2 CPU(s), 62 deferred
  properties`, rc 0, ~2 s.
- `busctl` shows the deferred types landing correctly: `y 5` (Channel),
  `t 1414335950486527` (CPU Id), `aq 1 2400` (AllowedSpeedsMT).
- Redfish Memory = 12 members, Processors = 2, both rendering full detail.
- Path unit: `date > collections/.updated` starts the service and it completes.
- Absent: remove `memory/11.json` → `dimm11` `Status.State: Absent`; restore →
  `Present` true again.
- BMC reboot with the host powered off → inventory still present.

## Two things learned on the box that are worth keeping

- **PIM persists inventory itself.** After the reboot every property was back,
  including the ones written by property Set, before our service had run —
  phosphor-inventory-manager restores from its own cache under
  `/var/lib/phosphor-inventory-manager`. Our boot-time run is therefore a
  re-sync from the files (the authority) rather than the only thing standing
  between us and an empty Redfish after reboot. It still matters: it is what
  recovers inventory if that cache is wiped (rwfs erase) or has drifted.
- **`/usr` is NOT persistent on this build.** The reboot wiped the hot-deployed
  binary, units and bmcweb (`/var` is the only overlay; the collections files
  survived there). Earlier notes claiming hot-deployed `/usr` content survives
  a reboot are wrong — hot-deploys are for the current boot only, and anything
  that must outlive a reboot has to be in the flashed image.
