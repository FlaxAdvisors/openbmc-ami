FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:tiogapass = " \
    file://0001-sensors-move-current-value-column-and-add-separator.patch \
    file://0002-nav-remove-radius-and-license.patch \
    file://0003-header-add-flax-logo.patch \
    file://0004-nav-reorder-operations-menu.patch \
    file://0005-firmware-hide-backup-image-cards.patch \
    file://0006-enable-power-restore-policy-page.patch \
    file://0007-eventlog-show-additionaldata-inline.patch \
    file://flax-logo.svg \
"

do_compile:prepend:tiogapass() {
    cp -f ${WORKDIR}/flax-logo.svg ${S}/src/assets/images/flax-logo.svg
}
