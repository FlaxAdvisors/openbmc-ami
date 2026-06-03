FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
     file://0001-64-mb-flash-size.patch \
     file://0002-add_uart_3_4_route.patch \
     file://0003-enable-vuart-for-host-console.patch \
     file://0004-enable-peci-for-cpu-temperature.patch \
     file://0005-peci-add-chardev-for-libpeci-ioctl-interface.patch \
     file://0006-i2c-aspeed-silence-smbus-gcall-irq-mismatch.patch \
     file://0007-disable-kcs2-at-0xca8-tiogapass.patch \
     file://0008-disable-mac1-ncsi-tiogapass.patch \
     file://0009-enable-video-engine-for-kvm-tiogapass.patch \
     file://0010-aspeed-video-force-sync-mode-for-kvm-capture.patch \
     file://0011-clk-aspeed-keep-d1clk-crt-running-for-kvm.patch \
     file://0012-enable-usb-vhub-for-kvm-hid-tiogapass.patch \
     file://0013-add-identify-led-tiogapass.patch \
     file://0014-enable-fmc-cs1-bmc-backup.patch \
     file://0015-ncsi-set-perm-addr-from-oem-gma.patch \
     file://0016-ipv6-regen-link-local-on-mac-change.patch \
     file://0017-ncsi-quiet-benign-rsp-validation-and-handler-warnings.patch \
     file://0018-ncsi-mlx-single-port-gma-mac-correction.patch \
     file://tiogapass.cfg \
     file://openbmc-flash-layout-64-tioga.dtsi \
"

do_patch:append() {
    cp ${WORKDIR}/openbmc-flash-layout-64-tioga.dtsi \
       ${S}/arch/arm/boot/dts/aspeed/
}

