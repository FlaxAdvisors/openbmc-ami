FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://0001-Fix-compile-errors.patch"
SRC_URI += "file://0002-Fix-PostComplete-GPIO-polarity-in-initialization.patch"

# TiogaPass: POST_COMPLETE GPIO stays HIGH when BIOS is done (never goes low).
# Upstream default is ActiveLow, but the Facebook TiogaPass BIOS does not
# assert (pull low) this signal after POST.  Override to ActiveHigh so that
# power-control sees GPIO=1 as "asserted" and transitions OperatingSystemState
# from Inactive -> Standby, which unblocks cpuinfo CPU inventory publishing.
SRC_URI:append:tiogapass = " file://power-config-host0.json"

do_install:append:tiogapass() {
    install -m 0644 ${WORKDIR}/power-config-host0.json \
        ${D}/usr/share/x86-power-control/power-config-host0.json
}
