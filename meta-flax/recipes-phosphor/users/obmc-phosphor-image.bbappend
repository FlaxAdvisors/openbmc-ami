# Add default IPMI/web user setup to the image
IMAGE_INSTALL:append = " phosphor-user-manager-default-admin"
IMAGE_INSTALL:append = " tiogapass-hw-init"
