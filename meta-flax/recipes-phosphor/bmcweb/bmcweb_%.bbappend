FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# ── TEMPORARY DIAGNOSTIC — REMOVE BEFORE SHIPPING ────────────────────────────
# Capture the TP26 BIOS's real host-interface request URLs and status codes, to
# find where it POSTs its memory/CPU/PCIe collections (they currently reach no
# route we serve).  Very verbose; do not leave enabled in a release image.
EXTRA_OEMESON:append:tiogapass = " -Dbmcweb-logging=debug"
# ─────────────────────────────────────────────────────────────────────────────

SRC_URI:append:tiogapass = " \
    file://0001-redfish-browser-logo-nav-and-caching.patch \
    file://0002-fix-httpPushUriBusy-reacquisition.patch \
    file://0003-fix-insertmedia-username-param-error-message.patch \
    file://0004-insertmedia-allow-dash-in-path-and-clarify-message.patch \
    file://0005-downgrade-power-and-login-events-to-informational.patch \
    file://0006-make-bmc-reset-audit-event-meaningful.patch \
    file://0007-flax-host-interface-inventory-receive-endpoint.patch \
    file://0008-serviceroot-ami-host-interface-compat.patch \
    file://0009-hostiface-correct-biosstaticfiles-path-and-inventorydata-get.patch \
    file://0012-hostiface-oem-inventorydata-get-and-hi-only-gate.patch \
    file://0013-hostiface-receive-fallback-collection-pushes.patch \
    file://0014-hostiface-touch-inventory-updated-stamp.patch \
    file://0015-hostiface-serve-real-oem-inventorydata-response.patch \
    file://0016-hostiface-store-drives-from-oem-push.patch \
"
