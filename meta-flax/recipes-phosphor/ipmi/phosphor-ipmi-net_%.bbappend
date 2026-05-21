FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
            file://0001-fix-sol-updateSOLParameter-catch-sdbusplus-exception.patch \
            file://0002-sol-fix-obmc-console-service-path-match.patch \
            file://0003-guid-cache-machine-id-fallback-for-rakp.patch \
"

# Disable per-RAKP PAM authentication (AMI OneTree CheckLockStatus feature).
# It runs a full synchronous pam_authenticate() (SHA512 crypt + shadow read +
# faillock) in netipmid's single event-loop thread on EVERY session setup
# (rakp12.cpp, #ifdef PAM_AUTHENTICATE). On the single-core AST2500 this stalls
# RAKP message 2/4 responses under IPMI polling load -> "no response from RAKP
# 1/3" / dropped sessions. RAKP still authenticates via its HMAC; only the IPMI
# account-lockout-after-failed-attempts feature is lost. TODO: revisit as a
# runtime toggle (off for provisioning, on for deployment).
PACKAGECONFIG:remove = "pam-authenticate"
