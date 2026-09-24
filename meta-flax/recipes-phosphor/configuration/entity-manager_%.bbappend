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
#  0026 - add the Labels allowlist the PCH VR (0x68) is missing; without it
#         psusensor also instantiates the chip's 12 V vin1/vin2 rails, which
#         collide on the same sensor name as vout1/vout2 and win the
#         activate() race on host power-on -> false "Reading 12 > Threshold 1"
#         Upper Critical SEL on MB_VR_PCH_PVNN and MB_VR_PCH_P1V05
#  0027 - give the VR vout sensors a <label>_Max just above their critical
#         threshold; the dbus-sensors default of 255 makes IPMI encode these
#         1 V rails at one volt per count (reporting only - D-Bus threshold
#         detection uses the raw double)
SRC_URI:append = " file://0026-fbtp-add-missing-Labels-allowlist-to-PCH-VR.patch"
SRC_URI:append = " file://0027-fbtp-give-VR-vout-sensors-a-usable-IPMI-range.patch"

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

# fru-device (AMI patch 0002-Add-Config-FRU-Support) reads
# configurations/eeprom.json -- an optional list of EEPROMs to expose even when
# blank, so they can be programmed over IPMI -- once at startup and again for
# every unparseable EEPROM and every empty address of every raw bus scan.  With
# the file absent it behaves as "none configured" but logs "JSON file not found"
# each time: dozens of lines per rescan.  TiogaPass has no blank-FRU EEPROMs to
# expose (AMI's own copy lists PSU FRUs on bus 7 0x50/0x51, which do not exist
# here), so ship an empty list: same behaviour, no noise.  entity-manager also
# loads it as a board config; without a Probe it is dropped silently.
# Deliberately NOT named eeprom.json: meta-ami carries its own eeprom.json and
# sits ahead of meta-flax in FILESPATH (this bbappend uses
# FILESEXTRAPATHS:append), so "file://eeprom.json" silently fetched AMI's copy
# -- two PSU FRUs that do not exist here.  A unique name cannot be shadowed.
SRC_URI:append = " file://flax-eeprom-empty.json"
do_install:append() {
    install -m 0444 ${WORKDIR}/flax-eeprom-empty.json ${D}${datadir}/entity-manager/configurations/eeprom.json
}
