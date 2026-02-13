SUMMARY = "Create default IPMI/web user on first boot"
DESCRIPTION = "Creates required privilege groups and a default admin user \
with IPMI, Redfish, web and SSH access on first boot via D-Bus."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://flax-ipmi-user.service \
    file://flax-ipmi-user.sh \
"

S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "flax-ipmi-user.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# busctl is in dbus, passwd/chpasswd in shadow
RDEPENDS:${PN} = "dbus shadow"

do_install() {
    install -d ${D}${bindir}
    install -m 0700 ${WORKDIR}/flax-ipmi-user.sh \
        ${D}${bindir}/flax-ipmi-user.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/flax-ipmi-user.service \
        ${D}${systemd_system_unitdir}/flax-ipmi-user.service
}

FILES:${PN} += "${systemd_system_unitdir}/flax-ipmi-user.service"
