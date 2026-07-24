#!/bin/sh
#
# flax-hi-account.sh - manage the HI-FW Redfish Host Interface firmware account.
#
# The TP26 BIOS authenticates its inventory push (over the USB virtual NIC) as
# the "HI-FW" account using a password it obtains from the BMC over KCS
# (NetFn 0x32 cmd 0x5d).  Our KCS handler (intel-ipmi-oem hostiface_inventory.cpp)
# generates that password and writes it to /run/flax-hi-cred; this script syncs
# it onto the account so bmcweb Basic auth accepts the BIOS.
#
# See docs/redfish-inventory-hi-discovery.md.  POSIX sh (BusyBox) only.
set -e

USER="HI-FW"
CRED="/run/flax-hi-cred"
UM_SVC="xyz.openbmc_project.User.Manager"
UM_OBJ="/xyz/openbmc_project/user"

create() {
    # Idempotent: create the account with Administrator privilege + redfish
    # access so it can reach the OEM inventory upload route.
    if id "${USER}" >/dev/null 2>&1; then
        return 0
    fi
    busctl call "${UM_SVC}" "${UM_OBJ}" "${UM_SVC}" CreateUser sassb \
        "${USER}" 1 redfish priv-admin true || true
}

setpw() {
    [ -f "${CRED}" ] || exit 0
    TOKEN=$(cat "${CRED}")
    [ -n "${TOKEN}" ] || exit 0
    # Ensure the account exists (in case the credential arrives before boot-time
    # creation completed), then set the password.
    create
    echo "${USER}:${TOKEN}" | chpasswd
}

case "$1" in
    create) create ;;
    setpw)  setpw ;;
    *) echo "usage: $0 {create|setpw}" >&2; exit 1 ;;
esac
