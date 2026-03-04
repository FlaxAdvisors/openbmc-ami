FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

OBMC_CONSOLE_HOST_TTY:tiogapass = "ttyVUART0"
SYSTEMD_SERVICE:${PN}:tiogapass = "obmc-console@ttyVUART0.service"

SRC_URI:append:tiogapass = " file://obmc-console@.service"

do_install:append:tiogapass() {
    # Inject console-id so obmc-console creates the socket at
    # /run/obmc-console/default (where netipmid and bmcweb look)
    echo "console-id = default" >> ${D}${sysconfdir}/obmc-console/server.ttyVUART0.conf
    echo "console-id = default" >> ${D}${sysconfdir}/obmc-console.conf
}
