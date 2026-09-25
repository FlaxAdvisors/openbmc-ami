#!/bin/sh
# First-boot account setup.  Does its work once per /etc (a factory reset wipes
# the marker, so it runs again on the fresh /etc), and nothing on later boots:
#   1. create the privilege groups phosphor-user-manager expects
#   2. enable root (IPMI user 1) for LAN call-in -- root defaults to
#      callin=false, and `ipmitool -I lanplus -U root` fails without it
# It never creates, modifies or removes any other account.

set -e

DONE_FILE="/etc/flax-accounts.done"

log() {
    echo "<6>flax-accounts: $*" > /dev/kmsg || true
}

if [ -e "${DONE_FILE}" ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# 0. Wait for ipmid
# ---------------------------------------------------------------------------
for i in $(seq 1 30); do
    if systemctl is-active phosphor-ipmi-host >/dev/null 2>&1; then
        # Give it a bit more time to fully initialize
        sleep 3
        break
    fi
    sleep 1
done

# ---------------------------------------------------------------------------
# 1. Create required groups if they don't already exist
# ---------------------------------------------------------------------------
for grp in web redfish ipmi ssh hostconsole priv-admin priv-operator priv-user priv-noaccess; do
    if ! grep -q "^${grp}:" /etc/group; then
        groupadd "${grp}"
        log "Created group: ${grp}"
    fi
done

# ---------------------------------------------------------------------------
# 2. Enable root (user 1) for LAN call-in
# ---------------------------------------------------------------------------
for i in $(seq 1 5); do
    if ipmitool channel setaccess 1 1 callin=on privilege=4 2>/dev/null; then
        log "Root channel access set"
        touch "${DONE_FILE}"
        exit 0
    fi
    sleep 2
done

log "ERROR: could not enable root LAN call-in; will retry next boot"
exit 1
