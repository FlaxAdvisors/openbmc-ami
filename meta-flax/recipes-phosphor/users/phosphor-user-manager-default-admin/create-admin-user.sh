#!/bin/sh
# First-boot script to create required privilege groups and default admin user.
# Runs once only - creates /etc/flax-ipmi-user.done on success.

set -e

NEW_USER="admin"
NEW_PASS="0penBmc1"

log() {
    echo "<6>flax-ipmi-user: $*" > /dev/kmsg || true
}

# ---------------------------------------------------------------------------
# 0. Quit if there's nothing to do
# ---------------------------------------------------------------------------
# Check if admin already exists
if id admin >/dev/null 2>&1; then
    echo "Admin user already exists"
    exit 0
fi

# ---------------------------------------------------------------------------
# 0. Wait for ipmi to be available
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

# Wait a bit for user manager to sync
sleep 10

# ---------------------------------------------------------------------------
# 4. Set the password via passwd (writes /etc/shadow + seeds pam_unix)
# ---------------------------------------------------------------------------
log "Setting password for '${NEW_USER}'..."
echo "${NEW_USER}:${NEW_PASS}" | chpasswd

log "Password set for '${NEW_USER}'."


# ---------------------------------------------------------------------------
# 5. Set ipmi password
# ---------------------------------------------------------------------------
# Set IPMI password
for i in $(seq 1 5); do
    if ipmitool user set password 2 0penBmc1 2>/dev/null; then
        echo "IPMI password set successfully"
        break
    fi
    echo "Attempt $i to set IPMI password failed, retrying..."
    sleep 2
done

# ---------------------------------------------------------------------------
# 5. Set channel access
# ---------------------------------------------------------------------------
# Set channel access
for i in $(seq 1 5); do
    if ipmitool channel setaccess 1 2 link=on ipmi=on callin=on privilege=4 2>/dev/null; then
        echo "Channel access set successfully"
        break
    fi
    echo "Attempt $i to set channel access failed, retrying..."
    sleep 2
done

# ---------------------------------------------------------------------------
# 5. Adn enable
# ---------------------------------------------------------------------------
# Enable user
ipmitool user enable 2 2>/dev/null

echo "Admin user setup complete"
