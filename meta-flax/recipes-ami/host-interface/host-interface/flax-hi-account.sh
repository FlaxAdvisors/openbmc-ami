#!/bin/sh
#
# flax-hi-account.sh - manage the Redfish Host Interface firmware accounts.
#
# The TP26 BIOS authenticates its inventory push (over the USB virtual NIC)
# using a password it obtains from the BMC over KCS (NetFn 0x32 cmd 0x5d).  Our
# KCS handler (intel-ipmi-oem hostiface_inventory.cpp) generates that password
# and writes it to /run/flax-hi-cred; this script syncs it onto the account so
# bmcweb Basic auth accepts the BIOS.
#
# The Basic-auth USERNAME the BIOS sends is "HostAutoFW" -- the same string our
# 0x5d response carries.  We originally read that string as a role name and
# created only "HI-FW" (the account name the OEM Lua does use), which made the
# push fail with "User unknown"; proven on hardware 2026-07-31.  Provision both:
# HostAutoFW is the one the BIOS actually authenticates as, HI-FW mirrors the
# OEM and is harmless.  HI-FW needs the phosphor-user-manager hyphen patch.
#
# See docs/redfish-inventory-hi-discovery.md.  POSIX sh (BusyBox) only.
set -e

USERS="HostAutoFW HI-FW"
CRED="/run/flax-hi-cred"
UM_SVC="xyz.openbmc_project.User.Manager"
UM_OBJ="/xyz/openbmc_project/user"

create() {
    # Idempotent: create each account with Administrator privilege + redfish
    # access so it can reach the OEM inventory upload route.
    for u in ${USERS}; do
        if id "${u}" >/dev/null 2>&1; then
            continue
        fi
        busctl call "${UM_SVC}" "${UM_OBJ}" "${UM_SVC}" CreateUser sassb \
            "${u}" 1 redfish priv-admin true || true
    done
}

setpw() {
    [ -f "${CRED}" ] || exit 0
    TOKEN=$(cat "${CRED}")
    [ -n "${TOKEN}" ] || exit 0
    # Ensure the accounts exist (in case the credential arrives before boot-time
    # creation completed), then set the password on each.  Don't let one failing
    # account stop the other -- HostAutoFW is the one the BIOS actually uses.
    create
    for u in ${USERS}; do
        echo "${u}:${TOKEN}" | chpasswd ||
            echo "flax-hi-account: failed to set password for ${u}" >&2
    done
}

case "$1" in
    create) create ;;
    setpw)  setpw ;;
    *) echo "usage: $0 {create|setpw}" >&2; exit 1 ;;
esac
