#!/bin/sh
#
# create_usbeth.sh - present a USB CDC-ECM ethernet gadget to the host OS.
#
# This gives the x86 host an internal "virtual NIC" over the AST2500 USB vhub,
# so host-resident tooling can reach the BMC's Redfish/IPMI services in-band
# (e.g. firmware update) without the external management LAN.
#
# The vhub (device/peripheral controller) and the configfs gadget framework are
# already used by obmc-ikvm's HID gadget.  obmc-ikvm binds its HID gadget
# on-demand to the LOWEST free vhub port (p1 up); to guarantee we never collide
# with it we bind the ethernet gadget to the HIGHEST free port (p5 down).
#
# POSIX sh only (BusyBox ash on the BMC).

set -e

GADGET="/sys/kernel/config/usb_gadget/eth"
VHUB="1e6a0000.usb-vhub"
IFNAME="bmcusb0"           # BMC-side interface name for the gadget
BMC_IP="10.199.199.1"      # BMC side of the point-to-point link (in-band tooling)
PREFIX="30"                # /30 -> host gets 10.199.199.2
DEV_MAC="02:00:00:aa:bb:01"   # BMC (device) side, locally administered
HOST_MAC="02:00:00:aa:bb:02"  # host side

# AMI Redfish Host Interface address the TP26 BIOS pushes inventory to.  The
# BIOS auto-configures a link-local address on its side of the USB link and
# reaches the BMC's Redfish service at this fixed link-local IP (matching the
# OEM BMC, which presents its host interface at 169.254.0.17/16).  We add it as
# a second address on the same gadget so the in-band 10.199.199.x link is
# preserved for our own tooling.  See docs/redfish-inventory-hi-discovery.md.
HI_IP="169.254.0.17"       # Redfish Host Interface (BIOS -> BMC inventory push)
HI_PREFIX="16"             # link-local /16

create_eth() {
    mkdir "${GADGET}"
    cd "${GADGET}"

    echo 0x1d6b > idVendor          # Linux Foundation
    echo 0x0104 > idProduct         # Multifunction Composite Gadget
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB

    mkdir strings/0x409
    echo "OpenBMC"          > strings/0x409/manufacturer
    echo "BMC Virtual NIC"  > strings/0x409/product
    echo "TIOGA0001"        > strings/0x409/serialnumber

    # CDC-ECM function (Linux host -> cdc_ether)
    mkdir functions/ecm.usb0
    echo "${DEV_MAC}"  > functions/ecm.usb0/dev_addr
    echo "${HOST_MAC}" > functions/ecm.usb0/host_addr
    echo "${IFNAME}"   > functions/ecm.usb0/ifname 2>/dev/null || true

    mkdir configs/c.1
    mkdir configs/c.1/strings/0x409
    echo "CDC ECM" > configs/c.1/strings/0x409/configuration
    echo 0xC0 > configs/c.1/bmAttributes    # self-powered
    echo 250  > configs/c.1/MaxPower

    ln -s functions/ecm.usb0 configs/c.1/
}

# Bind the gadget to the highest free vhub UDC port (p5 .. p1).
connect_eth() {
    [ -n "$(cat "${GADGET}/UDC" 2>/dev/null)" ] && return 0

    port=5
    while [ "${port}" -ge 1 ]; do
        udc="${VHUB}:p${port}"
        if [ -e "/sys/class/udc/${udc}" ] &&
           [ ! -e "/sys/bus/platform/devices/${VHUB}/${udc}/gadget/suspended" ] &&
           ! grep -lq "${udc}" /sys/kernel/config/usb_gadget/*/UDC 2>/dev/null; then
            echo "${udc}" > "${GADGET}/UDC"
            return 0
        fi
        port=$((port - 1))
    done

    echo >&2 "create_usbeth: no free vhub UDC port to bind ethernet gadget"
    return 1
}

disconnect_eth() {
    [ -f "${GADGET}/UDC" ] && echo "" > "${GADGET}/UDC" 2>/dev/null || true
}

# Give the BMC side of the link a static IP so bmcweb (listening on all
# interfaces) is reachable from the host.  The netdev appears once the gadget
# is bound; retry briefly.  Fall back to the u_ether default name if the
# ifname write was rejected.
assign_ip() {
    i=0
    while [ "${i}" -lt 10 ]; do
        for dev in "${IFNAME}" usb0; do
            if ip link show "${dev}" >/dev/null 2>&1; then
                ip addr add "${BMC_IP}/${PREFIX}" dev "${dev}" 2>/dev/null || true
                # Redfish Host Interface address the TP26 BIOS pushes to.
                ip addr add "${HI_IP}/${HI_PREFIX}" dev "${dev}" 2>/dev/null || true
                ip link set "${dev}" up
                return 0
            fi
        done
        i=$((i + 1))
        sleep 1
    done
    echo >&2 "create_usbeth: gadget netdev never appeared"
    return 1
}

[ -e "${GADGET}" ] || create_eth

case "$1" in
    connect)
        connect_eth
        assign_ip
        ;;
    disconnect)
        disconnect_eth
        ;;
    *)
        echo >&2 "Usage: $0 {connect|disconnect}"
        exit 1
        ;;
esac
