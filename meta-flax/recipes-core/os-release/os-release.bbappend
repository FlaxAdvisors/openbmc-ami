# Flax-branded version string for TiogaPass builds.
#
# Format (dev):     flax-onetree-<version>-<timestamp>  e.g. flax-onetree-1.0.0-202604011404
# Format (release): flax-onetree-<version>              e.g. flax-onetree-1.0.0
#
# To cut a release build:  set FLAX_RELEASE = "1" in local.conf or on the bitbake command line
# To bump the version:     change FLAX_VERSION below
#
# This bbappend owns /etc/os-release outright: meta-ami's and
# meta-common/meta-common's os-release bbappends are BBMASKed in
# conf/layer.conf, so the fields and the provenance block they used to supply
# are defined here instead.  That keeps the whole thing in our layer, which is
# the only one that survives the move onto a canonical OpenBMC tree.

require flax-provenance.inc

FLAX_VERSION = "1.1.0"
FLAX_RELEASE ?= "0"

# Repos to record provenance for.  Absent ones, and layers with no .git of
# their own, are skipped -- so this needs no edit when the layer set changes.
FLAX_PROVENANCE_REPOS ?= "${COREBASE} ${COREBASE}/meta-ami ${COREBASE}/meta-common"

# Previously supplied by meta-common/meta-common's bbappend.
OS_RELEASE_FIELDS:append = " OPENBMC_VERSION IPMI_MAJOR IPMI_MINOR IPMI_AUX13 IPMI_AUX14 IPMI_AUX15 IPMI_AUX16"
OS_RELEASE_FIELDS:remove = "BUILD_ID EXTENDED_VERSION"

# os-release.bb hashes VERSION_ID/VERSION into do_compile via
# OS_RELEASE_FIELDS, and our dev version string ends in a minute-granularity
# timestamp.  Any build whose parse and execution land either side of a minute
# boundary therefore sees the basehash change underneath it and dies with
# "metadata is not deterministic" / "Taskhash mismatch".  It is luck-of-the-clock
# flaky, and it bit a full image build on 2026-08-17.
#
# Exclude the timestamped values from the task hash and depend on the inputs
# that actually matter instead, so a FLAX_VERSION bump still rebuilds.  Upstream
# does the same for its own BUILD_ID (os-release.bb: BUILD_ID[vardepsexclude]).
do_compile[vardepsexclude] += "OPENBMC_VERSION VERSION_ID VERSION DATETIME"
do_compile[vardeps] += "FLAX_VERSION FLAX_RELEASE"

python() {
    flax_version = d.getVar('FLAX_VERSION') or '1.0.0'
    flax_release = d.getVar('FLAX_RELEASE') or '0'
    # DATETIME is in BB_HASHBASE_WHITELIST -- safe to use without causing sstate hash churn.
    dt = d.getVar('DATETIME') or ''
    timestamp = dt[0:12] if len(dt) >= 12 else dt

    if flax_release == '1':
        ver_string = 'flax-onetree-' + flax_version
    else:
        ver_string = 'flax-onetree-' + flax_version + '-' + timestamp

    d.setVar('OPENBMC_VERSION', ver_string)
    d.setVar('VERSION_ID', ver_string)
    d.setVar('VERSION', 'flax-onetree-' + flax_version)

    parts = (flax_version + '.0.0').split('.')
    d.setVar('IPMI_MAJOR', parts[0])
    d.setVar('IPMI_MINOR', parts[1])

    # IPMI Auxiliary Firmware Revision.  AUX14-16 carry the first three bytes of
    # the meta-ami HEAD, which is what version-vars.inc used to publish; keep
    # that so `ipmitool mc info` does not change under the fleet.  Falls back to
    # COREBASE once meta-ami is no longer a separate checkout.
    corebase = d.getVar('COREBASE') or ''
    aux_repo = os.path.join(corebase, 'meta-ami')
    if not flax_is_git_repo(aux_repo):
        aux_repo = corebase
    aux_hash = (flax_git(d, aux_repo, ['rev-parse', 'HEAD']) or '')
    d.setVar('IPMI_AUX13', '0x0')
    if len(aux_hash) >= 6:
        d.setVar('IPMI_AUX14', '0x{}'.format(aux_hash[0:2]))
        d.setVar('IPMI_AUX15', '0x{}'.format(aux_hash[2:4]))
        d.setVar('IPMI_AUX16', '0x{}'.format(aux_hash[4:6]))
}

python do_compile:append() {
    repos = (d.getVar('FLAX_PROVENANCE_REPOS') or '').split()
    lines = flax_provenance_lines(lambda repo, args: flax_git(d, repo, args), repos)
    if not lines:
        return
    with open(d.expand('${B}/os-release'), 'a') as f:
        f.write('\n'.join(lines) + '\n')
}

# The provenance block reads git state at task time, so the recipe must not be
# served from the parse cache.  (Was set by the masked AMI bbappends.)
BB_DONT_CACHE = "1"

# Make os-release available to other recipes.  (Likewise.)
SYSROOT_DIRS:append = " ${sysconfdir}"
