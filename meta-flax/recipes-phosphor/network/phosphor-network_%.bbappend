FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Hybrid MAC/gateway persistence fix.
#
# persist-mac stays enabled (AMI default via onetree-network-persist-mac-support)
# so the Redfish/IPMI "set MAC" path remains available. This patch then changes
# phosphor-network so it only PERSISTS a MAC the user explicitly set, instead of
# auto-freezing the running NC-SI-derived MAC into 00-bmc-eth0.network. It also
# stops pinning the discovered default gateway as a permanent [Neighbor]. Both
# avoid forcing stale hardware addresses after a mezzanine NIC / gateway change.
SRC_URI:append = " file://0001-persist-mac-only-when-user-set-no-gateway-neigh.patch"
