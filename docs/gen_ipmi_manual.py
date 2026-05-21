#!/usr/bin/env python3
"""Generate an HTML reference of the IPMI raw commands available on this BMC,
built directly from the two on-image allowlist configs."""
import re, html, datetime, pathlib

WORK = "/home/vagrant/openbmc-ami/build/tiogapass/tmp/work/arm1176jzs-openbmc-linux-gnueabi"
PHOS = f"{WORK}/phosphor-ipmi-host/1.0+git/git/host-ipmid-whitelist.conf"
INTEL = f"{WORK}/intel-ipmi-oem/0.1+git/git/ipmi-allowlist.conf"
OUT = "/home/vagrant/openbmc-ami/docs/ipmi-raw-commands.html"

NETFN_NAMES = {
    0x00: "Chassis", 0x04: "Sensor/Event", 0x06: "Application",
    0x08: "Firmware (Intel OEM)", 0x0A: "Storage", 0x0C: "Transport",
    0x2C: "Group Extension / DCMI", 0x2E: "OEM (OpenBMC blob + Intel Node Manager)",
    0x30: "Intel General Application (OEM)", 0x32: "Intel OEM Platform",
    0x3E: "Intel Managed Data Region (MDR)",
}

# Curated details for the commonly-used commands: friendly ipmitool subcommand,
# request data bytes, and response parsing.
DETAILS = {
 (0x00,0x01): dict(friendly="ipmitool chassis status  /  ipmitool power status",
   req="(none)",
   resp="B1 Current Power State (bit0=1 power on; [6:5]=restore policy), "
        "B2 Last Power Event, B3 Misc Chassis State (bit0 intrusion, [5:4] identify), "
        "B4 Front-Panel Button Capabilities. Power on/off = B1 &amp; 0x01."),
 (0x00,0x02): dict(friendly="ipmitool chassis power on|off|cycle|reset|soft",
   req="B1 = 0 power down, 1 power up, 2 power cycle, 3 hard reset, 4 pulse diag intr, 5 soft-off (ACPI)",
   resp="(none)"),
 (0x00,0x06): dict(friendly="ipmitool chassis policy list|always-on|previous|always-off",
   req="B1 policy: 0x00 always-off, 0x01 restore-previous, 0x02 always-on, 0x03 no-change (just query support)",
   resp="B1 = bitmask of <b>supported</b> policies: bit0 always-off, bit1 restore-previous, bit2 always-on "
        "(so <code>0x07</code> = all three supported). <b>This returns the supported set, NOT the current policy.</b> "
        "Read the current policy from Get Chassis Status (<code>raw 0x00 0x01</code>) byte&nbsp;1 bits&nbsp;[6:5]: "
        "00=always-off, 01=restore-previous, 10=always-on.", tested="impl"),
 (0x00,0x09): dict(friendly="ipmitool chassis bootparam get <n>",
   req="B1 param selector, B2 set selector, B3 block selector",
   resp="B1 param version, B2 param valid, B3.. data"),
 (0x04,0x2D): dict(friendly="ipmitool sensor / sdr  (per-sensor)",
   req="B1 = sensor number",
   resp="B1 reading (raw, apply SDR M/B/exp), B2 status (bit5=event-msg, bit6=scanning, bit7=reading-unavail), "
        "B3 threshold/discrete state, B4 discrete state hi"),
 (0x06,0x01): dict(friendly="ipmitool mc info",
   req="(none)",
   resp="B1 Device ID, B2 Device Rev, B3 FW major, B4 FW minor, B5 IPMI ver, B6 Additional Dev Support, "
        "B7-9 Manufacturer ID, B10-11 Product ID, B12-15 Aux FW rev"),
 (0x06,0x08): dict(friendly="(raw)  device GUID",
   req="(none)", resp="16-byte GUID (BMC). Falls back to machine-id on this build."),
 (0x06,0x37): dict(friendly="ipmitool mc guid",
   req="(none)", resp="16-byte System GUID. Used in RAKP msg 2/4; machine-id fallback on this build."),
 (0x06,0x42): dict(friendly="ipmitool channel info <ch>",
   req="B1 channel number (0x0E = current)",
   resp="B1 channel #, B2 medium type, B3 protocol, B4 session support/active count, ..."),
 (0x06,0x54): dict(friendly="ipmitool channel getciphers ipmi <ch>",
   req="B1 0x00 (IPMI), B2 channel, B3 list index",
   resp="B1 channel, then cipher-suite records. This BMC: only suite 17 (HMAC-SHA256)."),
 (0x0A,0x10): dict(friendly="ipmitool fru",
   req="B1 FRU device ID", resp="B1-2 inventory area size (LSB first), B3 access (0=byte,1=word)"),
 (0x0A,0x11): dict(friendly="ipmitool fru read",
   req="B1 FRU id, B2-3 offset (LSB first), B4 count to read",
   resp="B1 count returned, B2.. data"),
 (0x0A,0x20): dict(friendly="ipmitool sdr info",
   req="(none)", resp="B1 SDR version, B2-3 record count, B4-5 free space, ... reservation/timestamps"),
 (0x0A,0x23): dict(friendly="(used internally by 'ipmitool sdr')",
   req="B1-2 reservation ID, B3-4 record ID, B5 offset, B6 bytes to read (0xFF=all)",
   resp="B1-2 next record ID, B3.. record data"),
 (0x0A,0x40): dict(friendly="ipmitool sel info",
   req="(none)", resp="B1 SEL version, B2-3 entries, B4-5 free space, B6-9 last add time, B10-13 last erase, B14 op support"),
 (0x0A,0x43): dict(friendly="ipmitool sel list / elist",
   req="B1-2 reservation ID, B3-4 record ID (0x0000=first,0xFFFF=last), B5 offset, B6 bytes (0xFF=all)",
   resp="B1-2 next record ID, B3.. 16-byte SEL record"),
 (0x0A,0x48): dict(friendly="ipmitool sel time get", req="(none)", resp="4-byte timestamp (LSB first)"),
 (0x0C,0x02): dict(friendly="ipmitool lan print <ch>",
   req="B1 channel, B2 param selector, B3 set, B4 block",
   resp="B1 param rev, B2.. data (IP, MAC, etc.)"),
 (0x2C,0x01): dict(friendly="ipmitool dcmi discover",
   req="B1 0xDC (group), B2 param selector (1=supported caps)",
   resp="B1 0xDC, B2 major, B3 minor, B4 param rev, B5.. caps", grp="DCMI"),
 (0x2C,0x02): dict(friendly="ipmitool dcmi power reading",
   req="B1 0xDC (group), B2 mode (0x01=system power statistics), B3 attributes, B4 reserved",
   resp="B1 0xDC, B2-3 current watts (LSB first), B4-5 min, B6-7 max, B8-9 avg, B10-13 timestamp, "
        "B14-17 sampling period, B18 power-state. Far cheaper than an SDR walk for power polling.", grp="DCMI"),
 (0x2C,0x10): dict(friendly="(raw) DCMI temperature readings",
   req="B1 0xDC, B2 sensor type (0x01 inlet,0x03 CPU,0x07 baseboard), B3 entity id, B4 entity instance, B5 instance start",
   resp="B1 0xDC, B2 total instances, B3 count, then temp records", grp="DCMI"),
 (0x30,0x8d): dict(friendly="(raw) Get Fan Speed Offset",
   req="(none)",
   resp="B1 = current fan-speed <b>offset</b> in PWM&nbsp;% (e.g. <code>0x0a</code> = 10%). This is an Intel SmartFan "
        "offset <b>added on top of</b> the swampd/PID-computed fan PWM — it is not an absolute fan speed.", tested="impl"),
 (0x30,0x8c): dict(friendly="(raw) Set Fan Speed Offset",
   req="B1 = offset in PWM&nbsp;% added to the PID-computed duty. e.g. <code>raw 0x30 0x8c 0x14</code> = +20%. "
       "(verified: request is 1 byte, no response data)",
   resp="(none). For an <b>absolute</b> manual fan duty instead of an offset, use the D-Bus PWM override: "
        "<code>busctl set-property xyz.openbmc_project.FanSensor /xyz/openbmc_project/control/fanpwm/Pwm_1 "
        "xyz.openbmc_project.Control.FanPwm Target t &lt;0-255&gt;</code>.", tested="impl"),
 (0x30,0x8a): dict(friendly="(raw) Get Fan Control Configuration",
   req="Intel FSC parameter selector — platform-specific (selector 0x00 returns 0xCC on this build).",
   resp="depends on selector. Implemented, but the FSC parameter format is Intel-proprietary.", tested="impl"),
 (0x30,0x91): dict(friendly="(raw) Get/Set FSC Parameter",
   req="Intel FSC multi-byte selector — platform-specific (0x00 → 0xC9 out-of-range; 0x01 → 0xC7 needs more bytes).",
   resp="depends on selector. Implemented, but the FSC parameter format is Intel-proprietary.", tested="impl"),
 (0x30,0x9d): dict(friendly="(raw) Get Fan PWM Limit", req="—",
   resp="<b>Not implemented on this build</b> — returns <code>0xC1 Invalid command</code>.", tested="noimpl"),
 (0x30,0x85): dict(friendly="(raw) Get SF PWM", req="—",
   resp="<b>Not implemented on this build</b> — returns <code>0xC1 Invalid command</code>.", tested="noimpl"),
 (0x32,0x63): dict(friendly="(raw) Get Tach Information", req="—",
   resp="<b>Not implemented on this build</b> — returns <code>0xC1 Invalid command</code>. Read fan RPM via "
        "Get Sensor Reading (<code>raw 0x04 0x2D &lt;tach-sensor#&gt;</code>) on the *TACH sensors instead.", tested="noimpl"),
}

# IPMI completion codes (response byte 0, stripped by ipmitool but shown on error)
COMP_CODES = [
 ("0x00","Command completed normally"),
 ("0xC0","Node busy — try again later"),
 ("0xC1","Invalid/unsupported command (handler not registered)"),
 ("0xC2","Invalid command for given LUN"),
 ("0xC3","Timeout completing command"),
 ("0xC4","Out of space"),
 ("0xC5","Reservation canceled or invalid reservation ID"),
 ("0xC6","Request data truncated"),
 ("0xC7","Request data length invalid (wrong number of bytes)"),
 ("0xC8","Request data field length limit exceeded"),
 ("0xC9","Parameter out of range"),
 ("0xCA","Cannot return number of requested data bytes"),
 ("0xCB","Requested sensor/data/record not present"),
 ("0xCC","Invalid data field in request"),
 ("0xCD","Command illegal for specified sensor/record type"),
 ("0xD4","Insufficient privilege level / cipher"),
 ("0xD5","Command not supported in present state"),
 ("0xD6","Subfunction unavailable (disabled)"),
 ("0xFF","Unspecified error"),
]

def parse(path, intel):
    rows = []
    for line in pathlib.Path(path).read_text().splitlines():
        s = line.strip()
        m = re.match(r'0x([0-9A-Fa-f]+)\s*:\s*0x([0-9A-Fa-f]+)(?:\s*:\s*0x([0-9A-Fa-f]+))?\s*//?\s*(.*)', s)
        if not m:
            continue
        nf, cmd = int(m.group(1),16), int(m.group(2),16)
        mask = int(m.group(3),16) if m.group(3) else None
        # name = strip <Group>:<Name> -> Name
        raw = m.group(4)
        nm = re.findall(r'<([^>]*)>', raw)
        name = nm[-1] if nm else raw
        rows.append((nf, cmd, mask, name.strip()))
    return rows

intel = parse(INTEL, True)
phos = parse(PHOS, False)
phos_set = {(nf,cmd) for nf,cmd,_,_ in phos}

# merge: key (nf,cmd) -> name (prefer intel), mask, restricted flag
cmds = {}
for nf,cmd,mask,name in intel:
    cmds[(nf,cmd)] = dict(nf=nf,cmd=cmd,mask=mask,name=name)
for nf,cmd,mask,name in phos:
    cmds.setdefault((nf,cmd), dict(nf=nf,cmd=cmd,mask=0xffff,name=name))

total = len(cmds)
restricted_n = len(phos_set)
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

def esc(x): return html.escape(str(x))

rowshtml = []
for (nf,cmd) in sorted(cmds):
    c = cmds[(nf,cmd)]
    restricted = (nf,cmd) in phos_set
    mask = c['mask']
    lan = "—" if mask is None else ("yes" if (mask & 0x0002) else "no")
    det = DETAILS.get((nf,cmd))
    raw = f"raw 0x{nf:02x} 0x{cmd:02x}"
    badge = '<span class="b r">restricted-ok</span>' if restricted else ''
    dcmi = ''
    detblock = ''
    if det:
        dcmi = '<span class="b d">DCMI</span>' if det.get('grp')=="DCMI" else ''
        detblock = (f'<div class="det">'
                    f'<div><b>ipmitool:</b> <code>{esc(det["friendly"])}</code></div>'
                    f'<div><b>request:</b> {esc(det["req"])}</div>'
                    f'<div><b>response:</b> {det["resp"]}</div></div>')
    masktxt = '—' if mask is None else f'0x{mask:04x}'
    rowshtml.append(
      f'<tr class="cmd" data-s="{esc(("%02x %02x %s"%(nf,cmd,c["name"])).lower())}">'
      f'<td class="hx">0x{nf:02x}</td><td class="hx">0x{cmd:02x}</td>'
      f'<td>{esc(c["name"])} {badge}{dcmi}</td>'
      f'<td class="mono">{esc(raw)}</td>'
      f'<td class="ctr">{lan}</td><td class="ctr mono">{masktxt}</td>'
      f'</tr>')
    if detblock:
        rowshtml.append(f'<tr class="detrow"><td colspan="6">{detblock}</td></tr>')

groups = {}
for (nf,cmd) in cmds:
    groups.setdefault(nf, 0)
    groups[nf]+=1
groupnav = " ".join(
    f'<a href="#nf{nf:02x}">0x{nf:02x} {esc(NETFN_NAMES.get(nf,"?"))} ({groups[nf]})</a>'
    for nf in sorted(groups))

# build per-group tables
sections = []
for nf in sorted(groups):
    body = []
    for (n,cmd) in sorted(cmds):
        if n!=nf: continue
        c = cmds[(n,cmd)]
        restricted = (n,cmd) in phos_set
        mask = c['mask']; lan = "—" if mask is None else ("✓" if (mask&0x02) else "✗")
        det = DETAILS.get((n,cmd))
        raw = f"raw 0x{n:02x} 0x{cmd:02x}"
        badge = '<span class="b r" title="Allowed even when the channel is in restricted mode (phosphor allowlist)">restricted-ok</span>' if restricted else ''
        dcmi = '<span class="b d">DCMI</span>' if det and det.get('grp')=="DCMI" else ''
        tb = ''
        if det and det.get('tested')=='impl':
            tb = '<span class="b i" title="Verified responding on this build">impl&nbsp;✓</span>'
        elif det and det.get('tested')=='noimpl':
            tb = '<span class="b n" title="Allowlisted but handler not registered — returns 0xC1">not&nbsp;impl&nbsp;✗</span>'
        masktxt='—' if mask is None else f'0x{mask:04x}'
        body.append(
          f'<tr class="cmd" data-s="{esc(("%02x %02x %s"%(n,cmd,c["name"])).lower())}">'
          f'<td class="hx">0x{n:02x}</td><td class="hx">0x{cmd:02x}</td>'
          f'<td>{esc(c["name"])} {badge}{dcmi}{tb}</td>'
          f'<td class="mono">{esc(raw)}</td><td class="ctr">{lan}</td><td class="ctr mono">{masktxt}</td></tr>')
        if det:
            body.append('<tr class="detrow"><td colspan="6"><div class="det">'
                f'<div><b>ipmitool:</b> <code>{esc(det["friendly"])}</code></div>'
                f'<div><b>request data:</b> {det["req"]}</div>'
                f'<div><b>response:</b> {det["resp"]}</div></div></td></tr>')
    sections.append(
      f'<h2 id="nf{nf:02x}">NetFn 0x{nf:02x} — {esc(NETFN_NAMES.get(nf,"Unknown"))} '
      f'<span class="cnt">{groups[nf]} commands</span></h2>'
      f'<table><thead><tr><th>NetFn</th><th>Cmd</th><th>Command</th>'
      f'<th>ipmitool raw</th><th>LAN</th><th>Chan&nbsp;mask</th></tr></thead>'
      f'<tbody>{"".join(body)}</tbody></table>')

compcodes = "".join(f'<tr><td class="hx">{cc}</td><td>{esc(desc)}</td></tr>' for cc,desc in COMP_CODES)

doc = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TiogaPass BMC — IPMI Raw Command Reference</title>
<style>
:root{{--bg:#0f1419;--card:#1a2129;--fg:#d7dee6;--mut:#8b97a3;--acc:#5cc8ff;--line:#2a333d;}}
*{{box-sizing:border-box}}
body{{margin:0;font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}}
header{{padding:24px 28px;border-bottom:1px solid var(--line);background:var(--card);position:sticky;top:0;z-index:5}}
h1{{margin:0 0 4px;font-size:20px}}
.sub{{color:var(--mut);font-size:13px}}
.wrap{{max-width:1100px;margin:0 auto;padding:0 20px 80px}}
.bar{{display:flex;gap:12px;align-items:center;margin-top:12px;flex-wrap:wrap}}
#q{{flex:1;min-width:240px;padding:9px 12px;border:1px solid var(--line);border-radius:8px;background:#0b0f14;color:var(--fg);font-size:14px}}
.stat{{color:var(--mut);font-size:12px}}
.nav{{margin:16px 0;line-height:2}}
.nav a{{color:var(--acc);text-decoration:none;font-size:12px;margin-right:12px;white-space:nowrap}}
.nav a:hover{{text-decoration:underline}}
.note{{background:#16202b;border:1px solid var(--line);border-left:3px solid var(--acc);padding:12px 16px;border-radius:6px;margin:16px 0;font-size:13px}}
.note code,code{{background:#0b0f14;padding:1px 5px;border-radius:4px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;color:#e6c07b}}
h2{{margin:30px 0 8px;font-size:16px;border-bottom:1px solid var(--line);padding-bottom:6px;scroll-margin-top:120px}}
.cnt{{color:var(--mut);font-size:12px;font-weight:400}}
table{{width:100%;border-collapse:collapse;margin-bottom:6px}}
th,td{{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.04em}}
.hx,.mono{{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px}}
.hx{{color:#9ad}}.ctr{{text-align:center}}
tr.cmd:hover{{background:#141c24}}
.b{{display:inline-block;font-size:10px;padding:1px 6px;border-radius:10px;margin-left:6px;vertical-align:middle}}
.b.r{{background:#1d3a2a;color:#7fe0a8;border:1px solid #2c5740}}
.b.d{{background:#3a2a1d;color:#e0b97f;border:1px solid #57452c}}
.b.i{{background:#143026;color:#6ee7a8;border:1px solid #235f43}}
.b.n{{background:#3a1d20;color:#ff9aa0;border:1px solid #5e2a30}}
details.cc{{background:#16202b;border:1px solid var(--line);border-radius:6px;margin:16px 0;padding:6px 16px}}
details.cc summary{{cursor:pointer;font-size:13px;font-weight:600;padding:6px 0}}
details.cc table{{margin:6px 0}} details.cc td:first-child{{width:80px}}
.det{{background:#0b0f14;border-radius:6px;padding:8px 12px;margin:2px 0 8px;font-size:12.5px;color:var(--mut)}}
.det b{{color:var(--fg)}} .det code{{color:#7fe0a8}}
.detrow td{{border-bottom:1px solid var(--line);padding-top:0}}
footer{{color:var(--mut);font-size:12px;margin-top:30px;border-top:1px solid var(--line);padding-top:14px}}
</style></head><body>
<header>
 <h1>TiogaPass BMC — IPMI Raw Command Reference</h1>
 <div class="sub">flax-onetree-1.0.3 · generated {now} from on-image allowlists
   (host-ipmid-whitelist.conf + intel-ipmi-oem ipmi-allowlist.conf)</div>
 <div class="bar">
   <input id="q" placeholder="Filter by name, NetFn, or command (e.g. 'power', '0x2c', 'sel')…" autocomplete="off">
   <span class="stat" id="stat"></span>
 </div>
</header>
<div class="wrap">
 <div class="note">
  <b>Invocation (LAN):</b> <code>ipmitool -I lanplus -C 17 -H &lt;bmc-ip&gt; -U root -P &lt;pw&gt; raw &lt;netfn&gt; &lt;cmd&gt; [data…]</code><br>
  This BMC accepts only <b>cipher suite 17</b> (HMAC-SHA256) — pass <code>-C 17</code> (or use a client that auto-negotiates). NetFn values shown are the request (even) NetFn.
 </div>
 <div class="note">
  <b>Two allowlist layers.</b> <b>{total}</b> commands are registered/permitted (intel-ipmi-oem list, with a per-channel mask).
  The <b>LAN</b> column shows whether the command is permitted on the LAN channel (channel&nbsp;1). The <span class="b r">restricted-ok</span>
  badge marks the <b>{restricted_n}</b> commands in the phosphor restricted-mode allowlist — the only ones that work when a channel's
  restriction mode is set to <i>restricted</i> (the source of the <code>Channel/NetFn/Cmd not Allowlisted</code> rejection). A
  <code>0x0000</code> mask means the command is not exposed on standard channels (internal/SMM only). DCMI commands need group byte
  <code>0xDC</code> as the first data byte.<br>
  Where verified on the running build, commands are tagged <span class="b i">impl&nbsp;✓</span> (responding) or
  <span class="b n">not&nbsp;impl&nbsp;✗</span> (allowlisted but the handler isn't registered — returns <code>0xC1</code>).
  Untagged = not individually tested.
 </div>
 <details class="cc"><summary>IPMI completion codes (response status byte)</summary>
  <p style="color:var(--mut);font-size:12px;margin:4px 0">ipmitool strips the leading completion-code byte on success and prints it on failure
  (e.g. <code>rsp=0xc7</code>). Common values on this BMC:</p>
  <table><tbody>{compcodes}</tbody></table>
 </details>
 <div class="nav">{groupnav}</div>
 {''.join(sections)}
 <footer>Generated from the running build's allowlist configs. Channel mask bit&nbsp;N = channel&nbsp;N
   (<code>1&lt;&lt;channel</code>); LAN = channel&nbsp;1 (0x0002), system interface/KCS = channel&nbsp;15 (0x8000).
   Request/response byte layouts for highlighted commands follow the IPMI 2.0 / DCMI 1.5 specs; verify against your firmware before scripting writes.</footer>
</div>
<script>
const q=document.getElementById('q'), stat=document.getElementById('stat');
const rows=[...document.querySelectorAll('tr.cmd')];
function upd(){{
 const t=q.value.trim().toLowerCase(); let n=0;
 for(const r of rows){{
   const show=!t||r.dataset.s.includes(t); r.style.display=show?'':'none';
   const d=r.nextElementSibling; if(d&&d.classList.contains('detrow')) d.style.display=show?'':'none';
   if(show)n++;
 }}
 stat.textContent=n+' / '+rows.length+' commands';
 for(const h of document.querySelectorAll('h2')){{
   let e=h.nextElementSibling, any=false;
   while(e&&e.tagName!=='H2'){{ if(e.tagName==='TABLE'){{ any=[...e.querySelectorAll('tr.cmd')].some(r=>r.style.display!=='none'); }} e=e.nextElementSibling; }}
   h.style.display=any?'':'none';
 }}
}}
q.addEventListener('input',upd); upd();
</script>
</body></html>"""

pathlib.Path(OUT).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(OUT).write_text(doc)
print(f"wrote {OUT}  ({len(doc)} bytes)")
print(f"commands: {total} total, {restricted_n} restricted-mode")
