FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Pin the IPMI channel table.  The AMI OneTree copy of this file replaced
# channel 8 ("INTRABMC", medium oem / session-less) with a second "eth0" entry.
# ipmid resolves a request's source channel from the caller's D-Bus name
# (ipmid-new.cpp channelFromMessage); any caller that does not own
# xyz.openbmc_project.Ipmi.Channel.<name> -- notably `ipmitool -I dbus` run on
# the BMC itself -- falls back to getChannelByName("INTRABMC").  With INTRABMC
# missing that lookup throws and every such command is answered 0xD3, which
# ipmitool prints as "... failed: Destination unavailable".  Restored to the
# upstream/Intel/FB convention (channel 8 = INTRABMC); LAN stays on channel 1.
SRC_URI += "file://channel_config.json"

# Override Get Device ID values to match the OEM image:
#   id 32 (0x20), revision 1, manuf_id 40092 (Wiwynn, default), prod_id 7220 (0x1C34)
# manuf_id here is the fallback; flax-ipmi-devid-manuf.service overrides it at
# runtime from the board FRU (Wiwynn vs Quanta).
SRC_URI += "file://dev_id.json"

# Enable DCMI power reading: advertise PowerManagement capability and point the
# power-reading sensor at the Hot-Swap-Controller total board input power sensor.
SRC_URI += " \
    file://dcmi_cap.json \
    file://power_reading.json \
"
