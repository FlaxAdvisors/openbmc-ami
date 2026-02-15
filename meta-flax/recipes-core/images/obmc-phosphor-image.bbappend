# Re-enable the web UI (excluded by facebook.inc -> phosphor-no-webui.inc)
IMAGE_INSTALL:append = " webui-vue"
IMAGE_FEATURES:append = " obmc-ikvm"
