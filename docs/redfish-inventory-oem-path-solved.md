# The OEM InventoryData path, captured 2026-08-17

The OEM BMC chip was swapped into the box and the host booted once with a
redis monitor running. That single cycle answered every open question about
the AMI OEM inventory protocol. Artifacts:
`/vagrant/oem-reference/live-2026-08-17/`.

| file | what it is |
|---|---|
| `hi-InventoryData.json` | **the 4135-byte GET body** we spent three crashed attempts guessing at |
| `pushed-inventory.json` | the BIOS's actual 108 KB push payload, as the OEM stored it |
| `monitor.log.gz` | every redis command during the push, values included |
| `redis-db0.tsv` | 3688 keys, TYPE-aware, post-push |
| `hi-*.json` | service root, Chassis/Self, Systems/Self, Memory, Processors, Storage |
| `host-lspci.txt` | the host OS's own PCIe view, for correlation |

## How to read the resource at all (this took a while)

The endpoint is **gated by source address**, and it fails closed as **404**,
not 403 — with a perfectly valid administrator credential:

```
curl -u Administrator:superuser https://192.168.88.248/redfish/v1/Oem/Ami/InventoryData
    -> 401 with sysadmin (wrong account), 404 with Administrator (right account)
```

From the BMC itself, sourced from the host-interface address, it appears:

```
wget -O - --header "Authorization: Basic <b64>" \
     http://169.254.0.17/redfish/v1/Oem/Ami/InventoryData      -> 4135 bytes
```

`169.254.0.17` is the OEM's `usb0`; requests from `127.0.0.1` or the LAN 404.
Note plain HTTP on port 80 works, which matters because this firmware's
busybox `wget` has no TLS and its `openssl` is a stub with only `req`/`x509`.
This is the same peer-subnet gate our own implementation uses — the OEM just
answers 404 where we answer 403/405.

**Before the first push the OEM also answers 404.** Redis had zero
`InventoryData` keys after boot (the persisted `/conf/redis-dump.rdb.gz`
failed to load — the `gzip: invalid magic` line on the console), and the
resource did not exist until the BIOS pushed. So 404-until-populated is the
OEM's own behaviour in the empty state, and the BIOS is plainly fine with it:
this box POSTs successfully in exactly that condition.

## What the body contains

Top-level keys of `hi-InventoryData.json`, all of which the BIOS evidently
parses:

- `@odata.context` / `@odata.id` / `@odata.etag` — the etag is `W/"<LastModified>"`,
  the same epoch stored at `Redfish:Oem:Ami:InventoryData:LastModified`.
- `BiosStaticFiles` — **a filename → CRC32 map** of the seven BIOS web assets
  (`Index.html`, `Index.js`, `Index.css`, `RbLogo.png`, `ComboButton.png`,
  `Favicon.ico`, `SetupData.xml`).
- `Chassis` — links to `Chassis/Self`, its `NetworkAdapters` and `Thermal`.
- `DRE` — the four dynamic Redfish extensions, each with `Id`, `Md5Checksum`
  and `Running: true`.
- `NetworkDeviceFunctions` — MACs of the host NICs (including the internal
  virtual NIC), with `iSCSIBoot` allowable-value lists.
- `Registries` — `Members` list, including `BiosAttributeRegistryTPCH.0.52.0.`
- `SecureBoot` — current state **plus the `#SecureBoot.ResetKeys` action and
  its `@Redfish.ActionInfo`**.
- `System` — links for Bios, Boot, EthernetInterfaces, Memory, Processors,
  Storage … and, nested at
  `System.Oem.Ami.Inventory.Crc.GroupCrcList`:
  `[{"CPU":3032237160},{"PCIE":98483978},{"DIMM":2764192848}]`

## Three long-standing divergences, explained

From `COMPARISON-2026-08-11.md`, we could not explain why the OEM saw
different BIOS behaviour than we did. The body explains it:

1. **`BiosStaticFiles` posted ×1 batched (OEM) vs ×7 one-at-a-time (us).**
   The body advertises a CRC per asset. The BIOS compares and uploads only
   what changed. Our 191-byte stub advertised none, so the BIOS re-uploaded
   all seven, every boot.
2. **`GET SecureBoot.ResetKeys` (OEM) vs never requested (us).** The body
   hands the BIOS that action target and its ActionInfo. No advertisement, no
   request.
3. **`POST Oem/Ami/InventoryData` (OEM) vs never sent (us).** The BIOS only
   pushes to an endpoint the body describes as available.

So the divergences were never independent mysteries — they are all downstream
of the one resource we could not serve.

## The push is a state machine (new)

From `monitor.log`, one boot, times relative:

```
GET  Redfish:InventoryData:PostStatus:Status          <- BIOS polls first
GET  Redfish:Oem:Ami:InventoryData:LastModified
DEL  ...PostStatus:{DeletedModules,Messages,ProcessingTime}
SET  ...PostStatus:Status  "Ready"                    <- BMC accepts
SET  ...PostStatus:Status  "In-Progress"
   ... 23 seconds of parsing ...
SET  ...PostStatus:Status  "Completed"
SET  ...PostStatus:ProcessingTime "23040.49"
HSET ...PostStatus:Messages 1 "Warning PropertyMissing (Id : Redfish:Chassis)"
HSET ...PostStatus:Messages 2 "Warning PropertyMissing (Id : Redfish:Systems)"
HSET Redfish:oem:ami:inventory:crc:GroupCrcList CPU/PCIE/DIMM
```

The BIOS polls `PostStatus:Status` before and during; the BMC takes ~23 s to
process a 108 KB payload and reports non-fatal warnings back through
`Messages`. Nothing we ever served had this structure, which is a plausible
mechanism for the `#GP at RIP 674D113B`: a driver walking a status object that
is not there.

## The CRCs come FROM the BIOS — there is nothing to reverse

This retires what memory recorded as the open Phase-2 task ("reconstructing
that table from the redis dumps"). The BIOS's own push payload carries them:

```json
{ "GroupCrcList": {"DIMM": 2764192848, "CPU": 3032237160, "PCIE": 98483978},
  "Systems": [...], "Chassis": [...] }
```

The BMC stores those values verbatim (`HSET …crc:GroupCrcList` at the end of
processing) and echoes them back in the next GET. **We do not need to compute
a CRC; we need to remember one.** That the CPU and DIMM values are byte-identical
to the May capture months earlier is consistent: the BIOS derives them from
hardware that has not changed. PCIE differs (`98483978` vs `3797810510`),
which is the mechanism by which the BIOS decides a group needs re-pushing.

## What one push actually delivers

`pushed-inventory.json`, one 108 KB POST:

- `Systems[0]`: 12 Memory, 2 Processors, PCIeDevices, PCIeFunctions, Storage,
  MemorySummary, ProcessorSummary, SecureBoot, TrustedModules, UUID,
  BiosVersion, SKU, SerialNumber, EthernetInterfaces
- `Chassis[0]`: 25 PCIe devices / **47 functions** with VendorId, DeviceId,
  ClassCode, RevisionId, SubsystemId, SubsystemVendorId, DeviceClass;
  2 NetworkAdapters; ChassisType, SKU, SerialNumber

That is the entire CLAUDE.md inventory wish list — PCIe, Storage and
FabricAdapters included — in a single request we currently refuse.

## Second boot: the delta path (`boot2-delta/`)

The box was rebooted with nothing changed, so the BIOS recomputed its CRCs and
found all three matching what the BMC advertises. Result:

```
GET  Redfish:InventoryData:PostStatus:Status      <- BIOS polls
HGETALL Redfish:oem:ami:inventory:crc:GroupCrcList   } BMC assembling
HGETALL Redfish:BiosStaticFiles:Crc                  } the GET body
GET  Redfish:Oem:Ami:InventoryData:LastModified      }
   ... ~21 s later, the BIOS posts anyway ...
SET  PostStatus:Status "Ready" -> "In-Progress" -> "Completed"
SET  PostStatus:ProcessingTime "320.00"           <- vs 23040.49 on a full push
HSET crc:GroupCrcList CPU/PCIE/DIMM               <- same three values re-asserted
```

**Zero** Memory, Processor or PCIe writes hit redis this boot (1106 PCIe and 292
memory lines on the full push, 0 and 0 here), and the static assets were not
re-uploaded — only the CRC map was read. The push itself shrank from 108 KB to
**850 bytes**, and processing from 23 s to 320 ms.

`delta-push.json` is that 850-byte body: `GroupCrcList` plus static identity
only — Manufacturer, SerialNumber, SKU, BiosVersion, UUID, Status,
TrustedModules for Systems, and Manufacturer/SerialNumber/SKU/ChassisType for
Chassis. The three heavy groups are simply absent.

This confirms the CRC advertisement is what buys the steady state: matching
CRCs mean the BIOS skips both the inventory groups and the seven static assets.
Our current 191-byte stub advertises nothing, which is why our BMC eats a full
re-push on every single boot.

Two implementation consequences:

- **The delta payload overwrote `/var/tmp/hi_inventory_files/inventory.json`**
  (108689 -> 850 bytes) while redis kept the full inventory — 25 PCIe devices
  and 266 memory keys still present. The last received payload is therefore NOT
  the inventory; the store is. Any receiver must merge per group, never replace
  wholesale, or a no-change boot would erase everything.
- Advertising a CRC we cannot honour would be worse than advertising none: the
  BIOS would skip a group we do not actually hold.

## Implemented (bmcweb patch 0015, commit 195c9031dc)

The GET now returns the captured document shape, and the POST normalizes an
OEM push into the collection layout `flax-hi-inventory` already reads. The
per-item schemas are byte-identical between the OEM payload and the
generic-Redfish fallback, so the translator needed **no changes at all** — its
51 offline checks still pass untouched.

What the handler does:

- **Opt-in, inverted.** Absent `/var/lib/flax-inventory/enable-inventorydata-get`
  it answers 405, the behaviour proven to boot. The old flag was a *disable*
  file that had to be present to be safe, which meant an rwfs erase silently
  re-armed the crashing path — a live landmine on the shipped image.
- **`BiosStaticFiles`** carries a real CRC-32 per stored asset, so the BIOS
  uploads only what changed instead of all seven files every boot.
- **`GroupCrcList`** is read back from `groupcrc.json`, written verbatim from
  the BIOS's own push. Zeros while we hold nothing, which reads as stale for
  every group and asks for a full push.
- **`SecureBoot` omitted; `DRE` and `NetworkDeviceFunctions` present but empty**
  — see the divergences above.
- **The normalizer merges per group**, never wholesale, so an 850-byte
  no-change delta cannot erase the inventory.

### Verified offline, with no host boot

Hot-deployed, enabled with the LAN debug flag, and diffed against
`hi-InventoryData.json` (`ours-inventorydata-2026-08-17.json` is the result):

| check | outcome |
|---|---|
| top-level keys | all 9 of the OEM's, minus the deliberate `SecureBoot`; nothing extra |
| `System` sub-keys | identical minus `SecureBoot` |
| `GroupCrcList` shape | `[{"CPU":n},{"PCIE":n},{"DIMM":n}]`, matching |
| `BiosStaticFiles` CRCs | **6 of 7 byte-identical to the OEM's own values** |

That six-way CRC match is the strongest evidence available without a host boot:
it confirms the CRC-32 variant independently, using files we already held. The
seventh, `SetupData.xml`, differs because our stored copy genuinely differs —
the mechanism working as intended.

### How to enable it (and how to get back)

```bash
# arm it, then power-cycle the host
touch /var/lib/flax-inventory/enable-inventorydata-get
# recover: one ssh command + a host power cycle, no reflash
rm -f /var/lib/flax-inventory/enable-inventorydata-get
```

`allow-lan-inventorydata-get` additionally exposes the GET to the management
LAN for diffing. It is a debug affordance — remove it after testing.

Two things to know before arming it:

- A **hot-deployed** bmcweb does not survive a BMC reboot (`/usr` is not
  persistent), so a real test wants the image flashed first.
- The first armed boot is the risky one. It is also the one that yields
  everything: PCIe, Storage and NetworkAdapters in a single push.

### Still open

`PostStatus` is not implemented. The OEM runs a `Ready → In-Progress →
Completed` state machine with `ProcessingTime` and a `Messages` map, but it is
never an HTTP endpoint — the BIOS never GETs it, and those redis reads were the
OEM BMC talking to itself. It may matter only for the OEM's own UI. Left out
until evidence says the BIOS cares.

Publishing PCIe/Storage/NetworkAdapters to D-Bus is also still to do: the
receiver will write `collections/pcie/*.json`, but the translator maps only
DIMMs and CPUs today.

## Proven on our own firmware, 2026-08-17

Flashed as `flax-onetree-1.1.0-202608171911` and exercised through the whole
cycle. Nothing below is a hot-deploy.

| step | result |
|---|---|
| armed GET, host boot from empty | BIOS took the OEM path, pushed **108,556 bytes**, host stayed Running |
| normalize | memory 12, processors 2, pcie 25, drives 1 |
| CRCs stored | `{"CPU":3032237160,"DIMM":2764192848,"PCIE":3428776986}` |
| second boot (CRCs match) | **850-byte delta, zero groups re-pushed**, inventory intact |
| BMC reflash + reboot | boot-time run republished all of it from disk |

Redfish, from the flashed image:

```
Memory 12   Processors 2   PCIeDevices 25   FabricAdapters 1   Storage drives 1
nic_00_5E_00  FirmwareVersion 14.27.26.06  Slot 2
384 GiB, 40 cores, 2 CPUs
```

The CPU and DIMM CRCs the BIOS sent us are byte-identical to the ones the OEM
BMC received months earlier, which independently confirms both that the BIOS
derives them deterministically from unchanged hardware and that we are storing
the right value.

**The delta boot validated the riskiest logic in the receiver.** A push that
mentions no groups must not erase them: had the receiver stored what it was
given, that boot would have wiped 25 PCIe devices and the drive. It did not.
That trap was only visible because the OEM capture let us watch the same
850-byte delta overwrite the OEM's own stored `inventory.json` while its redis
kept the full inventory.

One operational lesson, unrelated to the feature but expensive: a live
full-image `flashcp` can leave the SPI flash in a mode U-Boot cannot probe
(`unrecognized JEDEC id bytes: 00, 00, 00`), and **only a full AC power cycle
clears it** -- the chip keeps VCC across a warm reset. It happened twice in one
evening. The give-away that the image is fine is that U-Boot is running from
the very chip it claims it cannot find.
