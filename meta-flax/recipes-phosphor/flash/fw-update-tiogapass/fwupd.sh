#!/bin/bash
# TiogaPass BMC firmware update script
# Invoked by fwupd@<version>.service (started by phosphor-image-updater in
# FWUPD_SCRIPT mode).  On success, exits 0 → onFlashWriteSuccess() → rebootBmc().
# On failure, exits 1 → onFlashWriteFailure() → activation Failed.
#
# Argument: version-id (the subdirectory under /tmp/images/ holding image-bmc)
#
# image-bmc is the kernel fitImage (~35MB) and goes to the "kernel" MTD
# partition (mtd3, 40MB), NOT to mtd0 (64MB full chip).  The rwfs UBI
# partition (mtd4) is preserved and does not need to be touched.

img_obj="${1}"
IMG="/tmp/images/${img_obj}/image-bmc"

# Find the "kernel" MTD partition by name
kernel_mtd=$(grep -rl '^kernel$' /sys/class/mtd/*/name 2>/dev/null | head -n 1)
KERNEL_DEV="/dev/${kernel_mtd:+$(basename "$(dirname "$kernel_mtd")")}"
KERNEL_DEV="${KERNEL_DEV:-/dev/mtd3}"

update_pct() {
    busctl set-property xyz.openbmc_project.Software.BMC.Updater \
        /xyz/openbmc_project/software/"${img_obj}" \
        xyz.openbmc_project.Software.ActivationProgress Progress \
        y "$1" 2>/dev/null || true
}

if [ -z "${img_obj}" ]; then
    echo "fwupd: error: no version-id argument"
    exit 1
fi

if [ ! -f "${IMG}" ]; then
    echo "fwupd: error: image not found: ${IMG}"
    exit 1
fi

echo "fwupd: writing ${IMG} to ${KERNEL_DEV}"
update_pct 10

echo "fwupd: flashing kernel partition (takes ~2 minutes)..."
flashcp -v "${IMG}" "${KERNEL_DEV}"
RC=$?

if [ "${RC}" -ne 0 ]; then
    echo "fwupd: flashcp failed (rc=${RC})"
    exit 1
fi

update_pct 95
echo "fwupd: flash complete — BMC will reboot"
exit 0
