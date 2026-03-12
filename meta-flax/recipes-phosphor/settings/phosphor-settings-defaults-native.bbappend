FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://tiogapass-host-acpi-power-state.yaml"
SETTINGS_HOST_TEMPLATES:append = " tiogapass-host-acpi-power-state.yaml"
