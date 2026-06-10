FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:tiogapass = " \
    file://0001-redfish-browser-logo-nav-and-caching.patch \
    file://0002-fix-httpPushUriBusy-reacquisition.patch \
    file://0003-fix-insertmedia-username-param-error-message.patch \
    file://0004-insertmedia-allow-dash-in-path-and-clarify-message.patch \
    file://0005-downgrade-power-and-login-events-to-informational.patch \
    file://0006-make-bmc-reset-audit-event-meaningful.patch \
"
