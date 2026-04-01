FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
            file://0001-fix-sol-updateSOLParameter-catch-sdbusplus-exception.patch \
            file://0002-sol-fix-obmc-console-service-path-match.patch \
"
