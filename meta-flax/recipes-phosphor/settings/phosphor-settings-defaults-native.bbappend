FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://tiogapass-host-acpi-power-state.yaml"
SETTINGS_HOST_TEMPLATES:append = " tiogapass-host-acpi-power-state.yaml"

# Register /xyz/openbmc_project/control/security/restriction_mode so
# intel-ipmi-oem's allowlist-filter.cpp finds it via ObjectMapper. The
# filter hardcodes this path; without an owner it logs "Could not
# initialize provisioning mode, defaulting to restricted" and blocks
# Chassis Control on the system interface (channel-mask 0x7f7f in
# ipmi-allowlist.conf excludes channel 15 = KCS). Default Modes::None
# maps to Allow-All in the filter's switch.
SRC_URI:append = " file://tiogapass-restriction-mode.yaml"
SETTINGS_BMC_TEMPLATES:append = " tiogapass-restriction-mode.yaml"

# Change default firmware update apply time from OnReset to Immediate.
# The FWUPD_SCRIPT activation path in phosphor-software-manager only calls
# flashWrite() when apply time is Immediate or AtMaintenanceWindowStart;
# OnReset leaves the activation stuck at "Activating" with no progress.
do_install:append() {
    sed -i 's/ApplyTime::RequestedApplyTimes::OnReset/ApplyTime::RequestedApplyTimes::Immediate/' \
        ${D}${settings_datadir}/defaults.yaml
}
