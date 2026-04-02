FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:tiogapass = " \
    file://0001-sensors-move-current-value-column-and-add-separator.patch \
"
