#!/usr/bin/env bash
#
# mint-hi-cert.sh - mint and install the BMC's Redfish Host Interface TLS cert.
#
# WHY THIS EXISTS
# ---------------
# The TP26 BIOS validates the BMC's TLS certificate chain against a trust store
# that contains AMI's CA (CN=www.ami.com, SKI F5:EA:84:8C:8A:31:DA:23:93:30:9E:
# 96:78:B1:8C:61:AA:B2:94:18).  Against any cert that does not chain to it, the
# BIOS ACKs our Certificate flight and then sends a bare TCP RST with no TLS
# alert, so the Redfish Host Interface inventory push never starts.  Verified
# 2026-07-30 and again 2026-08-11 on hardware.
#
# It validates the CHAIN, not a pinned certificate: a leaf carrying our own
# subject and our own freshly generated key, signed by AMI's CA, completes the
# handshake.  So we never need to reuse AMI's server key -- only their CA
# signature.
#
# /etc/ssl/certs/https/server.pem is baked into the read-only rootfs, so a full
# flash reverts the BMC to the stock OpenBMC self-signed cert
# (C=US, O=OpenBMC, CN=testhost).  Re-run this script after every reflash.
#
# THE AMI CA KEY IS NOT AND MUST NOT BE STORED IN THIS REPOSITORY.
# It is read by path from the OEM firmware image at run time.  Mount it with:
#
#   dd if=/vagrant/WTPC_P407.ima of=/tmp/oem-root.cramfs bs=4096 skip=1120 count=5786
#   sudo modprobe cramfs && sudo mkdir -p /mnt/oemroot
#   sudo mount -t cramfs -o ro,loop /tmp/oem-root.cramfs /mnt/oemroot
#
# This is a bench workaround.  The shippable fix is for AMI to sign our CSR or
# to issue us a subordinate CA under the www.ami.com root, so each BMC keeps a
# unique private key and nothing secret of AMI's lives in our tree.  A third
# option worth exploring is replacing the trust anchor in the BIOS itself.
#
# The generated private key and certificate are written outside the repository
# and the CA key is never copied to the BMC.

set -euo pipefail

CA_CERT=${CA_CERT:-/mnt/oemroot/etc/defconfig/ca.pem}
CA_KEY=${CA_KEY:-/mnt/oemroot/usr/local/redfish/certs/ca-key.pem}
BMC=${BMC:-192.168.88.248}
BMC_PASS=${BMC_PASS:-0penBmc}
HOP=${HOP:-brain}
OUTDIR=${OUTDIR:-${TMPDIR:-/tmp}/flax-hi-cert}
SUBJECT=${SUBJECT:-/C=US/O=Flax Advisors/OU=Service Processors/CN=flax-bmc.local}
DAYS=${DAYS:-3650}
HI_IP=${HI_IP:-169.254.0.17}
INBAND_IP=${INBAND_IP:-10.199.199.1}
REMOTE_PEM=/etc/ssl/certs/https/server.pem
INSTALL=1
RESTART=1

usage() {
	cat >&2 <<EOF
usage: $0 [options]

  --ca-cert PATH   AMI CA certificate      (default: $CA_CERT)
  --ca-key PATH    AMI CA private key      (default: $CA_KEY)
  --bmc ADDR       BMC address             (default: $BMC)
  --hop HOST       ssh jump host           (default: $HOP; "-" for direct)
  --subject DN     leaf subject            (default: $SUBJECT)
  --out DIR        output directory        (default: $OUTDIR)
  --no-install     mint only, do not touch the BMC
  --no-restart     install but do not restart bmcweb

Environment variables of the same names are honoured.
EOF
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--ca-cert) CA_CERT=$2; shift 2 ;;
	--ca-key) CA_KEY=$2; shift 2 ;;
	--bmc) BMC=$2; shift 2 ;;
	--hop) HOP=$2; shift 2 ;;
	--subject) SUBJECT=$2; shift 2 ;;
	--out) OUTDIR=$2; shift 2 ;;
	--no-install) INSTALL=0; shift ;;
	--no-restart) RESTART=0; shift ;;
	-h | --help) usage ;;
	*) echo >&2 "unknown argument: $1"; usage ;;
	esac
done

die() { echo >&2 "error: $*"; exit 1; }

# --- refuse to keep AMI key material anywhere inside the repository ----------
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
case "$(cd "$(dirname "$OUTDIR")" 2>/dev/null && pwd || echo "$OUTDIR")" in
"$repo_root" | "$repo_root"/*)
	die "refusing to write certificate material inside the repo ($OUTDIR)"
	;;
esac
for f in "$CA_CERT" "$CA_KEY"; do
	case "$(cd "$(dirname "$f")" 2>/dev/null && pwd || echo "$f")" in
	"$repo_root" | "$repo_root"/*)
		die "AMI CA material must not live in the repo ($f)"
		;;
	esac
done

[ -r "$CA_CERT" ] || die "CA certificate not readable: $CA_CERT (is the OEM image mounted? see header)"
[ -r "$CA_KEY" ] || die "CA key not readable: $CA_KEY (is the OEM image mounted? see header)"

# The CA cert and key must actually be a pair, or the BIOS will reject the chain.
ca_cert_mod=$(openssl x509 -in "$CA_CERT" -noout -modulus | openssl md5)
ca_key_mod=$(openssl rsa -in "$CA_KEY" -noout -modulus 2>/dev/null | openssl md5)
[ "$ca_cert_mod" = "$ca_key_mod" ] ||
	die "CA cert and CA key do not match ($ca_cert_mod vs $ca_key_mod)"

mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR"
umask 077

echo "==> AMI CA: $(openssl x509 -in "$CA_CERT" -noout -subject)"

# --- our own key, never AMI's -----------------------------------------------
openssl genrsa -out "$OUTDIR/server-key.pem" 2048 2>/dev/null
echo "==> generated a fresh RSA-2048 key (ours, not AMI's)"

cat > "$OUTDIR/leaf.ext" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = IP:$HI_IP, IP:$INBAND_IP, IP:$BMC, DNS:flax-bmc.local
EOF

openssl req -new -key "$OUTDIR/server-key.pem" -subj "$SUBJECT" \
	-out "$OUTDIR/server.csr" 2>/dev/null

openssl x509 -req -in "$OUTDIR/server.csr" \
	-CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
	-CAserial "$OUTDIR/ca.srl" \
	-days "$DAYS" -sha256 -extfile "$OUTDIR/leaf.ext" \
	-out "$OUTDIR/server-cert.pem" 2>/dev/null

openssl verify -CAfile "$CA_CERT" "$OUTDIR/server-cert.pem" >/dev/null ||
	die "minted leaf does not verify against the AMI CA"

# bmcweb expects the private key and the certificate in one file; append the CA
# so the BIOS receives the full chain in the Certificate flight.
cat "$OUTDIR/server-key.pem" "$OUTDIR/server-cert.pem" "$CA_CERT" \
	> "$OUTDIR/server.pem"

echo "==> minted $(openssl x509 -in "$OUTDIR/server-cert.pem" -noout -subject)"
echo "    issuer $(openssl x509 -in "$OUTDIR/server-cert.pem" -noout -issuer)"
echo "    chain verifies against the AMI CA"
echo "    output: $OUTDIR/server.pem"

# The chain file must never contain the CA's private key.
if grep -q "PRIVATE KEY" <(sed -n '/BEGIN CERTIFICATE/,$p' "$OUTDIR/server.pem"); then
	die "internal check failed: private key material after the leaf"
fi

[ "$INSTALL" = 1 ] || { echo "==> --no-install given, stopping here"; exit 0; }

# --- install ----------------------------------------------------------------
if [ "$HOP" = "-" ]; then
	bmc_ssh() { sshpass -p "$BMC_PASS" ssh -o StrictHostKeyChecking=no "root@$BMC" "$@"; }
	bmc_put() { sshpass -p "$BMC_PASS" scp -o StrictHostKeyChecking=no "$1" "root@$BMC:$2"; }
else
	# ssh concatenates its trailing arguments into one command string, so the
	# remote command has to be assembled here rather than passed as "$@".
	bmc_ssh() { ssh "$HOP" "sshpass -p $BMC_PASS ssh -o StrictHostKeyChecking=no root@$BMC '$*'"; }
	bmc_put() {
		scp -q "$1" "$HOP:/tmp/.hi-cert-staging" &&
			ssh "$HOP" "sshpass -p $BMC_PASS scp -o StrictHostKeyChecking=no /tmp/.hi-cert-staging root@$BMC:$2 && rm -f /tmp/.hi-cert-staging"
	}
fi

echo "==> installing to $BMC:$REMOTE_PEM"
bmc_ssh "[ -f $REMOTE_PEM.stock ] || cp $REMOTE_PEM $REMOTE_PEM.stock"
bmc_put "$OUTDIR/server.pem" "$REMOTE_PEM"
bmc_ssh "chmod 640 $REMOTE_PEM; openssl x509 -in $REMOTE_PEM -noout -subject -issuer"

if [ "$RESTART" = 1 ]; then
	echo "==> restarting bmcweb"
	bmc_ssh "systemctl restart bmcweb"
fi

echo "==> done.  Re-run this after any full flash: $REMOTE_PEM ships in the rootfs."
