SUMMARY = "BMC<->host virtual NIC (USB CDC-ECM gadget) for in-band Redfish/IPMI"
DESCRIPTION = "Presents a USB ethernet gadget to the x86 host over the AST2500 \
vhub so host-resident tooling can reach the BMC's Redfish/IPMI services in-band \
(e.g. firmware update) without the external management LAN."
SECTION = "application"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# shadow -> chpasswd (sync the KCS-issued password onto the HI-FW account)
RDEPENDS:${PN} = "systemd iproute2 shadow"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI = " \
    file://create_usbeth.sh \
    file://host-interface.service \
    file://flax-hi-account.sh \
    file://flax-hi-account.service \
    file://flax-hi-cred.path \
    file://flax-hi-cred.service \
    "

S = "${WORKDIR}"

inherit systemd

# flax-hi-cred.service is triggered by flax-hi-cred.path (no [Install]); it is
# installed but not enabled directly, so package it explicitly.
SYSTEMD_SERVICE:${PN} = "host-interface.service flax-hi-account.service flax-hi-cred.path"
FILES:${PN} += "${systemd_system_unitdir}/flax-hi-cred.service"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/create_usbeth.sh ${D}${bindir}/create_usbeth.sh
    install -m 0755 ${WORKDIR}/flax-hi-account.sh ${D}${bindir}/flax-hi-account.sh
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/host-interface.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/flax-hi-account.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/flax-hi-cred.path ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/flax-hi-cred.service ${D}${systemd_system_unitdir}/
}
