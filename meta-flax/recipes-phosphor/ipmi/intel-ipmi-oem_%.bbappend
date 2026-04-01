FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-fix-convertIntelVersion-single-digit-major-underflow.patch \
"
