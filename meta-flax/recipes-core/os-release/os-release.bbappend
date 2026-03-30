# Flax-branded version string for TiogaPass builds.
#
# Format (dev):     Flax-OneTree-<version>-<timestamp>  e.g. Flax-OneTree-1.0-202603271523
# Format (release): Flax-OneTree-<version>              e.g. Flax-OneTree-1.0
#
# To cut a release build:  set FLAX_RELEASE = "1" in local.conf or on the bitbake command line
# To bump the version:     change FLAX_VERSION below

FLAX_VERSION = "1.0"
FLAX_RELEASE ?= "0"

# Use BitBake's DATETIME (YYYYMMDDHHmmSS, 14 chars) sliced to minute precision (12 chars).
# DATETIME is in BB_HASHBASE_WHITELIST so it doesn't cause hash non-determinism.
FLAX_TIMESTAMP = "${@d.getVar('DATETIME')[0:12]}"

FLAX_VER_STRING = "${@'Flax-OneTree-' + d.getVar('FLAX_VERSION') + ('' if d.getVar('FLAX_RELEASE') == '1' else '-' + d.getVar('DATETIME')[0:12])}"

OPENBMC_VERSION = "${FLAX_VER_STRING}"
VERSION_ID = "${FLAX_VER_STRING}"
VERSION = "Flax-OneTree-${FLAX_VERSION}"
IPMI_MAJOR = "${@(d.getVar('FLAX_VERSION') or '1.0').split('.')[0]}"
IPMI_MINOR = "${@((d.getVar('FLAX_VERSION') or '1.0').split('.') + ['0'])[1]}"
