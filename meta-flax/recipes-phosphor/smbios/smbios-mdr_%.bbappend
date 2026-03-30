# Enable SMBIOS MDR features needed for Redfish hardware inventory:
#
# cpuinfo        — reads SMBIOS type-4 CPU records, publishes Processors to D-Bus
# smbios-ipmi-blob — IPMI blob handler that receives SMBIOS tables pushed by
#                   host BIOS during POST.  Without this the BMC never receives
#                   the tables regardless of what the BIOS sends.
#
# In this version of smbios-mdr, cpuinfo unconditionally requires libpeci
# (peci_dep = dependency('libpeci') in src/meson.build) regardless of the
# cpuinfo-peci option.  The base recipe's PACKAGECONFIG[cpuinfo] only lists
# i2c-tools — redefine it here to also declare libpeci as a build dep.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

PACKAGECONFIG[cpuinfo] = "-Dcpuinfo=enabled,-Dcpuinfo=disabled,i2c-tools libpeci"

PACKAGECONFIG:append:tiogapass = " cpuinfo smbios-ipmi-blob"

SRC_URI:append:tiogapass = " \
    file://0001-Add-SMBIOS-drive-and-NIC-inventory.patch \
"
