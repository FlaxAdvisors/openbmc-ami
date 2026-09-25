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

# 0001 stops NEW automatic MACs being saved, but a MAC saved by older firmware
# (or an earlier NIC) survives firmware updates in the /etc overlay and kept
# overriding the card. 0002 never re-applies a saved MAC: it drops it from the
# config at startup, so the NIC's own NC-SI MAC is always the one in use.
SRC_URI:append = " file://0002-never-reapply-saved-mac-nic-mac-is-authoritative.patch"
