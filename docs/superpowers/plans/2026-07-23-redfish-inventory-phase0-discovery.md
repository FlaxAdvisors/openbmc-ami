# Redfish Inventory — Phase 0 (Protocol Discovery) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a byte-exact protocol spec for the AMI-proprietary NetFn 0x32 inventory
conversation the TP26 BIOS speaks, so Phases 1–2 can implement a native receiver without guessing.

**Architecture:** Reverse-engineer from two complementary sources — a live, authoritative KCS
golden trace captured while the OEM BMC image runs on real TiogaPass hardware, corroborated by
LuaJIT decompilation and static analysis of the OEM stack. Reconcile the two into one written
protocol spec that becomes the gate for all downstream code.

**Tech Stack:** OpenBMC/Yocto (flax-onetree image), IPMI over KCS (AST2500), LuaJIT bytecode
(`ljd`/luajit-decompiler), Python 3 for the transcript decoder + tests, real TiogaPass hardware.

## Global Constraints

- No OEM/AMI proprietary binaries, Lua, or Redis are shipped in the flax-onetree image — this
  phase produces *documentation only* (a protocol spec + captured artifacts), no shipped code.
- Reverse-engineering is authorized; redistribution of AMI code is not. Decompiled Lua and OEM
  binaries stay under `/vagrant/oem-reference/` and `docs/`, never in `meta-flax/`.
- BMC access: `sshpass -p 0penBmc ssh tp-bmc` (direct). BMC has BusyBox only — no `curl`
  (use `wget`), `head` needs `-n N`, POSIX sh only.
- Build env: `. setup tiogapass` (not `source oe-init-build-env`).
- The TP26 BIOS is the fixed send side; its captured NetFn 0x32 requests from 2026-05-04 are the
  known starting point: `cmd 0x2a` (probe), `cmd 0x3d` (needs 33-byte `{CC, DevStatus[32]}`),
  `cmd 0x5d` (1-byte payload), `cmd 0xab` (empty). The data-carrying write command is not yet identified.
- Do NOT re-introduce the blanket empty-success stub (old patch 0013): it causes the `cmd 0x3d`
  retry storm → POST hang at code 91. (Relevant as a guardrail; no receiver code is written this phase.)

## Artifacts referenced

- `/vagrant/oem-reference/protocol-reverse/` — `inventoryBios.lua`, `hi-inventory-helper.lua`
  (LuaJIT bytecode), `inventory.json` (852-byte delta), `redis-*.dump` (populated target schema).
- `/vagrant/oem-reference/dimm-restored/` — full-payload inventory JSONs from the Phase 1 dimm-swap test.
- OEM BMC image — to be placed on `/vagrant/` by the user; bootable on a real TiogaPass.

## Deliverable of this phase

`docs/redfish-inventory-netfn32-protocol.md` — per-command request/response byte layout, handshake
ordering, inventory payload encoding, and a storage(type-0xC2) presence finding. This document is
the gate: Phase 1 does not start until it exists and is reconciled against the live trace.

---

### Task 1: Extract the OEM stack offline and choose a response-capture method

**Files:**
- Create: `docs/redfish-inventory-oem-teardown.md` (findings log)
- Work area: `/vagrant/oem-reference/oem-rootfs/` (extracted, not committed)

**Interfaces:**
- Consumes: OEM BMC image on `/vagrant/` (ask the user for the exact filename first).
- Produces: a confirmed capture method (how we will observe IPMIMain's *response* bytes per KCS
  transaction) and a file inventory (IPMIMain path, Lua processors, KCS bridge, log config).

Rationale: we already know the BIOS *requests* from 2026-05-04. The missing half is the OEM's
*responses*. Determine offline how we will capture them before spending a hardware session.

- [ ] **Step 1: Confirm the OEM image filename with the user, then identify its format**

Run: `ls -la /vagrant/*.ima /vagrant/*.bin /vagrant/*.mtd /vagrant/*.tar 2>/dev/null` and
`file <oem-image>`. Expected: identify a flash image (likely UBI/squashfs or a static MTD).

- [ ] **Step 2: Extract the root filesystem**

Use the matching tool for the format (e.g. `ubireader_extract_files`, `unsquashfs`, or
`binwalk -e`). Extract into `/vagrant/oem-reference/oem-rootfs/`.
Expected: a browsable rootfs tree.

- [ ] **Step 3: Locate the inventory stack and log its paths**

Run: `find /vagrant/oem-reference/oem-rootfs -iname 'IPMIMain*' -o -iname '*inventory*.lua' -o -iname '*.lua' | head -50`
and `find ... -iname '*ipmi*kcs*' -o -iname '*btbridge*' -o -iname 'ipmid*'`.
Record IPMIMain path, the Lua processor set, the KCS/host-bridge daemon, and any Redis config.
Write findings to `docs/redfish-inventory-oem-teardown.md`.
Expected: IPMIMain and the two known Lua files (or their live equivalents) located.

- [ ] **Step 4: Decide the response-capture method**

Evaluate, in `docs/redfish-inventory-oem-teardown.md`, which is viable on the running OEM BMC:
(a) IPMIMain verbose/debug logging (grep the binary/config for a log level or env var);
(b) `strace -e trace=read,write -x` on IPMIMain's KCS fd to log raw response bytes;
(c) a wire sniff on the KCS/LPC lines (logic analyzer) as fallback.
Pick the least invasive method that yields exact response bytes. Record the exact command line.
Expected: one chosen method with a concrete command, plus a fallback.

- [ ] **Step 5: Commit the teardown findings**

```bash
git add docs/redfish-inventory-oem-teardown.md
git commit -m "docs: OEM inventory stack teardown + response-capture method"
```

---

### Task 2: Decompile the Lua and draft the protocol hypothesis

**Files:**
- Create: `docs/redfish-inventory-netfn32-protocol.md` (DRAFT sections — hypotheses marked UNCONFIRMED)
- Work area: `/vagrant/oem-reference/protocol-reverse/decompiled/`

**Interfaces:**
- Consumes: `inventoryBios.lua`, `hi-inventory-helper.lua`; OEM IPMIMain from Task 1.
- Produces: a draft protocol spec: per-command struct hypotheses to confirm against the live trace.

- [ ] **Step 1: Install/locate a LuaJIT decompiler**

Try `ljd` (github.com/skudncnjhg/ljd or a maintained fork) or `luajit-decompiler-v2`. Confirm the
tool matches the bytecode version (`\x1bLJ\x02` → LuaJIT 2.1). Record the tool + version.
Expected: a decompiler that loads the files without a version-mismatch error.

- [ ] **Step 2: Decompile both files**

Run the decompiler on `inventoryBios.lua` and `hi-inventory-helper.lua`, output to
`/vagrant/oem-reference/protocol-reverse/decompiled/`.
Expected: readable-ish Lua source (partial is acceptable; the string tables already expose
`GetInventoryDevStatusRes_T`, `SetInventoryDevStatusReq_T`, ParamSelector/SetSelector/BlockSelector).

- [ ] **Step 3: Extract the struct definitions and command semantics**

From the decompiled source, write down for each NetFn 0x32 command the hypothesized request and
response struct layout — especially `cmd 0x3d`'s 33-byte `{CC, DevStatus[32]}` (what does each
`DevStatus` byte encode — device index? present/acked flags?) and the write command that carries
CPU/DIMM/PCIE blocks. Static-analyze IPMIMain (`strings`, `objdump -d`) where the Lua defers to C
framing.
Expected: a per-command hypothesis table.

- [ ] **Step 4: Write the DRAFT protocol spec**

Create `docs/redfish-inventory-netfn32-protocol.md` with a section per command, every hypothesized
field marked `UNCONFIRMED (from decompile)`. Include the payload encoding hypothesis derived from
the `redis-*.dump` target schema and the `dimm-restored/` JSONs.
Expected: a complete draft with explicit unknowns to resolve on the wire.

- [ ] **Step 5: Commit the draft**

```bash
git add docs/redfish-inventory-netfn32-protocol.md
git commit -m "docs: draft NetFn 0x32 protocol from Lua decompile (UNCONFIRMED)"
```

---

### Task 3: Build a transcript decoder (TDD)

**Files:**
- Create: `tools/netfn32/decode_transcript.py`
- Test: `tools/netfn32/test_decode_transcript.py`

**Interfaces:**
- Consumes: a raw capture file (hex lines of KCS request/response frames — format defined by the
  Task 1 capture method; normalize to `DIR NETFN CMD DATA...` hex per line).
- Produces: `decode(lines: list[str]) -> list[Frame]` where
  `Frame = {"dir": "req"|"resp", "netfn": int, "cmd": int, "data": bytes}`, and a
  `pretty(frames) -> str` that renders each frame with ASCII-decoded data. This tool is the fixture
  loader for Phase 1's byte-diff replay test, so its parse must be exact.

- [ ] **Step 1: Write the failing test**

```python
# tools/netfn32/test_decode_transcript.py
from decode_transcript import decode, Frame

def test_decodes_probe_request():
    line = "req 32 2a 01 00 73 6d 65 6d 62 65 72 73"  # 'smembers' prefix
    frames = decode([line])
    assert frames == [Frame(dir="req", netfn=0x32, cmd=0x2a,
                            data=bytes([0x01,0x00,0x73,0x6d,0x65,0x6d,0x62,0x65,0x72,0x73]))]

def test_decodes_response_and_pretty_shows_ascii():
    from decode_transcript import pretty
    frames = decode(["resp 32 3d 00 " + " ".join(["00"]*32)])
    assert frames[0].netfn == 0x32 and frames[0].cmd == 0x3d
    assert len(frames[0].data) == 33  # CC + DevStatus[32]
    assert "3d" in pretty(frames)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/netfn32 && python3 -m pytest test_decode_transcript.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'decode_transcript'`.

- [ ] **Step 3: Write minimal implementation**

```python
# tools/netfn32/decode_transcript.py
from dataclasses import dataclass

@dataclass
class Frame:
    dir: str
    netfn: int
    cmd: int
    data: bytes

def decode(lines):
    frames = []
    for raw in lines:
        parts = raw.split()
        if not parts:
            continue
        direction = "req" if parts[0].lower().startswith("req") else "resp"
        netfn = int(parts[1], 16)
        cmd = int(parts[2], 16)
        data = bytes(int(b, 16) for b in parts[3:])
        frames.append(Frame(dir=direction, netfn=netfn, cmd=cmd, data=data))
    return frames

def pretty(frames):
    out = []
    for f in frames:
        ascii_ = "".join(chr(b) if 32 <= b < 127 else "." for b in f.data)
        hexs = " ".join(f"{b:02x}" for b in f.data)
        out.append(f"{f.dir:4} netfn={f.netfn:02x} cmd={f.cmd:02x} | {hexs} | {ascii_}")
    return "\n".join(out)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/netfn32 && python3 -m pytest test_decode_transcript.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add tools/netfn32/decode_transcript.py tools/netfn32/test_decode_transcript.py
git commit -m "feat: NetFn 0x32 transcript decoder for protocol capture"
```

---

### Task 4: Capture the live golden trace on real hardware

**Files:**
- Create: `/vagrant/oem-reference/protocol-reverse/golden-trace.txt` (raw capture, not committed)
- Create: `/vagrant/oem-reference/protocol-reverse/golden-payload.json` (the uploaded inventory, not committed)

**Interfaces:**
- Consumes: the capture method from Task 1; a real TiogaPass that can boot the OEM BMC image.
- Produces: the authoritative byte-exact request/response transcript + the full inventory payload.

This is a hardware-in-the-loop task; steps are procedural with verification gates. It requires the
user to operate hardware (boot the OEM image, clear BIOS NVRAM). Coordinate before starting.

- [ ] **Step 1: Boot the OEM BMC image on the TiogaPass**

User flashes/boots the OEM BMC image (from Task 1) on the real TiogaPass. Confirm the OEM BMC comes
up and that its inventory works (query its Redfish/Redis for populated CPU/DIMM — proves the OEM
push path is live on this exact BIOS before we trace it).
Expected: OEM BMC reports populated inventory = golden reference is valid.

- [ ] **Step 2: Arm the capture**

On the running OEM BMC, start the response-capture method chosen in Task 1 (e.g. `strace` on
IPMIMain's KCS fd, or IPMIMain debug logging), writing to a file.
Expected: capture is running and logging KCS traffic.

- [ ] **Step 3: Force a full inventory push**

User clears BIOS NVRAM ("Restore Defaults" / "Reset NVRAM") so the BIOS sends full CPU/DIMM/PCIE
blocks, not the ~852-byte delta. Power the host through a full POST.
Expected: POST completes; the capture contains the full NetFn 0x32 conversation.

- [ ] **Step 4: Retrieve and normalize the capture**

Copy the raw capture off the OEM BMC to `/vagrant/oem-reference/protocol-reverse/golden-trace.txt`,
normalized to the `DIR NETFN CMD DATA...` hex form the decoder expects. Also copy the OEM's
resulting inventory JSON (its `/var/tmp/hi_inventory_files/inventory.json` or equivalent) to
`golden-payload.json`.
Expected: two files present; `golden-trace.txt` contains request+response pairs for cmd 0x2a, 0x3d,
0x5d, 0xab, and the data-carrying write command.

- [ ] **Step 5: Sanity-decode the trace**

Run: `cd tools/netfn32 && python3 -c "from decode_transcript import decode, pretty; print(pretty(decode(open('/vagrant/oem-reference/protocol-reverse/golden-trace.txt').read().splitlines())))"`
Expected: readable frames; `cmd 0x3d` response is exactly 33 bytes; the write command's payload
matches the CPU/DIMM data in `golden-payload.json`.

---

### Task 5: Reconcile into the authoritative protocol spec (the gate)

**Files:**
- Modify: `docs/redfish-inventory-netfn32-protocol.md` (promote UNCONFIRMED → CONFIRMED / correct)

**Interfaces:**
- Consumes: the Task 2 draft + the Task 4 golden trace/payload.
- Produces: the final protocol spec — the Phase 1 gate.

- [ ] **Step 1: Diff decompile hypotheses against live bytes**

For each command, compare the Task 2 hypothesized struct against the actual bytes in
`golden-trace.txt`. Where they disagree, the live bytes win. Resolve `cmd 0x3d`'s `DevStatus[32]`
semantics from the exact bytes the OEM returned and how the BIOS reacted (what it pushed next).
Expected: every command's request/response layout confirmed against the wire.

- [ ] **Step 2: Document the data-carrying command and payload encoding**

From the write command's frames + `golden-payload.json`, document exactly how CPU (Type 4), DIMM
(Type 17), and — if present — NVMe (Type 0xC2) data is encoded on the wire and how it maps to the
JSON. Record the storage(0xC2) presence finding explicitly (present / absent).
Expected: a receiver could be written to parse the payload from this section alone.

- [ ] **Step 3: Mark the spec CONFIRMED and record the Phase 1 handoff**

Update the spec status to CONFIRMED, add a short "Phase 1 handoff" section: which commands the
receiver must answer, their exact responses, and where the payload lands. Remove any remaining
UNCONFIRMED markers or downgrade genuinely-unresolved items to a listed open question.
Expected: no stray UNCONFIRMED markers except explicitly-listed open questions.

- [ ] **Step 4: Commit the confirmed spec**

```bash
git add docs/redfish-inventory-netfn32-protocol.md
git commit -m "docs: confirmed NetFn 0x32 inventory protocol (Phase 0 gate)"
```

- [ ] **Step 5: Update project memory**

Update `topic_redfish_inventory.md`: Phase 0 complete, protocol confirmed, pointer to the spec
doc; the "unlikely tractable" verdict is superseded by a live golden trace.

---

## Self-Review

**Spec coverage (against the design doc):**
- Design "Phase 0 — Discovery" → Tasks 1–5. ✓
- Live golden trace (authoritative) → Task 4. ✓
- Decompilation (corroborating) → Task 2. ✓
- Deliverable protocol spec as the gate → Task 5. ✓
- Command surface (0x2a/0x3d/0x5d/0xab + write cmd) → Tasks 2, 4, 5. ✓
- Storage type-0xC2 presence finding → Task 5 Step 2. ✓
- Guardrail against the empty-success stub → Global Constraints. ✓
- Phases 1–2 (receiver, translator) → deliberately deferred to a follow-on plan (tests need the
  confirmed bytes); noted at top and in Task 5 handoff. Not a gap — a scoping decision.
- Phase 3 (BMC NIC) → out of scope for this plan by user direction. ✓

**Placeholder scan:** the only code steps (Task 3) contain complete implementation + tests.
Procedural tasks (1, 2, 4, 5) are discovery, not code, and each ends with a concrete verification
gate and committed artifact — not "TODO". No forbidden placeholders.

**Type consistency:** `Frame{dir,netfn,cmd,data}` and `decode()`/`pretty()` are used consistently in
Task 3 and referenced identically in Task 4 Step 5.
