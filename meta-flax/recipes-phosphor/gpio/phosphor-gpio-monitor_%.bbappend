# This prevents the link from being created in the first place
SYSTEMD_SERVICE:${PN}-monitor:remove:tiogapass = "phosphor-multi-gpio-monitor.service"

# Since we're hiding this, remove the artifacts
do_install:append:tiogapass() {
    # Create the directory if it doesn't exist
    install -d ${D}${systemd_system_unitdir}

    # Symlink the service to /dev/null
    # This satisfies the dependency check but runs nothing
    ln -sf /dev/null ${D}${systemd_system_unitdir}/phosphor-multi-gpio-monitor.service
}

# 3. SHIP the file so the QA Issue goes away
# This tells BitBake: "Yes, I know this file is there, please put it in the package."
FILES:${PN}-monitor:append:tiogapass = " ${systemd_system_unitdir}/phosphor-multi-gpio-monitor.service"
