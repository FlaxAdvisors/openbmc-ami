#!/bin/sh
# First-boot account setup.  Does its work once per /etc (a factory reset wipes
# the marker, so it runs again on the fresh /etc), and nothing on later boots:
#   1. create the privilege groups phosphor-user-manager expects
#   2. remove the legacy 'admin' account that older images created, but ONLY
#      if it is still exactly that account -- password 0penBmc1, never changed.
#      An 'admin' anyone created or re-passworded is a real user and is left
#      alone.
#   3. enable root (IPMI user 1) for LAN call-in -- root defaults to
#      callin=false, and `ipmitool -I lanplus -U root` fails without it

set -e

DONE_FILE="/etc/flax-accounts.done"
LEGACY_USER="admin"
LEGACY_PASS="0penBmc1"

log() {
    echo "<6>flax-accounts: $*" > /dev/kmsg || true
}

if [ -e "${DONE_FILE}" ]; then
    exit 0
fi

# True only when LEGACY_USER exists and its shadow hash is LEGACY_PASS.
is_untouched_legacy_admin() {
    hash=$(grep "^${LEGACY_USER}:" /etc/shadow 2>/dev/null | cut -d: -f2)
    case "${hash}" in
        \$*\$*\$*) ;;
        *) return 1 ;;
    esac
    type=$(echo "${hash}" | cut -d'$' -f2)
    salt=$(echo "${hash}" | cut -d'$' -f3)
    [ "$(openssl passwd "-${type}" -salt "${salt}" "${LEGACY_PASS}" 2>/dev/null)" = "${hash}" ]
}

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
# 2. Remove the legacy admin account, if it is untouched
# ---------------------------------------------------------------------------
if is_untouched_legacy_admin; then
    for i in $(seq 1 30); do
        busctl status xyz.openbmc_project.User.Manager >/dev/null 2>&1 && break
        sleep 2
    done
    if busctl call xyz.openbmc_project.User.Manager \
        "/xyz/openbmc_project/user/${LEGACY_USER}" \
        xyz.openbmc_project.Object.Delete Delete >/dev/null 2>&1; then
        log "Removed legacy user '${LEGACY_USER}' (default password, never changed)"
    else
        log "WARNING: could not remove legacy user '${LEGACY_USER}'"
    fi
elif id "${LEGACY_USER}" >/dev/null 2>&1; then
    log "Keeping user '${LEGACY_USER}': not the untouched legacy account"
fi

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
