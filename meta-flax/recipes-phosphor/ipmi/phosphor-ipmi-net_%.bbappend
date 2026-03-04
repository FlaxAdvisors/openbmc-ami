FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
            file://0001-fix-sol-updateSOLParameter-catch-sdbusplus-exception.patch \
"
