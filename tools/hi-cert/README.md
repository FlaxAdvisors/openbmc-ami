# Redfish Host Interface — TLS certificate

The stock image serves the OpenBMC self-signed certificate
(`C=US, O=OpenBMC, CN=testhost`), which ships in the read-only rootfs. The TP26
BIOS will not talk to the BMC with it.

**How long the replacement lasts** (measured 2026-08-11, not assumed): `/etc` is
an overlay — lowerdir the read-only rootfs, upperdir `/run/mnt-persist/etc-data`
on the persistent rwfs. Our `server.pem` is written to the upper layer, so it
**survives `flashcp` of a full image**; a flash+reboot does *not* revert it.

It is lost when the rwfs is erased: a factory reset, an explicit
`flash_erase /dev/mtd4`, or a unit that has never had it installed. Run the
script then — and whenever the check at the bottom of this file fails.

**To install it:**

```bash
# once per boot of the build box: mount the OEM image for its CA
dd if=/vagrant/WTPC_P407.ima of=/tmp/oem-root.cramfs bs=4096 skip=1120 count=5786
sudo modprobe cramfs && sudo mkdir -p /mnt/oemroot
sudo mount -t cramfs -o ro,loop /tmp/oem-root.cramfs /mnt/oemroot

./tools/hi-cert/mint-hi-cert.sh
```

## Why

The BIOS validates the BMC's TLS **chain** against a trust store containing
AMI's CA (`CN=www.ami.com`). Against any other certificate it ACKs our
Certificate flight and then sends a bare TCP RST with no TLS alert — there is no
error message anywhere, the connection simply dies. Verified on hardware
2026-07-30 and again 2026-08-11.

It validates the chain, **not** a pinned certificate: a leaf carrying our own
subject and our own freshly generated key, signed by AMI's CA, completes the
handshake. That is what this script mints.

## What is and is not in this repository

The AMI CA **private key is not in this repository and must not be committed.**
It is read by path out of the mounted OEM firmware image at run time. The script
refuses to write certificate material anywhere under the repo, verifies the CA
cert and key are a pair before using them, and never copies the CA key to the
BMC. Each run generates a fresh RSA-2048 key that belongs to us.

This is a bench workaround, not a shippable answer. The shippable options are:

1. AMI signs our CSR, or issues us a subordinate CA under the `www.ami.com`
   root — then we sign per-unit certificates, every BMC keeps its own unique
   key, and nothing secret of AMI's lives in our tree. This is the ask to AMI.
2. Replace the trust anchor in the BIOS itself, which removes the dependency on
   AMI entirely. Not investigated.

## Verifying it took

```bash
ssh brain "sshpass -p 0penBmc ssh root@192.168.88.248 \
  'openssl x509 -in /etc/ssl/certs/https/server.pem -noout -subject -issuer'"
```

Subject should be `O=Flax Advisors`, issuer `O=American Megatrends Incorporated`.
If the subject reads `CN=testhost`, the overlay copy is gone and the BIOS push
will fail silently at the TLS layer — re-run the script.

The script keeps the certificate it replaced as `server.pem.stock` next to it,
so you can always see what the image originally shipped.
