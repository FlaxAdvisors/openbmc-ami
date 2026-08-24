FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Allow the hyphenated "HI-FW" Redfish Host Interface firmware account to be
# created. The TP26 BIOS authenticates its inventory push as user "HI-FW", but
# AMI patch 0025 set the username regex to forbid hyphens. See
# 0001-allow-hyphen-in-usernames-for-HI-FW-host-interface.patch.
SRC_URI:append:tiogapass = " \
    file://0001-allow-hyphen-in-usernames-for-HI-FW-host-interface.patch \
"
