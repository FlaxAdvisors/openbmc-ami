# meta-flax provides /etc/pam.d/dropbear via libpam_%.bbappend
# Prevent the dropbear recipe from installing its own copy which causes
# a file clash at image assembly time.
 
do_install:append() {
    rm -f ${D}${sysconfdir}/pam.d/dropbear
}
