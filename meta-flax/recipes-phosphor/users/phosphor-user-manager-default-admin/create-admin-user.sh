#!/bin/sh

# Wait for IPMI host service to be fully ready
for i in $(seq 1 30); do
    if systemctl is-active phosphor-ipmi-host >/dev/null 2>&1; then
        # Give it a bit more time to fully initialize
        sleep 3
        break
    fi
    sleep 1
done

# Check if admin already exists
if id admin >/dev/null 2>&1; then
    echo "Admin user already exists"
    exit 0
fi

# Create privilege groups if missing (groups should already exist from phosphor-user-manager)
for group in priv-admin priv-operator priv-user; do
    grep -q "^${group}:" /etc/group || groupadd $group
done

# Create admin user
useradd -m -G priv-admin,ipmi,redfish,web admin
echo "admin:0penBmc1" | chpasswd

# Wait a bit for user manager to sync
sleep 2

# Set IPMI user - try a few times in case service isn't quite ready
for i in $(seq 1 5); do
    if ipmitool user set name 2 admin 2>/dev/null; then
        echo "IPMI user name set successfully"
        break
    fi
    echo "Attempt $i to set IPMI user name failed, retrying..."
    sleep 2
done

# Set IPMI password
for i in $(seq 1 5); do
    if ipmitool user set password 2 0penBmc1 2>/dev/null; then
        echo "IPMI password set successfully"
        break
    fi
    echo "Attempt $i to set IPMI password failed, retrying..."
    sleep 2
done

# Set channel access
for i in $(seq 1 5); do
    if ipmitool channel setaccess 1 2 link=on ipmi=on callin=on privilege=4 2>/dev/null; then
        echo "Channel access set successfully"
        break
    fi
    echo "Attempt $i to set channel access failed, retrying..."
    sleep 2
done

# Enable user
ipmitool user enable 2 2>/dev/null

echo "Admin user setup complete"
