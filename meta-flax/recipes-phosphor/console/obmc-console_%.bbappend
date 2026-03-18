FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# TiogaPass host console path:
#   Host LPC COM1 (0x3F8) -> ASPEED SuperIO (enabled by CONFIG_ASPEED_ENABLE_SUPERIO)
#   -> uart1 TX path -> uart_routing: uart2 input = uart1
#   -> UART2 = /dev/ttyS1 -> obmc-console
# SuperIO is enabled by keeping HW_STRAP1 bit 20 clear in U-Boot (via
# CONFIG_ASPEED_ENABLE_SUPERIO=y in tiogapass.cfg).
OBMC_CONSOLE_HOST_TTY:tiogapass = "ttyS1"
OBMC_CONSOLE_TTYS:tiogapass = "ttyS1"
SYSTEMD_SERVICE:${PN}:tiogapass = "obmc-console@ttyS1.service"

SRC_URI:append:tiogapass = " file://sol-configure.sh "

do_install:append:tiogapass() {
    # Install our sol-configure.sh (overrides meta-common version)
    install -m 0755 ${WORKDIR}/sol-configure.sh ${D}${bindir}/sol-configure.sh

    # Write a clean server.ttyS1.conf (baud set at runtime by sol-configure.sh setup)
    printf 'baud = 115200\nconsole-id = default\n' \
        > ${D}${sysconfdir}/obmc-console/server.ttyS1.conf

    # obmc-console.conf: clean top-level config
    printf 'baud = 115200\nconsole-id = default\n' \
        > ${D}${sysconfdir}/obmc-console.conf

    # Mask ttyS2 and ttyVUART0 — only ttyS1 should run
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyS2.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyVUART0.service
}
