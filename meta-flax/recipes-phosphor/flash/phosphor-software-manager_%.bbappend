FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Enable host BIOS upgrade support (adds obmc-flash-host-bios@.service and
# compiles in the HOST_BIOS_UPGRADE activation path in phosphor-software-manager).
PACKAGECONFIG:append = " flash_bios"

SRC_URI += " \
    file://0001-fix-bios-activation-in-fwupd-script-mode.patch \
    file://0010-untar-failure-informational-not-error.patch \
    file://bios-update \
    file://backup-bmc-flash \
    file://obmc-flash-host-bios@.service \
"

RDEPENDS:${PN}-updater += "bash mtd-utils"

do_install:append() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/bios-update ${D}${sbindir}/bios-update
    install -m 0755 ${WORKDIR}/backup-bmc-flash ${D}${sbindir}/backup-bmc-flash

    # Replace the upstream placeholder service with our real implementation.
    install -m 0644 ${WORKDIR}/obmc-flash-host-bios@.service \
        ${D}${systemd_unitdir}/system/obmc-flash-host-bios@.service
}

FILES:${PN}-updater += " \
    ${sbindir}/bios-update \
    ${sbindir}/backup-bmc-flash \
    ${systemd_unitdir}/system/obmc-flash-host-bios@.service \
"
