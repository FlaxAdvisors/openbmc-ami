# Redfish Inventory via Native Host-Interface Receive Side — Design (v2)

**Date:** 2026-07-23 (v2 — rewritten after Phase-0 discovery completed)
**Branch:** `ocp`
**Status:** Design — ready for implementation plan
**Protocol reference:** `docs/redfish-inventory-netfn32-protocol.md` (byte-exact, Phase-0 complete)
**Supersedes:** the v1 "KCS→smbios2 shim" design (the real mechanism is two-transport; see below)

## Goal

Populate Redfish hardware inventory (Processors, Memory, Storage, and host NIC/PCIe) on the
TiogaPass BMC running our flax-onetree image, by natively reimplementing the **receive side**
of the AMI inventory mechanism the TP26 BIOS already uses. Ship no OEM/AMI code.

Success = `GET /redfish/v1/Systems/system/Processors`, `.../Memory`, `.../Storage`, and the
host NIC return real hardware on our image after a host POST.

## What Phase-0 discovery established (the mechanism)

The TP26 BIOS does **not** push SMBIOS structs and does **not** use Intel MDR_V2 or
phosphor-ipmi-blobs. It uses AMI's **two-transport Redfish Host Interface**:

1. **KCS NetFn 0x32 — bootstrap** (byte-exact captured): the BIOS probes a device list
   (`cmd 0x2a`, a Redis `smembers`; empty→cc `0xCC`→proceed), reads device status
   (`cmd 0x3d` → `07 07 07`), and is **issued Redfish Host Interface credentials**
   (`cmd 0x5d` → `HostAuto*` tokens). ~14 small messages.
2. **Redfish Host Interface over `usb0`** (schema RE'd): the BIOS acts as a Redfish **client**,
   authenticates as account **`HI-FW`** using that KCS-issued token, and **POST/PUTs an
   inventory file** to `/redfish/v1/Oem/Ami/BiosStaticFiles` (bracketed by
   `BIOSInventoryTransferComplete false→true`). On the OEM BMC a sync-agent expands that file
   into `Redfish:*` Redis keys served by its bmcweb.

Framing, exact bytes, routes, and auth are documented in the protocol reference.

## Design principles

- **Native, no OEM code shipped** (reverse-engineering authorized; redistribution not).
- **Reuse what we already have**: our USB virtual NIC ([[topic_inband_virtual_nic]]) and our
  bmcweb (which supports the DMTF Redfish Host Interface).
- **Target = OpenBMC D-Bus inventory** (decided): the translator publishes
  `xyz.openbmc_project.Inventory.Item.*`; our bmcweb serves it as Redfish. An intermediate
  store (e.g. a small Redis/file) is acceptable if feeding D-Bus directly proves awkward.

## Scope

**In:** Processors, Memory, Storage (NVMe), and — newly in scope, because this path carries it —
host **NIC/PCIe** device identity (`Chassis/…/PCIeDevices`, `NetworkAdapters`).
**Out:** anything the BIOS genuinely doesn't send. (The earlier "PCIe/NIC out" scoping was
based on the SMBIOS path and is retired — the HI path carries PCIe device identity incl. the
Mellanox host NIC.)
**No OEM/AMI binaries, Lua, or the OEM sync-agent in our image.**

## Architecture

```
TP26 BIOS ──KCS NetFn 0x32──▶ [1] KCS bootstrap handler (native ipmid provider, meta-flax)
   │                                · 0x2a device-list (empty ok), 0x3d device-status
   │                                · 0x5d: ISSUE a host-interface credential  ──┐
   │                                                                              │ shared credential
   └──HTTP/Redfish over usb0──▶ [2] Host Interface endpoint (bmcweb, meta-flax)   │
        (auth as HI-FW,             · account HI-FW authenticated by the ─────────┘
         POST inventory blob)         KCS-issued credential
                                    · accept POST/PUT of the inventory file
                                    ▼
                          /var/lib/flax-inventory/inventory.json   (our own file)
                                    │
                          [3] Translator (native service, meta-flax)
                                    · inventory.json ──▶ D-Bus Inventory.Item.{Cpu,Dimm,Drive,...}
                                    ▼
                          [4] EXISTING: our bmcweb ─▶ Redfish (Processors/Memory/Storage/NIC)
```

### Component boundaries

- **[1] KCS bootstrap handler** — *What:* answer the NetFn 0x32 handshake so POST proceeds and
  issue the HI credential. *In:* KCS IPMI requests (via phosphor-ipmi-kcs → ipmid dispatch).
  *Out:* correct responses per the captured byte transcript; a credential handed to [2].
  *Testable:* offline replay of the captured request transcript, byte-diffing our responses.
- **[2] Host Interface endpoint** — *What:* present the Redfish Host Interface the BIOS expects
  on `usb0` and accept its inventory file upload. *In:* HTTP POST/PUT from the BIOS as `HI-FW`.
  *Out:* the inventory file on disk. *Depends on:* the USB vNIC; a bmcweb OEM route +
  `HI-FW` account whose credential matches [1]'s issued token; SMBIOS Type-42 HI descriptor so
  the BIOS discovers our HI. *Testable:* POST a captured inventory file to the endpoint with a
  test credential; assert it lands.
- **[3] Translator** — *What:* inventory file → D-Bus inventory. *In:* the file from [2].
  *Out:* `xyz.openbmc_project.Inventory.Item.*` objects. *Testable:* feed a captured
  `inventory-full.json`; assert D-Bus objects and Redfish JSON (no BIOS in the loop).
- **[4]** existing bmcweb — unchanged.

### The crux / novel risk

The TP26 BIOS is a **closed client** with baked-in expectations: it discovers the HI (SMBIOS
Type 42 + KCS bootstrap), authenticates as `HI-FW` with the KCS-issued token, and POSTs to
specific AMI OEM URLs. Our bmcweb must present **the exact endpoints + credential flow the
closed BIOS expects**. This is the primary unknown-risk: a custom bmcweb OEM route
(`/redfish/v1/Oem/Ami/BiosStaticFiles` or equivalent) plus a **credential bridge** between the
KCS handler ([1]) and bmcweb auth ([2]). Phase 1 must de-risk this end-to-end before the
translator is built.

## Implementation phasing

- **Phase 1 — End-to-end "BIOS talks to us" proof (highest risk first).** Minimal KCS 0x32
  bootstrap handler + a bmcweb OEM endpoint on `usb0` that accepts the BIOS's authenticated
  inventory POST and **just saves the file**. Success = the TP26 BIOS completes its push to
  our BMC (no POST hang) and we capture its inventory file. Nothing is translated yet. This
  proves the closed BIOS will speak to our reimplementation — the make-or-break question.
- **Phase 2 — Translator (CPU/DIMM).** Parse the saved inventory → D-Bus
  `Inventory.Item.Cpu/Dimm` → verify Processors/Memory in our Redfish.
- **Phase 3 — Storage + host NIC/PCIe.** Extend the translator to Drives and PCIe/NetworkAdapter.
- **Phase 4 — Hardening.** Credential lifecycle, delta/full handling, error paths, field docs.

## Testing / validation

- **Offline replay (unit):** [1]'s responses byte-diffed vs the captured KCS transcript.
- **Endpoint fixture:** POST a captured inventory file to [2] with a test credential; assert landing.
- **Translator fixture:** captured `inventory-full.json` → D-Bus → Redfish; no BIOS in loop.
- **Hardware integration:** flash our image, POST the host, confirm push completes and Redfish
  shows CPU/DIMM/Storage/NIC.
- **Regression:** inband IPMI (chassis/SEL) still works; the KCS 0x32 handler is additive.

## Risks

- **Closed-BIOS compatibility (highest).** The BIOS may have AMI-specific expectations we can't
  fully replicate (discovery, auth nonces, exact URL/schema). Mitigation: Phase 1 proves the
  full path early with the smallest possible implementation; we have the byte-exact KCS
  transcript and the HI route/auth schema as ground truth.
- **bmcweb OEM route + credential bridge** between an ipmid provider and bmcweb is non-trivial
  (cross-process credential handoff). Mitigation: a simple shared secret store written by [1],
  read by [2]; scope it minimally.
- **SMBIOS Type-42 HI descriptor** must advertise our HI so the BIOS finds it. Mitigation:
  confirm what the TP26 BIOS keys on (fixed IP/interface vs SMBIOS-advertised) — a Phase-1
  investigation item.
- **Delta vs full push** (BIOS CRC cache): field units may need one full push after flash.
- **usb0 addressing:** the BIOS expects a specific host-interface network; our vNIC must match.

## Open items (resolve in Phase 1)

- Exact HI discovery the TP26 BIOS uses (SMBIOS Type 42 contents vs hardcoded `169.254.x`).
- The credential-bridge shape between [1] and [2].
- Whether our bmcweb's built-in Redfish HI support is enough or a custom OEM route is required
  for the `/Oem/Ami/BiosStaticFiles` upload the BIOS performs.
