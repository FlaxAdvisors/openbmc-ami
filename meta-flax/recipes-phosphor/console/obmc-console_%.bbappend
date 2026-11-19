FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# TiogaPass host console on BIOS COM0 (0x3F8), shared by two endpoints, both full-duplex:
#   1. SOL (network / ipmitool) via obmc-console on /dev/ttyS3 (UART4), bridged to COM0
#      through the ASPEED crossbar (uart4<-uart1 out, uart1<-uart4 in).
#   2. The physical 14-pin debug-card header (wired to UART1's pins): it hears COM0 via
#      io1=uart1 (TXD1), and its keystrokes are tapped on UART3/ttyS2 (crossbar uart3=io1,
#      RXD1 pin) and merged into COM0 by obmc-console-dbgcard-bridge.service (ttyS2->ttyS3).
# See sol-configure.sh for the full routing map. SOL and the debug card coexist with no
# contention (TXD1/RXD1 are separate pins); HW-validated on .245 2026-10-30.
OBMC_CONSOLE_HOST_TTY:tiogapass = "ttyS3"
OBMC_CONSOLE_TTYS:tiogapass = "ttyS3"
SYSTEMD_SERVICE:${PN}:tiogapass = "obmc-console@ttyS3.service obmc-console-dbgcard-bridge.service"

SRC_URI:append:tiogapass = " file://sol-configure.sh file://80-uart-routing.rules file://obmc-console-dbgcard-bridge.service "

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

    # Install the debug-card input bridge service (card keystrokes -> COM0).
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/obmc-console-dbgcard-bridge.service \
        ${D}${systemd_system_unitdir}/obmc-console-dbgcard-bridge.service

    # Mask unused console instances — only ttyS3 should run
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyS1.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyS2.service
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/obmc-console@ttyVUART0.service
}

FILES:${PN}:append:tiogapass = " ${base_libdir}/udev/rules.d/80-uart-routing.rules ${systemd_system_unitdir}/obmc-console-dbgcard-bridge.service"
