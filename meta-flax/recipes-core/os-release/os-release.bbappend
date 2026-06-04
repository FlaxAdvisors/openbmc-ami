# Flax-branded version string for TiogaPass builds.
#
# Format (dev):     flax-onetree-<version>-<timestamp>  e.g. flax-onetree-1.0.0-202604011404
# Format (release): flax-onetree-<version>              e.g. flax-onetree-1.0.0
#
# To cut a release build:  set FLAX_RELEASE = "1" in local.conf or on the bitbake command line
# To bump the version:     change FLAX_VERSION below

FLAX_VERSION = "1.0.5"
FLAX_RELEASE ?= "0"

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
