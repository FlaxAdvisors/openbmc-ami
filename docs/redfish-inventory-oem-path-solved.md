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

## Implementation sketch, now that guessing is over

1. Serve `GET /Oem/Ami/InventoryData`: **404 while we hold no inventory**
   (matches the OEM in the empty state, and is what today's working boot
   already effectively does), otherwise the captured structure with our stored
   values.
2. Accept the `POST`, persist the payload, and implement `PostStatus` as a
   real state machine: `Ready` → `In-Progress` → `Completed`, with
   `ProcessingTime` and a `Messages` map.
3. Store `GroupCrcList` from the payload and echo it back. Advertise
   `BiosStaticFiles` CRCs so the BIOS stops re-uploading all seven assets.
4. Keep the peer-subnet gate; answer 404 (not 403/405) off-interface, as the
   OEM does.

Acceptance before the BIOS ever sees it: diff our generated body against
`hi-InventoryData.json` — same keys, same nesting, same types; only CRCs,
etag/LastModified and MACs may differ. Keep the current 405 kill switch
staged, since that behaviour is proven to boot.
