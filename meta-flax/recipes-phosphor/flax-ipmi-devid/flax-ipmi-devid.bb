SUMMARY = "IPMI Get Device ID manufacturer derivation from FRU"
DESCRIPTION = "Boot service that maps the board FRU manufacturer (Wiwynn/Quanta) \
to the IANA enterprise number cached for intel-ipmi-oem's Get Device ID handler."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI = " \
    file://flax-ipmi-devid-manuf.sh \
    file://flax-ipmi-devid-manuf.service \
"

inherit systemd

RDEPENDS:${PN} = "systemd"

SYSTEMD_SERVICE:${PN} = "flax-ipmi-devid-manuf.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/flax-ipmi-devid-manuf.sh \
        ${D}${bindir}/flax-ipmi-devid-manuf.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/flax-ipmi-devid-manuf.service \
        ${D}${systemd_system_unitdir}/flax-ipmi-devid-manuf.service
}

FILES:${PN} = " \
    ${bindir}/flax-ipmi-devid-manuf.sh \
    ${systemd_system_unitdir}/flax-ipmi-devid-manuf.service \
"
