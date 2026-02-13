#!/bin/sh
# First-boot script to create required privilege groups and default admin user.
# Runs once only - creates /etc/flax-ipmi-user.done on success.

set -e

NEW_USER="admin"
NEW_PASS="0penBmc1"
DONE_FILE="/etc/flax-ipmi-user.done"

log() {
    echo "<6>flax-ipmi-user: $*" > /dev/kmsg || true
}

# ---------------------------------------------------------------------------
# 1. Create required groups if they don't already exist
# ---------------------------------------------------------------------------
for grp in web redfish ipmi ssh hostconsole priv-admin priv-operator priv-user priv-noaccess; do
    if ! grep -q "^${grp}:" /etc/group; then
        groupadd "${grp}"
        log "Created group: ${grp}"
    else
        log "Group already exists: ${grp}"
    fi
done

# ---------------------------------------------------------------------------
# 2. Wait for phosphor-user-manager to appear on D-Bus
# ---------------------------------------------------------------------------
log "Waiting for phosphor-user-manager on D-Bus..."
for i in $(seq 1 30); do
    if busctl status xyz.openbmc_project.User.Manager > /dev/null 2>&1; then
        log "phosphor-user-manager is ready."
        break
    fi
    if [ "${i}" -eq 30 ]; then
        log "ERROR: phosphor-user-manager did not appear on D-Bus after 60s"
        exit 1
    fi
    sleep 2
done

# ---------------------------------------------------------------------------
# 3. Create the user via D-Bus (skips if already exists)
# ---------------------------------------------------------------------------
if busctl tree xyz.openbmc_project.User.Manager 2>/dev/null | grep -q "/xyz/openbmc_project/user/${NEW_USER}"; then
    log "User '${NEW_USER}' already exists, skipping CreateUser."
else
    log "Creating user '${NEW_USER}'..."
    busctl call \
        xyz.openbmc_project.User.Manager \
        /xyz/openbmc_project/user \
        xyz.openbmc_project.User.Manager \
        CreateUser \
        "sassb" \
        "${NEW_USER}" \
        4 "web" "ipmi" "redfish" "ssh" \
        "priv-admin" \
        true
    log "User '${NEW_USER}' created."
fi

# ---------------------------------------------------------------------------
# 4. Set the password via passwd (writes /etc/shadow + seeds pam_unix)
# ---------------------------------------------------------------------------
log "Setting password for '${NEW_USER}'..."
echo "${NEW_USER}:${NEW_PASS}" | chpasswd

log "Password set for '${NEW_USER}'."

# ---------------------------------------------------------------------------
# 5. Mark done so this service never runs again
# ---------------------------------------------------------------------------
touch "${DONE_FILE}"
log "Done. First-boot user setup complete."
