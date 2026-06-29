FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Override with correct channel config that includes kcs3
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
