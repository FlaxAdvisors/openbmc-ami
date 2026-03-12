# TiogaPass (AST2500) only has KCS3 — no KCS4 hardware.
# meta-common unconditionally appends kcs4 via :append which runs after any =
# assignment regardless of layer priority. Use :remove (runs after all appends)
# to strip kcs4 back out.
SYSTEMD_SERVICE:${PN}:remove = "${PN}@${SMM_DEVICE}.service"
