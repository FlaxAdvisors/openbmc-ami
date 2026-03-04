SUMMARY = "Create default admin IPMI user"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

inherit allarch systemd

RDEPENDS:${PN} = "phosphor-user-manager"

SRC_URI = "file://create-admin-user.sh \
          file://create-admin-user.service \
"


SYSTEMD_SERVICE:${PN} = "create-admin-user.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/create-admin-user.sh ${D}${sbindir}/create-admin-user.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/create-admin-user.service ${D}${systemd_system_unitdir}/create-admin-user.service
}

FILES:${PN} = "${sbindir}/create-admin-user.sh"

