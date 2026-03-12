FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# meta-facebook/conf/recipes/fb-consoles.inc sets OBMC_CONSOLE_HOST_TTY = "ttyS2"
# and OBMC_CONSOLE_TTYS = "${@fb_get_consoles(d)}" (direct assignments, not ?=).
# TiogaPass uses VUART for host console: Intel Xeon D PCH emulates COM1 (0x3F8)
# over LPC bus → ASPEED VUART intercepts it → /dev/ttyVUART0 on the BMC.
# Physical UART routing does not work: ASPEED UART1 physical pins are not
# connected to the host PCH UART on the TiogaPass board.
# VUART is configured with SIRQ=0 (patch 0003) to prevent the continuous
# SERIRQ4 TX-empty assertion that caused 30-second host boot stalls.
OBMC_CONSOLE_HOST_TTY:tiogapass = "ttyVUART0"
OBMC_CONSOLE_TTYS:tiogapass = "ttyVUART0"
SYSTEMD_SERVICE:${PN}:tiogapass = "obmc-console@ttyVUART0.service"

SRC_URI:append:tiogapass = " \
    file://obmc-console@.service \
"

do_install:append:tiogapass() {
    # console-id = default so netipmid and bmcweb find the socket at
    # /run/obmc-console/default
    echo "console-id = default" >> ${D}${sysconfdir}/obmc-console/server.ttyVUART0.conf
    echo "console-id = default" >> ${D}${sysconfdir}/obmc-console.conf

    # Mask obmc-console@ttyS2 to prevent socket activation conflict.
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyS2.service
}
