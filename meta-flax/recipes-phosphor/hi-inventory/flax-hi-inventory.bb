SUMMARY = "Publish host-interface BIOS inventory on D-Bus"
DESCRIPTION = "Reads the Memory/Processors inventory the TP26 BIOS pushes over \
the Redfish host interface (persisted by bmcweb under /var/lib/flax-inventory) \
and hands it to phosphor-inventory-manager in a single Notify() call, which is \
what makes it appear under Redfish Systems/system/Memory and /Processors. \
Runs as a oneshot on every push and at boot, so inventory survives a BMC \
reboot with the host powered off."
SECTION = "application"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "sdbusplus nlohmann-json"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI = " \
    file://inventory_map.hpp \
    file://inventory_map.cpp \
    file://main.cpp \
    file://flax-hi-inventory.service \
    file://flax-hi-inventory.path \
    file://flax-hi-inventory.conf \
    "

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "flax-hi-inventory.path"
# The service has no [Install] of its own beyond multi-user.target; it is
# packaged and enabled so the boot-time republish happens too.
SYSTEMD_SERVICE:${PN} += "flax-hi-inventory.service"

do_compile() {
    ${CXX} ${CXXFLAGS} ${LDFLAGS} -std=c++20 \
        -o flax-hi-inventory \
        ${WORKDIR}/main.cpp ${WORKDIR}/inventory_map.cpp \
        -lsdbusplus -lsystemd
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 flax-hi-inventory ${D}${bindir}/flax-hi-inventory

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/flax-hi-inventory.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/flax-hi-inventory.path ${D}${systemd_system_unitdir}/

    install -d ${D}${sysconfdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/flax-hi-inventory.conf ${D}${sysconfdir}/tmpfiles.d/
}

FILES:${PN} += "${sysconfdir}/tmpfiles.d/flax-hi-inventory.conf"
