FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

PACKAGECONFIG[sel-delete] = "-Dclears-sel=true,-Dclears-sel=false"
PACKAGECONFIG:append:tiogapass = " log-threshold log-pulse log-watchdog log-alarm log-host sel-delete"

SRC_URI += "file://0001-write-sel-to-both-journal-and-dbus.patch"
