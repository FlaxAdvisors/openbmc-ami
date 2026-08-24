FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# bmcweb logging stays at the upstream default ('error').  Do NOT ship
# -Dbmcweb-logging=debug: it puts four BMCWEB_LOG_DEBUG calls per video frame
# in the KVM read/write handlers, on the io_context thread -- ~60 journald
# writes/second during a console session on a 400MHz ARM11.  That competes with
# the video pipeline for CPU and floods the 4MB volatile journal, so rsyslog
# starts dropping (~900 msgs/min) and the journal retains only minutes of
# history, which is exactly what you need when diagnosing a field problem.
# Re-enable it temporarily on a bench unit only.

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
    file://0017-redfish-render-pciedevice-firmwareversion.patch \
    file://0018-redfish-render-fabricadapter-firmwareversion.patch \
    file://0019-kvm-drop-input-only-idle-timeout.patch \
"
