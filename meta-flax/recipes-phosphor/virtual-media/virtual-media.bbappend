FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-fix-inactivity-timer-and-large-iso-cdrom-limit.patch \
"
