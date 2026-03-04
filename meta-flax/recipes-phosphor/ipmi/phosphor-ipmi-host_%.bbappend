#FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/phosphor-ipmi-host:"
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Use D-Bus-based SDR handler instead of empty YAML sensor table
PACKAGECONFIG:append = " dynamic-sensors"

SRC_URI += " \
            file://0001-fix-bios-object-crash.patch \
            file://0002-fix-settings-map-crash.patch \
            file://0003-fix-chassis-power-restore-crash.patch \
            file://0004-fix-allowlist-empty-restricted-mode.patch \
            file://0005-fix-sdr-empty-sensor-table-crash.patch \
"
