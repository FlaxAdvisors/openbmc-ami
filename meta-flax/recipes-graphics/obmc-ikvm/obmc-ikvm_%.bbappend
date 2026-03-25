FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://start-ipkvm.service \
    file://0001-fix-kvm-always-use-v4l2-getframe-remove-dim-reset.patch \
    file://0002-fix-kvm-remove-blocking-dbus-and-deferred-resize.patch \
"

do_install:append() {
    install -m 0644 ${WORKDIR}/start-ipkvm.service ${D}${systemd_system_unitdir}/start-ipkvm.service
}
