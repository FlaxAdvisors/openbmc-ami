# Hunt for AST2500: Evaluating AMI's GitHub Repos as Submodules

**Document type:** Technical Evaluation
**Scope:** Can AMI's public OpenBMC repositories (meta-ami, meta-core, bmcweb, phosphor-networkd, phosphor-host-ipmid) be used as git submodules to benefit the TiogaPass (AST2500) build?

---

## 1. Context

This repository's `upstream` remote is `ocp-hm-openbmc-opf-ami/openbmc` — it is literally AMI's
OpenBMC fork. The dead BBMASK entries in `meta-flax/conf/layer.conf` referencing
`meta-ami/meta-common/` were the conflict-resolution mechanism for when `meta-ami` was cloned
as a sibling directory. AMI's intended build model is:

```
openbmc/          <-- this repo (we have it)
meta-common/      <-- clone of ocp-hm-openbmc-opf-ami/meta-core (optional)
meta-ami/         <-- clone of ocp-hm-openbmc-opf-ami/meta-ami
```

So adding `meta-ami` as a submodule is architecturally coherent with how this repo was originally
designed to be used. The question is whether it helps the TiogaPass.

---

## 2. AMI GitHub Organisation Overview

**Organisation:** `ocp-hm-openbmc-opf-ami` (Open Compute Project + AMI)
**Total public repositories:** 45
**Product branding:** "OneTree" (OT) — AMI's commercial OpenBMC product
**Build orchestration:** No repo manifest, no `.gitmodules`. Manual `git clone` of 3-4 repos + Yocto `TEMPLATECONF`.

---

## 3. Repository-by-Repository Findings

### 3.1 meta-ami

| Property | Value |
|---|---|
| URL | `https://github.com/ocp-hm-openbmc-opf-ami/meta-ami` |
| Default branch | `ocp` |
| Branches | 6 (`ocp`, `3.0.1-merge`, `bmcweb_srcrev_update`, `OT-2.1_build_fix`, `OT-2.1_sync_up`, `bmcweb_ocp`) |
| Yocto compat | `nanbield scarthgap` (4.3 / 5.0) |
| Last updated | October 2025 (2,306 commits) |
| .gitmodules | No |

**Purpose:** AMI's primary Yocto metadata layer. Contains BSP configurations, machine definitions,
and build templates for AMI's supported evaluation boards.

**AST chip support:**

| SoC | Supported | Machine path |
|---|---|---|
| **AST2500** | **No** | — |
| AST2600 | Yes | `meta-evb/meta-evb-aspeed/meta-evb-ast2600/` |
| AST2700 | Yes | `meta-evb/meta-evb-aspeed/meta-evb-ast2700/` |
| Nuvoton NPCM845 | Yes | `meta-evb/meta-evb-nuvoton/meta-evb-npcm845/` |

**Verdict for TiogaPass: Not usable.** No AST2500 machine definition, BSP, or build template
exists. The entire layer-level content (machine conf, u-boot recipes, kernel BSP) is irrelevant
for AST2500.

### 3.2 meta-core (Intel BKC)

| Property | Value |
|---|---|
| URL | `https://github.com/ocp-hm-openbmc-opf-ami/meta-core` |
| Default branch | `ocp` |
| Branches | 3 (`ocp`, `3.0.1-merge`, `OT-2.1_sync_up`) |
| Yocto compat | `nanbield scarthgap` |
| Last updated | October 2025 (3 commits — squashed import) |
| .gitmodules | No |

**Purpose:** Intel's OpenBMC firmware meta-layer distributed as a "Best-Known Configuration" (BKC)
release. Contains `meta-ast2600/`, `meta-common/`, and utility scripts.

**AST chip support:**

| SoC | Supported |
|---|---|
| **AST2500** | **No** |
| AST2600 | Yes (`meta-ast2600/` with BSP, u-boot, security, IKVM recipes) |
| AST2700 | No |

**Verdict for TiogaPass: Not usable.** AST2600-only. Not a substitute for the already-in-tree
`meta-intel-openbmc`, which _does_ contain AST2500 reference content (the S2600WF machine is
an AST2500 platform).

### 3.3 bmcweb

| Property | Value |
|---|---|
| URL | `https://github.com/ocp-hm-openbmc-opf-ami/bmcweb` |
| Default branch | `master` |
| Branches | 2 (`master`, `fix-bmcweb-coredump-issue`) |
| Last updated | January 2026 (3,486 commits, active development) |
| .gitmodules | No (uses Meson `subprojects/` wraps, not git submodules) |

**Purpose:** AMI's fork of the OpenBMC embedded web server. Carries AMI-specific patches on top
of upstream bmcweb: Redfish parse error fixes, dump creation limits, chassis ID logic improvements.

**AST chip dependency: None.** bmcweb is a userspace HTTP server, entirely hardware-agnostic.

**Verdict for TiogaPass: Potentially useful**, but should be consumed via BitBake `SRC_URI`
override, not as a git submodule. See Section 5.

### 3.4 phosphor-networkd

| Property | Value |
|---|---|
| URL | `https://github.com/ocp-hm-openbmc-opf-ami/phosphor-networkd` |
| Default branch | `main` |
| Branches | 1 |
| Last updated | January 2026 (active development) |
| .gitmodules | No |

**Purpose:** AMI's fork of the OpenBMC network management daemon. Adds dual-node support,
IPv4/IPv6 flushing improvements, GARP control, Clang 19 formatting fixes.

**AST chip dependency: None.** Userspace network daemon.

**Verdict for TiogaPass: Potentially useful** via `SRC_URI` override.

### 3.5 phosphor-host-ipmid

| Property | Value |
|---|---|
| URL | `https://github.com/ocp-hm-openbmc-opf-ami/phosphor-host-ipmid` |
| Default branch | `main` |
| Branches | 19+ (`main`, `master`, plus OT-ticket branches for DCMI, boot options, system info, alerts, global enables) |
| Last updated | January 2026 (active development) |
| .gitmodules | No |

**Purpose:** AMI's fork of the IPMI host daemon. Carries significant patches: DCMI power
management, boot option handling, system info parameters, alert support, default user creation,
Intel LF sync patches.

**AST chip dependency: None.** IPMI is a protocol-level daemon.

**Verdict for TiogaPass: Potentially useful** via `SRC_URI` override. The DCMI and boot option
patches are relevant to any x86 IPMI deployment.

---

## 4. AST2500 Support Summary

| Repository | AST2500 | AST2600 | AST2700 | Useful for TiogaPass? |
|---|---|---|---|---|
| **meta-ami** | **No** | Yes | Yes | **No** — no BSP |
| **meta-core** | **No** | Yes | No | **No** — no BSP |
| **bmcweb** | N/A | N/A | N/A | **Yes** — hardware-agnostic |
| **phosphor-networkd** | N/A | N/A | N/A | **Yes** — hardware-agnostic |
| **phosphor-host-ipmid** | N/A | N/A | N/A | **Yes** — hardware-agnostic |
| **meta-intel-openbmc** (in-tree) | **Yes** | No | No | **Yes** — S2600WF is AST2500 |

AMI has moved on from AST2500 in their "OneTree" product line. Their commercial customers are
on AST2600/AST2700. The AST2500 is effectively end-of-life in AMI's stack.

---

## 5. Git Submodules Are the Wrong Mechanism

Even for the hardware-agnostic daemon forks that could be useful, git submodules are the wrong
abstraction. BitBake is its own dependency manager. The correct way to consume AMI's daemon forks
is via `SRC_URI` overrides in `.bbappend` files:

```bitbake
# Example: meta-tiogapass-lf/recipes-phosphor/interfaces/bmcweb_%.bbappend
# Override upstream bmcweb source with AMI's fork
SRC_URI = "git://github.com/ocp-hm-openbmc-opf-ami/bmcweb.git;branch=master;protocol=https"
SRCREV = "<pin-to-specific-commit>"
```

This approach:
- Integrates with BitBake's fetch/unpack/patch pipeline natively
- Allows pinning to a specific commit (reproducible builds)
- Can be selectively applied per-recipe without pulling in an entire layer
- Does not pollute the git history with submodule tracking commits
- Is how every other OpenBMC platform handles source overrides

A git submodule checkout of `meta-ami` would be inert — BitBake would not discover its recipes
unless it were also added to `bblayers.conf`, and adding it to `bblayers.conf` would reintroduce
the same kind of layer conflict that MOVING_FORWARD.md's plan aims to eliminate.

---

## 6. Impact on MOVING_FORWARD.md Plan

### What the plan already gets right

- Correctly identifies `meta-ami` as non-existent in the tree (Section 3.7, 6.1)
- Correctly identifies BBMASK entries as dead code from a prior deployment context
- Correctly activates `meta-intel-openbmc` (which does support AST2500)
- The upstream-first + `meta-tiogapass-lf` architecture is the right path

### What the plan could add as a forward-looking note

1. **AMI's daemon forks as optional Phase 3+ recipe overrides.** After the base migration
   stabilises (Phases 1-2), individual AMI daemon forks (bmcweb, phosphor-host-ipmid,
   phosphor-networkd) could be evaluated recipe-by-recipe for patches that upstream hasn't
   merged. This is a `SRC_URI` override in `meta-tiogapass-lf`, not a submodule.

2. **Explicit AST2500 EOL statement.** Anyone considering re-adding `meta-ami` to this build
   should know that AMI dropped AST2500 support. The `meta-ami` layer cannot produce a
   TiogaPass image without significant porting effort that would defeat the purpose of using it.

3. **meta-core is not a substitute for meta-intel-openbmc.** The in-tree `meta-intel-openbmc`
   already provides Intel platform management recipes for AST2500 (the S2600WF reference).
   AMI's `meta-core` is a newer, AST2600-only Intel BKC that does not replace it.

### What does NOT change

The migration execution sequence (MOVING_FORWARD.md Section 10) remains valid as-is. No
submodules need to be added. The `meta-tiogapass-lf` layer + `meta-intel-openbmc` activation
path is correct for AST2500.

---

## 7. Full AMI Organisation Repo Inventory

The `ocp-hm-openbmc-opf-ami` GitHub organisation hosts 45 public repositories. Notable ones
beyond those analysed above:

| Repo | Description |
|---|---|
| `openbmc` | Base OpenBMC fork (this repo's upstream) |
| `meta-common` | Alias/older name for meta-core content |
| `dbus-sensors` | AMI fork of sensor daemon |
| `webui-vue` | AMI fork of Vue.js BMC web frontend |
| `pldmd` | PLDM daemon fork |
| `linux` | Kernel fork |
| `libmctp` | MCTP library fork |
| `mctpd` / `mctpwplus` | MCTP daemon forks |
| `spdmd` | SPD memory info daemon |
| `virtual-media` | Virtual media daemon |
| `intel-ipmi-oem` | Intel OEM IPMI commands (also in meta-intel-openbmc) |

All follow the same pattern: AMI forks of upstream LF OpenBMC components with proprietary patches
that AMI maintains outside the upstream review process.

---

## 8. Recommendations

1. **Do not add meta-ami or meta-core as submodules.** They cannot build for AST2500 and would
   reintroduce layer conflicts.

2. **Do not add daemon repos as submodules.** Use BitBake `SRC_URI` overrides if/when specific
   AMI patches are needed.

3. **Keep meta-intel-openbmc as the Intel platform layer.** It is the only Intel layer in the
   ecosystem that supports AST2500.

4. **Proceed with the MOVING_FORWARD.md plan as designed.** The architecture is correct. AMI's
   repos are a resource to cherry-pick from at the recipe level, not a foundation to build on.

5. **Monitor AMI's daemon forks for useful patches.** After Phase 2 of the migration, evaluate
   whether AMI's bmcweb or phosphor-host-ipmid patches address gaps in the upstream versions
   (especially DCMI, Redfish fixes, and boot option handling).

---

## References

- [MOVING_FORWARD.md](MOVING_FORWARD.md) — Migration plan from Facebook/Flax layers to
  `meta-tiogapass-lf` + `meta-intel-openbmc` (see Sections 3.7, 5, 6.1 for meta-ami context)
- [FUNCTIONALITY.md](FUNCTIONALITY.md) — Full recipe and capability map for the current build
  (see "Hardware Descriptor Files" section for AST2500 platform details)
- AMI GitHub: `https://github.com/ocp-hm-openbmc-opf-ami`
