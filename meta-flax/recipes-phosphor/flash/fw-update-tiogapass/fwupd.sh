#!/bin/bash
# TiogaPass BMC firmware update script
# Invoked by fwupd@<version>.service (started by phosphor-image-updater in
# FWUPD_SCRIPT mode).  On success, exits 0 → onFlashWriteSuccess() → rebootBmc().
# On failure, exits 1 → onFlashWriteFailure() → activation Failed.
#
# Argument: version-id (the subdirectory under /tmp/images/ holding image-bmc)
#
# image-bmc is the static.mtd image: it starts at flash offset 0 and contains
# u-boot + kernel fitImage (~35MB total).  It must be written to the "bmc" MTD
# device (mtd0, full 64MB chip) so that u-boot lands at the correct offset.
# flashcp only erases/writes blocks up to the image size, so the rwfs partition
# (mtd4) at the end of the chip is preserved.

img_obj="${1}"
IMG="/tmp/images/${img_obj}/image-bmc"

# Find the "bmc" MTD partition by name (the full chip, mtd0).
# The static.mtd image starts at offset 0 and includes u-boot + kernel, so
# it must be written to the full chip device, not just the kernel sub-partition.
# flashcp only erases/writes the blocks covered by the image, so the rwfs
# partition at the end of the chip is preserved.
bmc_mtd=$(grep -rl '^bmc$' /sys/class/mtd/*/name 2>/dev/null | head -n 1)
BMC_DEV="/dev/${bmc_mtd:+$(basename "$(dirname "$bmc_mtd")")}"
BMC_DEV="${BMC_DEV:-/dev/mtd0}"

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

echo "fwupd: writing ${IMG} to ${BMC_DEV}"
update_pct 10

echo "fwupd: flashing bmc (takes ~2 minutes)..."

# Parse flashcp -v progress (Erasing/Writing/Verifying counters) and translate
# to D-Bus ActivationProgress updates so the WebUI bar moves through midpoints
# instead of jumping 10 -> 100. Phases mapped to 10-40 / 40-70 / 70-95.
set -o pipefail
flashcp -v "${IMG}" "${BMC_DEV}" 2>&1 | tr '\r' '\n' | {
    last_pct=10
    phase=
    while IFS= read -r line; do
        case "$line" in
            "Erasing blocks: "*)   phase=erase ;;
            "Writing data: "*)     phase=write ;;
            "Verifying data: "*)   phase=verify ;;
            *) echo "$line"; continue ;;
        esac
        nums="${line#*: }"
        cur="${nums%%/*}";  cur="${cur%k}"
        rest="${nums#*/}";  tot="${rest%% *}";  tot="${tot%k}"
        [ -n "$tot" ] && [ "$tot" -gt 0 ] || continue
        case "$phase" in
            erase)  pct=$((10 + 30 * cur / tot)) ;;
            write)  pct=$((40 + 30 * cur / tot)) ;;
            verify) pct=$((70 + 25 * cur / tot)) ;;
        esac
        if [ "$pct" -gt "$last_pct" ] && [ $((pct - last_pct)) -ge 5 ]; then
            update_pct "$pct"
            last_pct=$pct
        fi
    done
}
RC=${PIPESTATUS[0]}

if [ "${RC}" -ne 0 ]; then
    echo "fwupd: flashcp failed (rc=${RC})"
    exit 1
fi

update_pct 95
echo "fwupd: flash complete — BMC will reboot"
exit 0
