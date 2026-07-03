# TiogaPass has no eMMC device. The stock com.ami.eMMCEnable.service runs
# /usr/bin/enable-emmc.sh, which fails on every boot because there is no eMMC
# to partition/mount. That service is in the phosphor critical-service monitor
# list, so its failure raises a scary
# xyz.openbmc_project.State.Error.CriticalServiceFailure (and a BMC dump) on
# every boot.
#
# emmc-enable is a hard RDEPENDS of packagegroup-onetree-apps, so we keep the
# package but mask the service (symlink the unit to /dev/null in /etc, which
# overrides the copy in /lib) so it never runs, never fails, and never trips
# the critical-service monitor.

do_install:append() {
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/com.ami.eMMCEnable.service
}

FILES:${PN} += "${sysconfdir}/systemd/system/com.ami.eMMCEnable.service"
