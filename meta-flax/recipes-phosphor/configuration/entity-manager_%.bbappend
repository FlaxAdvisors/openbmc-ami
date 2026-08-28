FILESEXTRAPATHS:append := ":${THISDIR}/${PN}:"

#SRC_URI:append = " file://WC-Baseboard.json \
#                   file://WP-Baseboard.json \
#                   file://FCXXPDBASSMBL_PDB.json \
#                   file://OPB2RH-Chassis.json \
#                   file://CYP-baseboard.json \
#                   file://FBTP-Zone.json \
#                   file://MIDPLANE-2U2X12SWITCH.json"

SRC_URI:append = " file://SensorBoard.json"
SRC_URI:append = " file://SensorSBFan.json"
SRC_URI:append = " file://TNP-baseboard.json"
SRC_URI:append = " file://0017-Add-tiogapass-configs-to-meson.patch"
# fbtp.json fixes (exported from the devtool workspace):
#  0018 - drop nonexistent MEZZ TMP421 sensor + fan PID entry
#  0019 - convert HSC sensors to native PMBus (+ reindent)
#  0020 - gate CPU/PCH VR voltage sensors on host PowerState (no SEL spam when host off)
#  0021 - gate main (P3V3/P5V/P12V ADC) + INA230 12V rails on host PowerState
#  0022 - raise fan TACH upper non-critical threshold 8500 -> 9500 RPM (quiet flapping)
#  0023 - add 2C stepwise hysteresis; idle fans oscillated 35%<->70% because
#         MB_INLET_REMOTE_TEMP dithers on the 40C step boundary with no hysteresis
#  0024 - match the OEM's other two damping mechanisms: failsafe 100->60% and
#         fan-channel slew limits (its CfgPwm 0x3C and RampRate 0x14)
# (Board-level Decorator.Ipmi was dropped: entity-manager's global.json schema
#  sets additionalProperties:false on boards and does not permit Decorator.Ipmi,
#  so EM strips it. The ipmid SDR CPU storm is fixed by the intel-ipmi-oem
#  per-path association cache (0004) instead.)
SRC_URI:append = " file://0018-fbtp-remove-nonexistent-MEZZ-TMP421-sensor-and-fan-P.patch"
SRC_URI:append = " file://0019-fbtp-convert-HSC-sensors-to-native-PMBus-reindent.patch"
SRC_URI:append = " file://0020-fbtp-gate-VR-voltage-sensors-on-host-power-state.patch"
SRC_URI:append = " file://0021-fbtp-gate-main-and-INA230-rails-on-host-power-state.patch"
SRC_URI:append = " file://0022-fbtp-raise-fan-tach-upper-noncritical-to-9500.patch"
SRC_URI:append = " file://0023-fbtp-add-stepwise-hysteresis-to-stop-fan-oscillation.patch"
SRC_URI:append = " file://0024-fbtp-match-oem-failsafe-and-ramp-rate.patch"
#  0025 - tag the baseboard as Inventory.Item.System so bmcweb populates
#         Systems/system Manufacturer/Model/Serial/PartNumber AND BiosVersion
#         (all of which were null together because no Item.System existed)
SRC_URI:append = " file://0025-fbtp-add-Inventory-Item-System-to-baseboard.patch"

#RDEPENDS_${PN} += "default-fru"

#SRC_URI:append = " file://0001-updated-configuration-sensors-units.patch"
#SRC_URI:append = " file://0002-Unuse-hw-disable-json.patch"
#SRC_URI:append = " file://0003-Frontpanel-riser-tempsenorjson.patch"
#SRC_URI:append = " file://0004-Psu-Threshold.patch"
#SRC_URI:append = " file://0005-digital-sensor.patch"
#SRC_URI:append = " file://0006-Inventory-disable.patch"
#SRC_URI:append = " file://0007-Updated-Flextronic-configuration.patch"
#SRC_URI:append = " file://0008-Added-SdrInfo.patch"
#SRC_URI:append = " file://0009-SEL-sensor.patch"
#SRC_URI:append = " file://0010-Intrusion-Sensor-json.patch"
#SRC_URI:append = " file://0011-SELandACPI-sensor.patch"
#SRC_URI:append = " file://0012-memoryand-hdd-sensor.patch"
#SRC_URI:append = " file://0015-Updated-Tiogapass-Configuration.patch"
#SRC_URI:append = " file://0016-FBTP-cpusensor-sdrinfo.patch"
#Intel patch
#SRC_URI:append += " file://0013-Add-retries-to-mapper-calls.patch"
#SRC_URI:append += " file://0014-Improve-initialization-of-I2C-sensors.patch"

# Copy custom JSON files into the source tree before meson configure so they
# are present when meson processes the install_data() entries added by the patch.
do_configure:prepend() {
    for json in SensorBoard.json SensorSBFan.json TNP-baseboard.json; do
        install -m 0444 ${WORKDIR}/${json} ${S}/configurations/
    done
}
