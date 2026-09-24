SUMMARY = "Flax-CA-signed TLS leaf for the BIOS Redfish Host Interface"
DESCRIPTION = "\
Installs bmcweb's TLS server certificate into the read-only rootfs so it \
survives a factory reset. \
\
The TP26 BIOS validates the BMC's TLS chain against the flax-ca anchor baked \
into its trust store, and drops the connection with a bare TCP RST -- no TLS \
alert -- if the chain does not verify. bmcweb writes a self-signed CN=testhost \
certificate whenever /etc/ssl/certs/https/server.pem is missing, which the \
BIOS rejects, so host-interface inventory (CPUs, DIMMs, PCIe) silently stops. \
\
Before this recipe the certificate existed only in the /etc overlay's upper \
layer on the read-write UBI volume. A factory reset runs ubiformat on that \
volume, so the certificate went away and inventory broke with no obvious \
error pointing at TLS. Shipping it in the rootfs puts it in the overlay's \
lower layer, where the reset cannot reach it. \
"

LICENSE = "CLOSED"

inherit allarch

# server.pem holds the BMC's TLS PRIVATE key, so it is deliberately kept out of
# this repository, which is public. It is minted outside the tree by
# tools/hi-cert/mint-hi-cert.sh in the (private) openbmc-ami-tools repo:
#
#   CA_CERT=/vagrant/bios-ca-swap/flax-ca.pem \
#   CA_KEY=/vagrant/bios-ca-swap/flax-ca-key.pem \
#   ./mint-hi-cert.sh --no-install --out /vagrant/bios-ca-swap/hi-cert-build
#
# Override FLAX_HI_CERT_PEM in local.conf to point somewhere else.
FLAX_HI_CERT_PEM ?= "/vagrant/bios-ca-swap/hi-cert-build/server.pem"

# The file lives outside any layer, so bitbake cannot see it change on its own.
# ':False' keeps a build without the key material working rather than failing.
do_install[file-checksums] += "${FLAX_HI_CERT_PEM}:False"

do_install() {
    if [ ! -r "${FLAX_HI_CERT_PEM}" ]; then
        bbwarn "flax-hi-cert: ${FLAX_HI_CERT_PEM} not readable; shipping no HI certificate."
        bbwarn "flax-hi-cert: bmcweb will self-sign (CN=testhost) and the BIOS will refuse"
        bbwarn "flax-hi-cert: the host interface, so Redfish CPU/DIMM inventory will be empty."
        return
    fi

    install -d ${D}${sysconfdir}/ssl/certs/https
    # 0640 matches the permission mint-hi-cert.sh has been deploying to running
    # BMCs; bmcweb runs as root (no User= in bmcweb.service), so it can read it.
    install -m 0640 ${FLAX_HI_CERT_PEM} ${D}${sysconfdir}/ssl/certs/https/server.pem
}

FILES:${PN} = "${sysconfdir}/ssl/certs/https/server.pem"

# The certificate is useless without the server that presents it.
RDEPENDS:${PN} = "bmcweb"
