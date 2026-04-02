FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://tiogapass-host-acpi-power-state.yaml"
SETTINGS_HOST_TEMPLATES:append = " tiogapass-host-acpi-power-state.yaml"

# Change default firmware update apply time from OnReset to Immediate.
# The FWUPD_SCRIPT activation path in phosphor-software-manager only calls
# flashWrite() when apply time is Immediate or AtMaintenanceWindowStart;
# OnReset leaves the activation stuck at "Activating" with no progress.
do_install:append() {
    sed -i 's/ApplyTime::RequestedApplyTimes::OnReset/ApplyTime::RequestedApplyTimes::Immediate/' \
        ${D}${settings_datadir}/defaults.yaml
}
