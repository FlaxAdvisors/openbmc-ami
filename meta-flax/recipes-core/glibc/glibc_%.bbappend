FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://nscd.conf"

do_install:append() {
    install -m 644 ${WORKDIR}/nscd.conf ${D}${sysconfdir}/nscd.conf
}
