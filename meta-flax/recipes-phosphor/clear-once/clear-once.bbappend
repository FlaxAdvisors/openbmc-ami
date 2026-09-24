FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Make clear-once actually run.  Upstream never enables it directly: it is
# pulled in by phosphor-ipmi-host.service (Wants=/After=clear-once.service).
# AMI replaces that unit with phosphor-ipmi-host-ami.service, which dropped the
# Wants=, so on this image clear-once.service is installed but static and never
# starts.  Then nothing clears the U-Boot one-shot key openbmconce: after a
# factory reset (openbmconce=factory-reset) the initramfs reformats the rwfs
# volume on EVERY subsequent boot, not just the next one.
#
# Our copy of the unit adds [Install] WantedBy=multi-user.target -- the
# obmc-phosphor-systemd preset already says "enable clear-once.service", it was
# only a no-op because the unit had nothing to install -- and skips the flash
# write when no key is set.  It is deliberately NOT ordered before ipmid the
# way upstream does it: clearing the key rewrites the U-Boot environment
# (seconds), and delaying ipmid at boot widens the host FRU-read race.
