# Fix duplicate D-Bus name issue by using wants instead of requires
do_install:append() {
    # Remove the multi-user.target.requires symlinks (they cause duplicate bus name errors)
    rm -f ${D}${systemd_system_unitdir}/multi-user.target.requires/xyz.openbmc_project.State.Host@0.service
    rm -f ${D}${systemd_system_unitdir}/multi-user.target.requires/xyz.openbmc_project.State.Chassis@0.service
    
    # The services will still start via their WantedBy=multi-user.target in the service file
}
