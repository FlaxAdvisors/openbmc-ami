FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://tiogapass.cfg"
SRC_URI += "file://0001-tiogapass-enable-superio-uart1-lpc-decode.patch"
SRC_URI += "file://0002-tiogapass-enable-pcie-vga-mmio-for-kvm.patch"
