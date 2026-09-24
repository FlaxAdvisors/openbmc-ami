# Continuation Prompt — meta-ami overlay restructure (Phase 1)

Paste the block below into a new session to resume.

---

We're restructuring this repo from a vendored AMI OneTree `openbmc` superproject fork
into a **thin `meta-flax` overlay** composed (by pinned reference) onto AMI's layer model:
base `openbmc` + `meta-common` + `meta-ami` + `meta-intel-openbmc` + `meta-flax`.
Full assessment + Phase 1 scope is in memory `topic-meta-ami-overlay-migration`.

Established facts:
- Our root repo = fork of AMI OneTree `openbmc` superproject (subtrees), HEAD `b2ac0c8c`.
  Base layers (meta=poky symlink, meta-phosphor, meta-aspeed, meta-intel-openbmc,
  meta-openembedded, meta-security, meta-arm) are vendored subtrees. `meta-flax` is our
  ONLY delta (confirmed). `meta-ami` (`ad131770`, upstream ocp now `7d665ce5`) and
  `meta-common` (`a79e47eb`) are gitignored separate clones from `ocp-hm-openbmc-opf-ami`.
  `meta-megarac` (pri 6) is an ORPHAN: untracked, no .git, no origin.
- `meta-flax`: no LAYERDEPENDS, pri 20; patches Intel recipes (intel-ipmi-oem, smbios-mdr,
  entity-manager/FBTP.json) → meta-intel-openbmc is a mandatory compose dep.
- bblayers order to preserve: meta → meta-oe/networking/python → meta-phosphor → meta-aspeed
  → meta-common → meta-common/meta-common → meta-flax → meta-ami → meta-intel-openbmc
  → meta-megarac → build/tiogapass/workspace. MACHINE=tiogapass, DISTRO=openbmc-phosphor.

Phase 1 = zero functional change, prove-before-delete. Gate: composed build must be
recipe-diff-identical to today's `b2ac0c8c` build before deleting any vendored layer.

Start with TASK 1 (read-only, the de-risking gate):
1. Fetch AMI `ocp-hm-openbmc-opf-ami/openbmc`; find the commit our fork last subtree-synced
   from; diff its meta/meta-phosphor/meta-aspeed/meta-openembedded against our b2ac0c8c —
   the diff MUST be empty (only meta-flax + root helpers should differ). Verify the stray
   `447f51b8 linux-aspeed v6.6.27` commits are AMI-origin (subtree), not Flax edits.
2. Confirm whether `meta-intel-openbmc` and `meta-megarac` live in AMI's base superproject;
   if not, plan to pin them as separate clones.

Two decisions to confirm with me before building artifacts:
1. Base source = AMI upstream `openbmc` (true alignment) vs our fork `@b2ac0c8c`
   (byte-identical safety net first, re-point later)?
2. Do all work in a throwaway scratch worktree (recommended) — touch nothing until gate passes.

Deliverables (in order, gated on the build diff): `tiogapass.pinlist`, `setup-tiogapass.sh`,
`conf/templates/tiogapass/{bblayers,local}.conf.sample`, verified-equivalent build, then the
cleanup commit removing vendored bases.

Discipline: PIN revisions, don't float on HEAD.
