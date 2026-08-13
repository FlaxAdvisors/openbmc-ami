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

# USB identity the TP26 (Wiwynn) BIOS keys on for its Redfish Host Interface.
# Reverse-engineered from the OEM MegaRAC gadget driver (eth.ko / eth-6.5.0.0.0):
# it presents an RNDIS device with idVendor=0x046B (AMI), idProduct=0xFFB0 and
# calls RndisSetVendor(0x046B).  The UEFI BIOS only enumerates/activates an
# *RNDIS* NIC of this identity as its host interface during POST -- a stock
# CDC-ECM gadget (our previous presentation) is ignored by the BIOS and only
# bound by the host OS at boot.  See docs/redfish-inventory-hi-discovery.md.
VID="0x046b"               # AMI (American Megatrends) - must match for BIOS HI
PID="0xffb0"               # AMI virtual ethernet

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

    echo "${VID}" > idVendor
    echo "${PID}" > idProduct
    echo 0x0100   > bcdDevice
    echo 0x0200   > bcdUSB

    # Present a plain, NON-composite CDC device (no IAD), matching the OEM.
    #
    # We previously declared the Microsoft composite class 0xEF/0x02/0x01,
    # which advertises an Interface Association Descriptor.  ep0 tracing during
    # POST (kernel patch 0019) showed the TP26 BIOS reading our 75-byte
    # configuration, re-reading it twice, and then abandoning the host
    # interface without ever sending RNDIS_MSG_INIT.  The OEM gadget module
    # this same BIOS accepts (eth.ko / CreateEthernetDescriptor) emits no IAD
    # at all -- no type-0x0B descriptor anywhere in the module.  Kernel patch
    # 0020 lets us drop ours; the device class must agree with that.
    echo 0x02 > bDeviceClass      # Communications
    echo 0x00 > bDeviceSubClass
    echo 0x00 > bDeviceProtocol

    # Strings verbatim from the OEM gadget module (eth.ko .rodata).  The BIOS
    # fetches string descriptors 1/2/3 immediately before it decides whether to
    # bind, so present exactly what the implementation it accepts presents
    # rather than our own branding.
    mkdir strings/0x409
    echo "American Megatrends Inc." > strings/0x409/manufacturer
    echo "Virtual Ethernet"        > strings/0x409/product
    echo "1234567890"              > strings/0x409/serialnumber

    # RNDIS function -- what the TP26 UEFI BIOS enumerates and binds as its
    # Redfish Host Interface NIC during POST (and the Linux host binds via
    # rndis_host).  A CDC-ECM gadget is ignored by the BIOS; RNDIS is not.
    mkdir functions/rndis.usb0
    echo "${DEV_MAC}"  > functions/rndis.usb0/dev_addr
    echo "${HOST_MAC}" > functions/rndis.usb0/host_addr
    echo "${IFNAME}"   > functions/rndis.usb0/ifname 2>/dev/null || true
    # The rndis function pre-populates os_desc/interface.rndis/compatible_id
    # with "RNDIS"; set it explicitly in case the kernel default differs.
    echo RNDIS   > functions/rndis.usb0/os_desc/interface.rndis/compatible_id 2>/dev/null || true
    echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id 2>/dev/null || true

    # Descriptor class/subclass/protocol: leave at the f_rndis defaults
    # (IAD 02/06/00, control interface 02/02/FF).  We briefly presented the
    # USB-IF RNDIS triple EF/04/01 here on the theory that the UEFI RNDIS
    # driver matches the interface descriptor -- TESTED ON HARDWARE
    # 2026-08-10 AND DISPROVEN: the BIOS behaved identically.  Disassembling
    # the OEM's own gadget module (lib/modules/generic/misc/eth.ko, extracted
    # from the WTPC_P407.ima cramfs) shows it builds a CDC-ACM style function
    # -- Abstract Control Management functional descriptor "04 24 02 00" plus
    # a 0xFF protocol -- i.e. the OEM presents 02/02/FF, exactly what stock
    # f_rndis already gives us.  Kernel patch 0019 keeps the if_* knobs
    # available but we deliberately do not set them.
    #
    # (If you ever do set them: they parse with sscanf("%02hhx") -- BARE
    # two-digit hex.  Writing "0xEF" silently stores 0x00.)

    # Suppress the Interface Association Descriptor (kernel patch 0020) so the
    # configuration we hand the BIOS starts at the control interface, like the
    # OEM's.  Bare two-digit hex -- "00", not "0x00".  The fallback keeps this
    # script working on a kernel without patch 0020.
    echo 00 > functions/rndis.usb0/iad 2>/dev/null || true

    mkdir configs/c.1
    mkdir configs/c.1/strings/0x409
    echo "RNDIS" > configs/c.1/strings/0x409/configuration
    echo 0xC0 > configs/c.1/bmAttributes    # self-powered
    echo 250  > configs/c.1/MaxPower

    ln -s functions/rndis.usb0 configs/c.1/

    # Top-level Microsoft OS descriptor -> makes the host fetch the RNDIS
    # compatible-id above and load its RNDIS driver.
    echo 1       > os_desc/use           2>/dev/null || true
    echo 0xcd    > os_desc/b_vendor_code 2>/dev/null || true
    echo MSFT100 > os_desc/qw_sign       2>/dev/null || true
    ln -s configs/c.1 os_desc/           2>/dev/null || true
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
