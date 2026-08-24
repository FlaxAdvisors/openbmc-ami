FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-fix-convertIntelVersion-single-digit-major-underflow.patch \
    file://0002-allowlist-add-blob-transfer-cmd.patch \
    file://0003-allowlist-add-dcmi-cmds.patch \
    file://0004-cache-sensor-entity-association-lookups.patch \
    file://0005-devid-fru-manufacturer-product-and-flax-fw-revision.patch \
    file://0006-add-netfn32-hostiface-inventory-bootstrap-handler.patch \
"

# Pull in the runtime FRU -> manufacturer/product cache used by patch 0005.
RDEPENDS:${PN} += "flax-ipmi-devid"
