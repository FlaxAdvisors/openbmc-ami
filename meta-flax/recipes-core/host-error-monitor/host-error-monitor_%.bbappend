FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# TiogaPass CPU fault detection.
#
# Upstream host-error-monitor ships include/error_monitors.hpp as an empty
# stub (no monitors instantiated), so the daemon watches nothing out of the
# box. This patch wires up the IERR (CATERR), ERR2 and CPU/PCH thermal-trip
# monitors using the GPIO line names already present in the TiogaPass DTS.
SRC_URI += " \
    file://0001-tiogapass-enable-cpu-error-monitors.patch \
    file://0002-fix-libpeci-cpu-model-enum-names.patch \
"

# libpeci: on CATERR, IERR monitor reads the CPU MCA banks over PECI and logs
#          which socket failed and the error type (the bad-CPU decode).
# crashdump: intentionally OFF (needs the crashdump service + storage; the
#            IERR/MCA decode alone is enough for fleet triage).
PACKAGECONFIG = "libpeci"
