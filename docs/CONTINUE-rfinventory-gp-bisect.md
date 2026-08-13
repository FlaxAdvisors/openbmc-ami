# CONTINUE: HI inventory — RECEIVE SIDE WORKING (2026-08-13)

**INVENTORY IS LANDING.** The TP26 BIOS now pushes its full inventory over the
host interface and we persist all of it. Host boots to Linux.

```
/var/lib/flax-inventory/collections/memory/0..11.json    12 DIMMs
/var/lib/flax-inventory/collections/processors/0..1.json  2 CPUs (~14 KB each)
/var/lib/flax-inventory/collections/pcie/00_01_00.json    1 PCIe device
```

Real data — DIMM: Hynix `HMA84GR7MFR4N-UH`, 32768 MiB DDR4 RDIMM, serial
`28DCDD40`, `DIMM A0`, 2400 MHz. All 12 slots A0-A5/B0-B5. CPU: `Intel(R)
Xeon(R) Gold 6138`, 20 cores / 40 threads, with `SubProcessors`.

**How:** we deliberately answer `GET /Oem/Ami/InventoryData` with **405**, which
makes the BIOS use the generic-Redfish fallback (DELETE-then-POST on the standard
collections), and patch 0013 receives those. Serving that GET is the one known
way to brick the boot — three attempts to reconstruct its body all crashed the
BIOS. Do not re-enable it without reading the FINDINGS doc.

**Next: Phase 2** — translate these files into D-Bus inventory so Redfish
actually surfaces them. Nothing publishes them yet.

## Remaining cleanup (deliberately deferred while getting it working)
- `-Dbmcweb-logging=debug` still in `bmcweb_%.bbappend` — very verbose, remove
- kill switch (`disable-inventorydata-get`) — temporary scaffolding, remove once
  stable. It earned itself: recovered the box in ~30 s, twice.
- running bmcweb is hot-deployed, ahead of the flashed image — needs an image build
- patches 0010/0011 still out of the build; 0009 edited in place (GET route
  stripped) rather than being a clean patch
- nothing committed

---

# Historical: the #GP investigation (RESOLVED)

**RESOLVED 2026-08-13.** Root cause bisected to a single route:

> **Serving `GET /redfish/v1/Oem/Ami/InventoryData` crashes the TP26 BIOS.**
> Remove that one route registration from patch 0009 and the host boots.

Confirmed on hardware — console reaches the Linux kernel handoff:

```
Pushing firmware layout to OData server.
Clearing memory collection...  Posting memory collection...
Clearing CPU collection...     Posting CPU collection...
Clearing PCIe collection...    Posting PCIe collection...
EFI stub: Loaded initrd from LINUX_EFI_INITRD_MEDIA_GUID device path
EFI stub: Measured initrd data into PCR 9
```

The rest of the host-interface flow works: static files, `SetupData.xml` and
`bios-blob.bin` all upload, and the BIOS proceeds to post its inventory
collections.

**ANSWERED 2026-08-13 by a debug-logging capture** — see
`/vagrant/oem-reference/protocol-reverse/FINDINGS-2026-08-13-real-inventory-endpoints.md`.

> **There is no `Oem/Ami/InventoryData` push.** The BIOS writes inventory into
> the STANDARD Redfish collections — `DELETE`+`POST` on
> `/redfish/v1/Systems/system/Memory`, `/Systems/system/Processors`, and
> `/Chassis/Cpld/PCIeDevices/<id>`. Upstream bmcweb registers those paths for
> **GET only**, so every one returns **405/404** and never reaches a handler of
> ours. That is why nothing ever landed.

Also refined: the crash is not caused by the InventoryData route existing. In
this capture it returned **405 and the host booted fine**. Only a **200 with our
JSON body** kills it. Do not re-enable that 200 without a recovery plan.

## Symptom

The host reaches BDS (POST code 98, `<DEL>` prompt visible), prints

```
Configuring firmware is in progress...
Pushing firmware layout to OData server.
```

and then dies in its own Redfish inventory driver:

```
!!!! X64 Exception Type - 0D(#GP - General Protection)  CPU Apic ID - 00000000 !!!!
RIP  - 00000000674D113B    RAX - 0, RCX - 0, RDX - 674D2AA0
!!!! Find image d:\bios_source_crb\tpchcascade\bioscode\p26c\14203m\...\RfInventory\
     RfInventory.pdb (ImageBase=00000000674BD000) !!!!
```

Never hands off to a boot device. `RIP` is **identical on every occurrence**
(offset 0x1413B into RfInventory) — deterministic, same code path every time.

## Ruled out (do not re-investigate)

| Theory | How it was killed |
|---|---|
| Bad/partial BIOS flash | SPI readback matched the source image **byte-for-byte** (md5 `f9ecf9fa…`) |
| Incomplete BIOS image | Valid Intel descriptor `5aa5f00f`, all regions in-bounds, 3 UEFI FVs, 1 trailing 0xFF byte |
| A specific BIOS chip | Both chips are **TPC_P26C**; identical crash on each. The BIOS is not the variable |
| Hardware | Older images and earlier versions of this branch booted fine on this box |
| `DynamicExtension` answered 201 (patch 0010) | Reverted to 404 — verified 404 at runtime, zero `dynext` uploads — **still crashed** |
| Missing `Systems`/`Chassis` in InventoryData GET (patch 0011) | Added both, response 237 B → 1129 B — **still crashed** |
| bmcweb "204 with a body" CRITICAL log | Red herring. `HttpBody::payloadSize()` returns an *engaged* optional (0) for an empty body, so `!pSize` is false and bmcweb logs that on **every** 204. Cosmetic upstream bug, not malformed framing |

Partial signal worth keeping: patch **0011 changed BIOS behaviour** — it now runs
the discovery GET **twice** (22:28:45 and 22:31:13), which is what the OEM does
and we previously did once. Directionally right, insufficient. Do not discard
0011 without reason.

Also: with `usb0` **down**, the BIOS does not skip the HI — it spins in the KCS
netfn 0x32 bootstrap loop (`HI32-trace` continuously) and parks at the splash.
Taking the interface away makes things worse, not better.

## Bisect — this is the active workstream

Boundary is clean. Last commit `e47597c4d3` contains **0007 only**. Everything
suspected is **untracked**, added 2026-08-11 onward:

```
?? bmcweb/0008-serviceroot-ami-host-interface-compat.patch
?? bmcweb/0009-hostiface-correct-biosstaticfiles-path-and-inventorydata-get.patch
?? bmcweb/0010-hostiface-accept-bios-registry-post.patch
?? bmcweb/0011-hostiface-inventorydata-get-systems-chassis.patch
?? linux-aspeed/0019..0024  (USB gadget RNDIS)
 M bmcweb/0007-...patch, bmcweb_%.bbappend      (both reverted for step 1)
 M intel-ipmi-oem/0006-add-netfn32-...patch
 M host-interface/{create_usbeth.sh,flax-hi-account.*,flax-hi-cred.*}
```

**Step 1 — DONE 2026-08-12, THE HOST BOOTED.** bmcweb reverted to committed
baseline (0007 as committed, 0008–0011 dropped), hot-deployed. Host completed
POST and booted.

- baseline binary md5 `15d59634f4c530c703c7e333ee35ecdf`
- baseline `flax_host_interface.hpp` is 3422 bytes (full stack is 15771)
- verified absent: `DynamicExtension`, `jsonValue["Systems"]`, `handleFlaxRegistryUpload`

### The bracket

```
GOOD  committed 0007, nothing else
BAD   modified 0007 + 0008 + 0009 + 0010 + 0011
```

**The culprit is in bmcweb, and it is one of FIVE candidates, not four.** The
working tree's 0007 was *modified* and step 1 reverted that too, so the 0007
delta is inside the bracket. Do not narrow to "one of 0008–0011" and skip it.

Kernel `0019`–`0024`, netfn32 0006 and the host-interface scripts are all
**exonerated** — they were unchanged on the box across the good and bad boots
(only the bmcweb binary was swapped). That removes every candidate that would
have required a full image build. All remaining bisect steps are ~5 min
hot-deploy cycles.

### Bisect log

| step | build | binary md5 | hpp bytes | result |
|---|---|---|---|---|
| 1 | committed 0007 only | `15d59634…` | 3422 | **GOOD** — booted |
| 2 | modified 0007 only | `c1eba442…` | 5402 | **GOOD** — booted |
| 3 | 0007+0008+0009 | `ac75cd88…` | 13376 | **BAD** — full push then fault |
| 4 | 0007+0008 | `9146c423…` | 5402 | **GOOD** — booted, no layout push (404s) |
| 5 | 0007+0008+0009 **minus InventoryData GET route** | `47df0e6d…` | — | **GOOD** — booted AND full layout push worked |

**Culprit: the `GET /redfish/v1/Oem/Ami/InventoryData` route added by 0009.**
Everything else in 0009 is fine and is needed — it provides the top-level
`/redfish/v1/BiosStaticFiles` and `/redfish/v1/Systems/<str>/Bios` routes that
the BIOS actually uses (the `/Oem/Ami/...` forms in 0007 are not what it calls).

0010 and 0011 are **exonerated** — step 3 reproduces the fault without either.
Both of 2026-08-12's hypothesis-driven fixes were operating on patches that are
not in the failing set.

Step 3 detail: `GET InventoryData` → 7 static files → `SetupData.xml` →
`bios/bios-blob.bin` → fault. No `registry/bios-registry.json` (that hook is in
0010, absent), and the BIOS took the 404 and continued — same as it does for
DynamicExtension.

### Scoring a step — what is and isn't a valid signal

`.247` answers **ping during POST** — that is the UEFI network stack, not an OS.
Ping is therefore only a crashed/not-crashed signal (a #GP halts ICMP too), NOT
a boot test. `HI32-trace` volume was never baselined against a good boot and is
not a discriminator either. Valid "it booted" evidence:

- console reaching `EFI stub: Loaded initrd …` (definitive), or
- **SSH answering on 192.168.88.247:22** (confirmed up after a successful boot)

Beware console scrollback — stale exception text was misread as a fresh crash
once. Match the text against the current boot's timestamps before scoring.

## Box state — IMPORTANT

- **BMC flashed image:** `flax-onetree-1.0.9-202608122038` (contains 0007–0010,
  **not** 0011).
- **Running bmcweb is NOT the flashed one.** `/usr/libexec/bmcwebd` has been
  hot-replaced and `/usr` is on the **persistent overlay**, so this survives a
  BMC reboot. A power cycle does *not* restore it.
- **Restore the flashed binary:**
  ```bash
  cp /var/bmcwebd.orig /usr/libexec/bmcwebd && systemctl restart bmcweb
  ```
  `/var/bmcwebd.orig` = md5 `530fc3ef…` (the 202608111925 build, kept as backup).
- **Working tree backups** of the modified 0007 + bbappend that were reverted for
  step 1: `<scratchpad>/bisect-backup/{0007.modified,bbappend.modified}`.
  Restore them before resuming forward work, or 0008–0011 stay out of the build.

## Environment

BMC is **192.168.88.248** (not .245); `tp-bmc` alias is stale. Everything hops
through brain:

```bash
ssh brain "sshpass -p 0penBmc ssh -o StrictHostKeyChecking=no root@192.168.88.248 '<cmd>'"
```

Hot-deploy cycle (~5 min), which is the whole reason bisect is cheap:

```bash
B=build/tiogapass/tmp/work/arm1176jzs-openbmc-linux-gnueabi/bmcweb/1.0+git/packages-split/bmcweb/usr/libexec/bmcwebd
scp $B brain:/tmp/bmcwebd.new
ssh brain 'sshpass -p 0penBmc scp /tmp/bmcwebd.new root@192.168.88.248:/tmp/'
ssh brain "sshpass -p 0penBmc ssh root@192.168.88.248 \
  'systemctl stop bmcweb; cp /tmp/bmcwebd.new /usr/libexec/bmcwebd; \
   chmod +x /usr/libexec/bmcwebd; systemctl start bmcweb'"
```

Watch the push:

```bash
journalctl -f | grep -iE "flax-hi|CRITICAL"
```

Normal sequence before the crash: `GET InventoryData` → `registry/bios-registry.json`
(457442) → `static/` ×7 → `static/SetupData.xml` (471360) → `bios/bios-blob.bin`
(22717) → **#GP within 1 s**.

## The lead that costs no boots

Stop reverse-engineering by experiment. The OEM firmware is unpacked at
`/vagrant/oem-reference/oem-rootfs/` with `hi-inventory-helper.lua` (96 KB) and
`inventoryBios.lua`. Read what the OEM actually returns for
`POST /redfish/v1/Systems/Self/Bios` — the request immediately before the fault,
and the one where the OEM receives **two** POSTs and we receive one.

Remaining known divergences from `/vagrant/oem-reference/protocol-reverse/COMPARISON-2026-08-11.md`:

| | OEM | ours |
|---|---|---|
| `GET Oem/Ami/InventoryData` | 3105 B | 1129 B (was 237 B before 0011) |
| `POST BiosStaticFiles` | 201 ×1 batched | 201 ×7 one at a time |
| `POST Systems/Self/Bios` | 204 ×2 | 204 ×1 |
| `POST Oem/Ami/InventoryData` | 201 | never sent |
| `GET SecureBoot.ResetKeys` | 200 | never requested |

`GroupCrcList` still returns zeros; the OEM returns real CRCs
(`DIMM 2764192848, CPU 3032237160, PCIE 3797810510`). Reconstructing that table
from the redis dumps in `protocol-reverse/` is still the open Phase-2 task.

## Unrelated, noticed today

`sel-logger` asserts critical SELs every boot on a scaling error:
`MB_VR_PCH_PVNN_Output_Voltage ... Reading=11.750000 Threshold=1.100000` —
~11.75 V on a ~1 V rail. Sensor config bug, not urgent, but it spams the SEL.
