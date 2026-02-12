# Remove 'settings' from the RDEPENDS of the packagegroup-obmc-apps-extras (or whichever sub-package it's in)
# We use the :remove operator which is the most 'powerful' way to override
RDEPENDS:${PN}-extras:remove = "settings"

# If it's in the main package, use this instead/as well:
RDEPENDS:${PN}:remove = "settings"
