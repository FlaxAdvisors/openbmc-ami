SUMMARY = "TiogaPass hardware initialization service"
DESCRIPTION = "Sets up LPC port 80h redirect for debug card post code display"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI = " \
    file://tiogapass-hw-init.sh \
    file://tiogapass-hw-init.service \
    file://tiogapass-clear-vr-faults.service \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tiogapass-hw-init.service tiogapass-clear-vr-faults.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/tiogapass-hw-init.sh ${D}${bindir}/tiogapass-hw-init.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/tiogapass-hw-init.service \
        ${D}${systemd_system_unitdir}/tiogapass-hw-init.service
    install -m 0644 ${WORKDIR}/tiogapass-clear-vr-faults.service \
        ${D}${systemd_system_unitdir}/tiogapass-clear-vr-faults.service
}

FILES:${PN} = " \
    ${bindir}/tiogapass-hw-init.sh \
    ${systemd_system_unitdir}/tiogapass-hw-init.service \
    ${systemd_system_unitdir}/tiogapass-clear-vr-faults.service \
"
