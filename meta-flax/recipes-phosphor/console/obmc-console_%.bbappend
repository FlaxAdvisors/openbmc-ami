FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# TiogaPass host console path (bidirectional SOL via COM1/0x2F8):
#   Host LPC COM1 (0x2F8, BIOS "COM1") -> ASPEED LPC HICRC decode (0x1e789098=0x0A30)
#   -> UART4 = /dev/ttyS3 -> obmc-console
# No UART crossbar: direct LPC hardware decode, no echo feedback loop.
# No BIOS change needed: BIOS outputs to both COM0 (0x3F8) and COM1 (0x2F8) simultaneously.
OBMC_CONSOLE_HOST_TTY:tiogapass = "ttyS3"
OBMC_CONSOLE_TTYS:tiogapass = "ttyS3"
SYSTEMD_SERVICE:${PN}:tiogapass = "obmc-console@ttyS3.service"

SRC_URI:append:tiogapass = " file://sol-configure.sh file://80-uart-routing.rules "

do_install:append:tiogapass() {
    # Install our sol-configure.sh (overrides meta-common version)
    install -m 0755 ${WORKDIR}/sol-configure.sh ${D}${bindir}/sol-configure.sh

    # Write a clean server.ttyS3.conf (baud set at runtime by sol-configure.sh setup).
    # Remove any symlink the upstream recipe may have created before writing our file.
    install -d ${D}${sysconfdir}/obmc-console
    rm -f ${D}${sysconfdir}/obmc-console/server.ttyS3.conf
    printf 'baud = 115200\nconsole-id = default\n' \
        > ${D}${sysconfdir}/obmc-console/server.ttyS3.conf

    # obmc-console.conf: clean top-level config
    printf 'baud = 115200\nconsole-id = default\n' \
        > ${D}${sysconfdir}/obmc-console.conf

    # Install platform udev rule (tags ttyS3 for systemd, removes old crossbar rule)
    install -d ${D}${base_libdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/80-uart-routing.rules \
        ${D}${base_libdir}/udev/rules.d/80-uart-routing.rules

    # Mask unused console instances — only ttyS3 should run
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyS1.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyS2.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyVUART0.service
}

FILES:${PN}:append:tiogapass = " ${base_libdir}/udev/rules.d/80-uart-routing.rules"
