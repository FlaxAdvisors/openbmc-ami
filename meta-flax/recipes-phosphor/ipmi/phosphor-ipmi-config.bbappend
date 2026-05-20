FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Override with correct channel config that includes kcs3
SRC_URI += "file://channel_config.json"

# Enable DCMI power reading: advertise PowerManagement capability and point the
# power-reading sensor at the Hot-Swap-Controller total board input power sensor.
SRC_URI += " \
    file://dcmi_cap.json \
    file://power_reading.json \
"
