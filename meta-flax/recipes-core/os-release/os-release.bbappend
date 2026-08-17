# Flax-branded version string for TiogaPass builds.
#
# Format (dev):     flax-onetree-<version>-<timestamp>  e.g. flax-onetree-1.0.0-202604011404
# Format (release): flax-onetree-<version>              e.g. flax-onetree-1.0.0
#
# To cut a release build:  set FLAX_RELEASE = "1" in local.conf or on the bitbake command line
# To bump the version:     change FLAX_VERSION below

FLAX_VERSION = "1.1.0"
FLAX_RELEASE ?= "0"

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

# Anonymous python block runs after version-vars.inc's python() block (which is required by
# meta-common and meta-ami bbappends and calls d.setVar() to override regular assignments).
# Our python() runs last because meta-flax has the highest priority and is parsed last.
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
}
