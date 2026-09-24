#!/bin/sh
# First-boot account setup.  Runs at every boot but only does work once per
# /etc (a factory reset wipes the marker, so it runs again on the fresh /etc):
#   1. create the privilege groups phosphor-user-manager expects
#   2. remove the old default 'admin' account (earlier images created
#      admin/0penBmc1; that account is no longer shipped)
#   3. enable root (IPMI user 1) for LAN call-in -- root defaults to
#      callin=false, and `ipmitool -I lanplus -U root` fails without it

set -e

DONE_FILE="/etc/flax-accounts.done"
OLD_USER="admin"

log() {
    echo "<6>flax-accounts: $*" > /dev/kmsg || true
}

# ---------------------------------------------------------------------------
# Remove the legacy admin account, even on a box that already ran this script
# (its /etc still holds admin from an older image).
# ---------------------------------------------------------------------------
remove_admin() {
    if ! id "${OLD_USER}" >/dev/null 2>&1; then
        return 0
    fi
    for i in $(seq 1 30); do
        busctl status xyz.openbmc_project.User.Manager >/dev/null 2>&1 && break
        sleep 2
    done
    if busctl call xyz.openbmc_project.User.Manager \
        "/xyz/openbmc_project/user/${OLD_USER}" \
        xyz.openbmc_project.Object.Delete Delete >/dev/null 2>&1; then
        log "Removed legacy user '${OLD_USER}'"
    else
        log "WARNING: could not remove legacy user '${OLD_USER}'"
    fi
}

if [ -e "${DONE_FILE}" ]; then
    remove_admin
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
# 2. Remove the legacy admin account
# ---------------------------------------------------------------------------
remove_admin

# ---------------------------------------------------------------------------
# 3. Enable root (user 1) for LAN call-in
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
