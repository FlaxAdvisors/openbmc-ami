FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Override with correct channel config that includes kcs3
SRC_URI += "file://channel_config.json"
