SUMMARY = "TiogaPass BMC firmware update script"
DESCRIPTION = "Provides /usr/bin/fwupd.sh called by fwupd@.service \
(phosphor-software-manager FWUPD_SCRIPT mode) to flash image-bmc \
to the BMC SPI flash via flashcp."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://fwupd.sh"

S = "${WORKDIR}"

RDEPENDS:${PN} = "mtd-utils bash"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/fwupd.sh ${D}${bindir}/fwupd.sh
}

FILES:${PN} = "${bindir}/fwupd.sh"
