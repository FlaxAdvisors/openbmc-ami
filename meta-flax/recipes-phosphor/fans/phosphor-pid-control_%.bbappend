FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Adds subcommand 3 (setPwmDuty) to the OEM IPMI fan control command this
# recipe already registers at NetFn 0x2E / IANA 49871 / cmd 0x04.  The
# allowlist entry that lets that command through on the LAN channel lives in
# intel-ipmi-oem patch 0007 -- both are needed for the command to work
# remotely.
SRC_URI += "file://0001-oem-ipmi-add-set-pwm-duty-subcommand.patch"
