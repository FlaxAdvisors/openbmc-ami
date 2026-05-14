#!/bin/bash
# Create uploadable firmware update tars for TiogaPass.
#
# Usage:
#   ./make-update-tar.sh                          — build BMC update tar
#   ./make-update-tar.sh bios <bios.bin> [ver]    — build BIOS update tar
#
# BMC output:  build/tiogapass/tmp/deploy/images/tiogapass/tiogapass-bmc-update.tar
# BIOS output: build/tiogapass/tmp/deploy/images/tiogapass/tiogapass-bios-update.tar
#
# ── BMC upload (simple binary POST) ────────────────────────────────────────
#   curl -k -u root:0penBmc -X POST https://<bmc-ip>/redfish/v1/UpdateService \
#        -H "Content-Type: application/octet-stream" \
#        --data-binary @tiogapass-bmc-update.tar
#
# ── BIOS upload (multipart — Targets required by bmcweb) ───────────────────
#   curl -k -u root:0penBmc -X POST https://<bmc-ip>/redfish/v1/UpdateService \
#        -F "UpdateFile=@tiogapass-bios-update.tar;type=application/octet-stream" \
#        -F 'UpdateParameters={"Targets":["/redfish/v1/Managers/bmc"],"@Redfish.OperationApplyTime":"Immediate"};type=application/json'
#
# NOTE: For BIOS the Targets value must be /redfish/v1/Managers/bmc (the only
# target accepted by bmcweb in non-D-Bus update mode).  The actual BIOS flash
# path is triggered by purpose=VersionPurpose.Host in the MANIFEST, not by
# the Targets field.

set -e

DEPLOY_DIR="build/tiogapass/tmp/deploy/images/tiogapass"

# ── BIOS tar ─────────────────────────────────────────────────────────────────
if [ "${1}" = "bios" ]; then
    BIOS_BIN="${2}"
    BIOS_VERSION="${3:-$(date +%Y%m%d%H%M%S)}"

    if [ -z "${BIOS_BIN}" ] || [ ! -f "${BIOS_BIN}" ]; then
        echo "ERROR: Usage: $0 bios <bios.bin> [version]" >&2
        exit 1
    fi

    echo "Image:   ${BIOS_BIN}  ($(du -h "${BIOS_BIN}" | cut -f1))"
    echo "Version: ${BIOS_VERSION}"

    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    # AMI's phosphor-version-software-manager validates filenames against an
    # allowlist (FWImages + OPTIONAL_IMAGES, see meta-ami patch 0009).  The BIOS
    # binary must be named "image-bios" — "bios.bin" gets rejected as "not a
    # valid Firmware file".
    cp "${BIOS_BIN}" "${TMPDIR}/image-bios"

    cat > "${TMPDIR}/MANIFEST" <<EOF
purpose=xyz.openbmc_project.Software.Version.VersionPurpose.Host
version=${BIOS_VERSION}
MachineName=tiogapass
ExtendedVersion=${BIOS_VERSION}
EOF

    OUTPUT="${DEPLOY_DIR}/tiogapass-bios-update.tar"
    mkdir -p "${DEPLOY_DIR}"
    tar -C "$TMPDIR" -cf "$OUTPUT" image-bios MANIFEST

    echo ""
    echo "Done: ${OUTPUT}  ($(du -h "$OUTPUT" | cut -f1))"
    echo ""
    echo "Upload via curl (Redfish multipart — Targets required):"
    echo "  curl -k -u root:0penBmc -X POST https://<bmc-ip>/redfish/v1/UpdateService \\"
    echo "       -F 'UpdateFile=@${OUTPUT};type=application/octet-stream' \\"
    echo "       -F 'UpdateParameters={\"Targets\":[\"/redfish/v1/Managers/bmc\"],\"@Redfish.OperationApplyTime\":\"Immediate\"};type=application/json'"
    exit 0
fi

# ── BMC tar ───────────────────────────────────────────────────────────────────

# Find the most recently built static.mtd
STATIC_MTD=$(ls -t "${DEPLOY_DIR}"/obmc-phosphor-image-tiogapass-*.static.mtd 2>/dev/null | head -1)
if [ -z "$STATIC_MTD" ]; then
    echo "ERROR: No static.mtd found in ${DEPLOY_DIR}. Run bitbake first." >&2
    exit 1
fi

# Extract version from phosphor-image-manifest.json
MANIFEST_JSON="${DEPLOY_DIR}/phosphor-image-manifest.json"
if [ -f "$MANIFEST_JSON" ]; then
    VERSION=$(python3 -c "import json; d=json.load(open('$MANIFEST_JSON')); print(d['info']['version'])")
else
    VERSION=$(basename "$STATIC_MTD" .static.mtd | sed 's/obmc-phosphor-image-tiogapass-//')
fi

echo "Image:   $(basename $STATIC_MTD)  ($(du -h "$STATIC_MTD" | cut -f1))"
echo "Version: $VERSION"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp "$STATIC_MTD" "$TMPDIR/image-bmc"

# MANIFEST read by phosphor-software-manager-updater.
# The image is the full static.mtd (u-boot + kernel from offset 0) and is
# written to /dev/mtd0 (full chip) by fwupd.sh.
# Omit KeyType/HashType — those trigger signature verification which will
# fail without accompanying .sig files in a development build.
cat > "$TMPDIR/MANIFEST" <<EOF
purpose=xyz.openbmc_project.Software.Version.VersionPurpose.BMC
version=${VERSION}
MachineName=tiogapass
ExtendedVersion=${VERSION}
CompatibleName=com.meta.Hardware.BMC.Model.TiogaPass
EOF

OUTPUT="${DEPLOY_DIR}/tiogapass-bmc-update.tar"
tar -C "$TMPDIR" -cf "$OUTPUT" image-bmc MANIFEST

echo ""
echo "Done: ${OUTPUT}  ($(du -h "$OUTPUT" | cut -f1))"
echo ""
echo "Upload via web UI:"
echo "  https://<bmc-ip>  ->  Settings -> Firmware -> Upload BMC image"
echo ""
echo "Upload via curl (Redfish):"
echo "  curl -k -u root:0penBmc -X POST https://<bmc-ip>/redfish/v1/UpdateService \\"
echo "       -H 'Content-Type: application/octet-stream' \\"
echo "       --data-binary @${OUTPUT}"
