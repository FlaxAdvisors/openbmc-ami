# Redfish Inventory — Native Host-Interface Receiver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the TP26 BIOS push hardware inventory to *our* flax-onetree BMC and surface it in
our Redfish, by natively reimplementing the receive side (KCS NetFn 0x32 bootstrap + Redfish
Host Interface endpoint + a translator to OpenBMC D-Bus inventory).

**Architecture:** Two transports. (1) A native KCS NetFn 0x32 bootstrap handler answers the
BIOS handshake and issues a Host-Interface credential. (2) A Redfish Host Interface on our USB
vNIC accepts the BIOS's authenticated inventory file upload. (3) A translator maps the received
inventory to `xyz.openbmc_project.Inventory.Item.*`, which our bmcweb serves as Redfish.

**Tech Stack:** OpenBMC/Yocto (meta-flax), C++ ipmid provider, bmcweb (C++), USB CDC-ECM gadget
(existing `host-interface` recipe), Python for the translator + offline tests, real TiogaPass.

## Global Constraints

- No OEM/AMI binaries, Lua, or the OEM sync-agent shipped. Documentation + our own code only.
- Ground truth: `docs/redfish-inventory-netfn32-protocol.md` (byte-exact KCS transcript + HI
  route/auth schema) and `/vagrant/oem-reference/protocol-reverse/live-2026-07-23/` (captures:
  `kcs-bytes-fullpush.txt`, `inventory-full.json`, redis traces).
- Target: OpenBMC D-Bus inventory (per spec). An intermediate store is allowed if direct D-Bus
  feeding is awkward — decide in Phase 2, don't pre-build it.
- Existing infra to reuse, not rebuild: `meta-flax/recipes-ami/host-interface/` (USB CDC-ECM
  vNIC, currently `10.199.199.1/30`), `intel-ipmi-oem` (ipmid provider path), our bmcweb bbappend.
- BMC access `sshpass -p 0penBmc ssh tp-bmc`; build `. setup tiogapass`; BusyBox (`head -n N`,
  `wget` not curl). For long remote captures set the Bash tool `timeout` explicitly.
- KCS 0x32 responses must be byte-exact per the capture; never ship a blanket empty-success stub.

## Phasing overview

- **Phase 1 (this plan's focus) — prove the closed BIOS talks to our BMC.** Highest risk first.
  End when the TP26 BIOS completes its inventory push to *our* image and we capture the file.
- **Phase 2 — translator (CPU/DIMM)** → D-Bus → our Redfish Processors/Memory.
- **Phase 3 — Storage + host NIC/PCIe.**
- **Phase 4 — hardening** (credential lifecycle, delta/full, errors, field docs).

Phases 2–4 are outlined at the end; their tasks firm up once Phase 1 proves compatibility (the
translator tasks are already well-defined by `inventory-full.json`, but there is no point
building them if Phase 1 shows the BIOS won't push to us).

---

## Phase 1 — Prove the BIOS pushes to our BMC

### Task 1.1: Determine how the TP26 BIOS discovers + auths to the Host Interface

**Files:** Create `docs/redfish-inventory-hi-discovery.md` (findings).

**Interfaces:** Consumes the running TP26 host + OEM captures. Produces the exact HI contract
the BIOS expects: network location, USB gadget identity, SMBIOS Type-42 contents, and how the
KCS `0x5d` credential maps to the HTTP auth.

Rationale: our vNIC is `10.199.199.x`; the OEM HI is `169.254.x`. We must learn what the BIOS
actually keys on before configuring our HI.

- [ ] **Step 1: Read the TP26 BIOS's SMBIOS Type 42 (Redfish Host Interface descriptor)**

On the running TP26 host OS: `dmidecode -t 42` (or from our BMC's captured SMBIOS). Record the
Host IP Assignment Type, IP, subnet, the Device (USB) descriptor (idVendor/idProduct), and the
Redfish service IP/port/hostname. Expected: the BIOS's baked-in HI target (likely `169.254.x`
auto/link-local + a USB device descriptor).

- [ ] **Step 2: Compare against the OEM BMC's working HI**

From the OEM captures / a booted OEM BMC: its `usb0` = `169.254.0.17`, gadget identity, and the
`HI-FW` account. Diff against our `create_usbeth.sh` (`10.199.199.1/30`, VID 0x1d6b/PID 0x0104).
Record every field the BIOS requires us to match. Expected: a concrete "must-match" list.

- [ ] **Step 3: Map the credential flow**

From `kcs-bytes-fullpush.txt`: `cmd 0x5d` returns `HostAuto*` tokens. Determine (from the OEM
`account.lua` HI handler, already extracted) how that token becomes the `HI-FW` HTTP credential
(basic auth password? session token?). Expected: the credential-bridge contract for Task 1.3.

- [ ] **Step 4: Write `docs/redfish-inventory-hi-discovery.md`** with the must-match HI contract
and the credential mapping. Expected: enough to configure our HI + write the bootstrap handler.

- [ ] **Step 5: Commit**

```bash
git add docs/redfish-inventory-hi-discovery.md
git commit -m "docs: TP26 BIOS host-interface discovery + credential contract"
```

### Task 1.2: KCS NetFn 0x32 bootstrap handler (byte-exact)

**Files:**
- Create: `meta-flax/recipes-phosphor/ipmi/netfn32-inventory/…` (new ipmid provider recipe) OR a
  patch to `intel-ipmi-oem` (decide in Step 1 from how intel-ipmi-oem registers providers).
- Test: `tools/netfn32/test_handler_responses.py` (offline byte-diff replay).

**Interfaces:** Consumes KCS IPMI requests via phosphor-ipmi-kcs → ipmid dispatch. Produces
byte-exact responses for cmds `0x2a` (empty→cc 0xCC), `0x3d` (`00 07 07 07`), `0x5d` (issue
credential), `0xaa/0xab`; writes the issued credential to a shared store for Task 1.3.

- [ ] **Step 1: Decide provider mechanism** — inspect `intel-ipmi-oem` for how it registers
`ipmi::registerHandler(...)` for a NetFn; mirror it. Record the choice.
Expected: a registration pattern that adds NetFn 0x32 handlers additively (no disruption to
existing inband IPMI).

- [ ] **Step 2: Write the failing offline replay test**

```python
# tools/netfn32/test_handler_responses.py
from netfn32_model import respond   # pure-python mirror of our handler logic
def test_0x2a_empty_returns_cc():
    # smembers of an absent key -> completion code 0xCC
    assert respond(0x2a, bytes([0x01,0x00])+b"smembers Redfish:oem:MappingOut:DeviceList") == (0xCC, b"")
def test_0x3d_device_status():
    assert respond(0x3d, bytes([0x01,0x00,0x07])) == (0x00, bytes([0x07,0x07,0x07]))
def test_0x5d_issues_token():
    cc,data = respond(0x5d, bytes([0x01]))
    assert cc==0x00 and data[:1]==bytes([0x0a]) and b"HostAuto" in data  # token shape from capture
```

- [ ] **Step 3: Run it, verify it fails** — `cd tools/netfn32 && python3 -m pytest test_handler_responses.py -v` → FAIL (no module).

- [ ] **Step 4: Write `netfn32_model.py`** — the pure logic (response bytes per the capture),
so it can be validated offline and then transliterated to the C++ handler.

- [ ] **Step 5: Run it, verify PASS.**

- [ ] **Step 6: Implement the C++ handler** in the provider recipe, transliterating
`netfn32_model.py`; on `0x5d` write the issued token to `/run/flax-hi-cred` for Task 1.3.

- [ ] **Step 7: Build** `bitbake intel-ipmi-oem` (or the new recipe) — compiles clean.

- [ ] **Step 8: Commit.**

### Task 1.3: Configure our Host Interface to match the BIOS + accept the credential

**Files:**
- Modify: `meta-flax/recipes-ami/host-interface/host-interface/create_usbeth.sh` (address/identity
  to match Task 1.1's must-match list).
- Create: a bmcweb OEM route + `HI-FW` account whose credential is the token from `/run/flax-hi-cred`
  (patch under `meta-flax/recipes-phosphor/bmcweb/bmcweb/`), OR a minimal standalone HTTPS
  receiver if bmcweb OEM-route surface is too invasive (decide from Task 1.1 findings).

**Interfaces:** Consumes the HI contract (1.1) + the shared credential (1.2). Produces an
endpoint on the vNIC that accepts the BIOS's authenticated inventory file POST/PUT and writes it
to `/var/lib/flax-inventory/inventory.json`.

- [ ] **Step 1:** Adjust `create_usbeth.sh` to the required addressing/identity from Task 1.1
(e.g. link-local `169.254.x` + matching gadget descriptor) **without breaking** the existing
in-band vNIC use — if they conflict, add a second config/interface rather than repurposing.
- [ ] **Step 2:** Stand up the receive endpoint (bmcweb OEM route for `/Oem/Ami/BiosStaticFiles`
or equivalent) authenticated by the shared credential; on upload, save the body to
`/var/lib/flax-inventory/inventory.json` and set a transfer-complete flag.
- [ ] **Step 3: Fixture test** — `POST` the captured `inventory-full.json` to the endpoint with a
test credential; assert it lands at the expected path. (No BIOS in the loop.)
- [ ] **Step 4:** Build the image (`bitbake obmc-phosphor-image`).
- [ ] **Step 5: Commit.**

### Task 1.4: Hardware integration — does the BIOS actually push to us? (the make-or-break)

**Interfaces:** Consumes 1.2 + 1.3 on real hardware. Produces a captured
`/var/lib/flax-inventory/inventory.json` written by the *real TP26 BIOS*.

- [ ] **Step 1:** Flash our image to the TiogaPass BMC (`fx-tp` tar), verify services up
(`check-bmc`), inband IPMI still works (regression).
- [ ] **Step 2:** Power-cycle the host; watch POST complete with no hang (the KCS 0x32 handler
must answer correctly — if POST hangs, byte-diff our KCS traffic vs `kcs-bytes-fullpush.txt`).
- [ ] **Step 3:** After POST, check `/var/lib/flax-inventory/inventory.json` exists and matches
the shape of `inventory-full.json`. **This is the Phase-1 success gate.**
- [ ] **Step 4:** If the BIOS did not push: diagnose via the discovery doc (HI addressing,
gadget identity, credential, SMBIOS Type 42) — iterate 1.1/1.3. Record findings.
- [ ] **Step 5:** Document the Phase-1 result and commit the captured file + notes.

---

## Phase 2 — Translator (CPU/DIMM) → D-Bus  *(outline; firms up after 1.4 passes)*

- **2.1** Python/C++ translator: parse `inventory.json` → `xyz.openbmc_project.Inventory.Item.Cpu`
  and `.Dimm` D-Bus objects. Fixture test against `inventory-full.json` asserting object
  properties (Model "Xeon Gold 6138", 20c/40t; DIMM Hynix 32GB, PN `HMA84GR7MFR4N-UH`).
- **2.2** Wire the translator to run on the transfer-complete flag from Phase 1.
- **2.3** Hardware: confirm `GET /redfish/v1/Systems/system/Processors` and `.../Memory` return
  real data via our bmcweb.

## Phase 3 — Storage + host NIC/PCIe  *(outline)*

- **3.1** Extend translator to `Storage/Drives` (Intel 660P NVMe).
- **3.2** Extend to `Chassis/…/PCIeDevices` + `NetworkAdapters` (Mellanox host NIC) as far as the
  OpenBMC inventory model + our bmcweb Redfish support allow.
- **3.3** Hardware validation.

## Phase 4 — Hardening  *(outline)*

- Credential lifecycle/rotation; delta-vs-full push handling; error paths; document the
  one-full-push-after-flash caveat; regression sweep of inband IPMI / SOL / power.

## Self-Review

**Spec coverage:** KCS bootstrap → 1.2; Host Interface endpoint → 1.3; translator → Phase 2/3;
D-Bus target → Phase 2; NIC/PCIe in scope → Phase 3; closed-BIOS-compat risk front-loaded → 1.1/1.4.
**Placeholder scan:** Phase-1 code steps carry real test code/response bytes from the capture;
Phases 2–4 are explicitly outlines pending the 1.4 gate (a scoping decision, not a gap).
**Type consistency:** `respond(cmd, req)->(cc, data)` used consistently in 1.2; shared credential
path `/run/flax-hi-cred` and inventory path `/var/lib/flax-inventory/inventory.json` consistent
across 1.2/1.3/Phase 2.
