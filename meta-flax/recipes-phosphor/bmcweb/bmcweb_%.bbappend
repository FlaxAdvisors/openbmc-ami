FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:tiogapass = " \
    file://0001-redfish-browser-logo-nav-and-caching.patch \
"
