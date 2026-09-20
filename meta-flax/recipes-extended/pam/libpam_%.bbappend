FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://dropbear"

# pam.d/common-password is NOT listed in SRC_URI on purpose.
#
# Both poky's libpam recipe and meta-phosphor's bbappend already fetch
# "file://pam.d/common-password"; what decides which copy of that file lands in
# the image is FILESPATH order, not SRC_URI.  meta-ami/meta-common carries a
# byte-for-byte copy of poky's *stock* common-password (pam_unix only) and does
# a FILESEXTRAPATHS:prepend, which puts it ahead of meta-phosphor -- so the
# OpenBMC stack with pam_ipmicheck/pam_ipmisave was silently being shadowed and
# the shipped file had no IPMI modules at all.  pam_ipmisave.so was built and
# installed under /lib/security, just never invoked, so IPMI password changes
# never reached /etc/ipmi_pass.
#
# meta-flax sits ahead of meta-ami in FILESPATH, so dropping meta-phosphor's
# file here restores it.  The copy is kept byte-identical to
# meta-phosphor/recipes-extended/pam/libpam/pam.d/common-password so it stays
# trivially diffable against upstream; if meta-ami ever stops shipping its
# stock copy, this whole file can go away.

do_install:append() {
    install -d ${D}${sysconfdir}/pam.d
    install -m 0644 ${WORKDIR}/dropbear ${D}${sysconfdir}/pam.d/dropbear
}
