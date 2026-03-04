FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
     file://0001-64-mb-flash-size.patch \
     file://0002-add_uart_3_4_route.patch \
     file://0003-enable-vuart-for-host-console.patch \
     file://openbmc-flash-layout-64-tioga.dtsi \
"
do_patch:append() {
    cp ${WORKDIR}/openbmc-flash-layout-64-tioga.dtsi \
       ${S}/arch/arm/boot/dts/aspeed/
}

