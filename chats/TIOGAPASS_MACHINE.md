# Tiogapass Machine — Layered Build System Reference

## Layer Stack (bblayers.conf)

Bitbake searches layers in **reverse** order (last = highest priority):

```
1. meta                          ← Poky base (lowest priority)
2. meta-openembedded/meta-oe
3. meta-openembedded/meta-networking
4. meta-openembedded/meta-python
5. meta-phosphor                 ← OpenBMC core framework
6. meta-aspeed                   ← AST2500 SOC support
7. meta-facebook                 ← Facebook vendor layer
8. meta-facebook/meta-tiogapass  ← Platform-specific (highest priority)
   build/tiogapass/workspace     ← devtool overlay
```

---

## Machine Configuration Inheritance Chain

`meta-facebook/meta-tiogapass/conf/machine/tiogapass.conf` pulls in a hierarchy of `.inc` files that progressively build up the machine definition:

```
tiogapass.conf
  ├── conf/machine/include/ast2500.inc           (meta-aspeed)
  │     └── aspeed.inc
  │           MACHINEOVERRIDES =. "aspeed:"
  │           SERIAL_CONSOLES = "115200;ttyS4"
  │           KERNEL = linux-aspeed (fitImage)
  │           MACHINE_FEATURES += "hw-rng"
  │
  ├── conf/machine/include/facebook-compute-singlehost.inc (meta-facebook)
  │     └── facebook-compute.inc
  │           └── facebook-withhost.inc
  │                 └── facebook.inc
  │                       DISTROOVERRIDES .= ":facebook"
  │                       IMAGE_FEATURES:remove = "obmc-ikvm"  ← KVM disabled
  │                       SERIAL_CONSOLES:facebook = "57600;ttyS4"
  │
  ├── conf/machine/include/obmc-bsp-common.inc  (meta-phosphor)
  │
  └── phosphor-static-norootfs.inc              (meta-phosphor)
        IMAGE_FSTYPES = "cpio.xz.fitImage mtd-static-norootfs"
```

The `MACHINEOVERRIDES` chain becomes: **aspeed:aspeed-g5:fb-withhost:fb-compute:fb-compute-singlehost**, enabling conditional variable assignment like `SERIAL_CONSOLES:facebook = ...`.

---

## Flash Layout (64MB NOR)

Defined in `meta-facebook/meta-tiogapass/conf/machine/tiogapass.conf`:

| Region | Offset | Content |
|--------|--------|---------|
| U-Boot | 0      | `u-boot-aspeed-sdk` (AST2500 tuned) |
| Kernel | 1 MB   | `linux-aspeed` fitImage + initramfs |
| ROFS   | 40 MB  | Read-only root (cpio.xz, squashed) |
| RWFS   | 41 MB  | Read-write overlay (overlayfs-etc) |

---

## Platform Dependencies (AST2500)

All defined in `meta-aspeed/conf/machine/include/aspeed.inc`:

- **CPU:** ARM ARMv6 (arm1176jzs) — `tune-arm1176jz-s.inc`
- **Kernel:** `linux-aspeed` with `KERNEL_DEVICETREE = aspeed/aspeed-bmc-facebook-tiogapass.dtb`
- **Serial console:** ttyS4 at 57600 baud (Facebook override)
- **Hardware RNG:** `MACHINE_FEATURES += "hw-rng"`
- **udev rules:** `udev-aspeed-vuart`, `udev-aspeed-mtd-partitions` (MACHINE_EXTRA_RRECOMMENDS)
- **Bootloader:** `u-boot-aspeed-sdk` with `UBOOT_MACHINE = evb-ast2500_defconfig`

The kernel and u-boot configs are fragment-patched per-platform:
- `meta-facebook/meta-tiogapass/recipes-kernel/linux/linux-aspeed_%.bbappend` → adds `tiogapass.cfg`
- `meta-facebook/meta-tiogapass/recipes-bsp/u-boot/u-boot-aspeed-sdk_%.bbappend` → adds `tiogapass.cfg`

---

## Software Feature Map

`obmc-phosphor-image` maps `IMAGE_FEATURES` → packagegroups → packages:

```
IMAGE_FEATURE              PACKAGEGROUP                    KEY PACKAGES
─────────────────────────────────────────────────────────────────────────
obmc-sensors             → packagegroup-obmc-apps-sensors  → phosphor-hwmon
obmc-console             → packagegroup-obmc-apps-console  → obmc-console
obmc-bmcweb              → packagegroup-obmc-apps-bmcweb   → bmcweb
obmc-host-ipmi           → packagegroup-obmc-apps-ipmi     → phosphor-ipmi-*
obmc-fan-control         → packagegroup-obmc-apps-fans     → phosphor-fan-*
obmc-leds                → packagegroup-obmc-apps-leds     → phosphor-led-manager
obmc-logging-mgmt        → packagegroup-obmc-apps-logging  → phosphor-logging
obmc-network-mgmt        → packagegroup-obmc-apps-network  → phosphor-network
obmc-software            → packagegroup-obmc-apps-fw-mgmt  → phosphor-software-manager
obmc-ikvm                → [REMOVED by facebook.inc]
```

---

## Tiogapass-Specific Additions

### GPIO & Power Control

`meta-facebook/meta-tiogapass/recipes-tiogapass/fb-powerctrl/fb-powerctrl_0.1.bb` installs via:

```bitbake
OBMC_IMAGE_EXTRA_INSTALL:append = " fb-powerctrl "
```

Files installed:
- `setup_gpio` — initializes GPIO pins on AST2500 at boot
- `power-util` — host power management utility
- `host-gpio.service`, `host-poweron.service`, `host-poweroff.service` (systemd)

### Sensors

- **Intel CPU:** `recipes-phosphor/sensors/dbus-sensors_%.bbappend` enables `intelcpusensor`
- **NVMe (6 drives):** `phosphor-nvme/nvme_config.json` — bus IDs 20, 21, 24–27; criticalHigh = 75°C
- **Virtual sensors:** `phosphor-virtual-sensor/virtual_sensor_config.json`

### IPMB (Inter-board communication)

`recipes-phosphor/ipmi/phosphor-ipmi-ipmb_%.bbappend`:
- `/dev/ipmb-4` (remote addr 0x44)
- `/dev/ipmb-9` (remote addr 0x96)

### BIOS Update

`recipes-phosphor/flash/phosphor-software-manager_%.bbappend` adds `bios-update` script + `obmc-flash-host-bios@.service`.

---

## Dynamic Layer Inclusion

`meta-phosphor/conf/layer.conf` uses `BBFILES_DYNAMIC` to conditionally include recipes only when specific layers are present:

```bitbake
BBFILES_DYNAMIC += " \
    aspeed-layer:${LAYERDIR}/dynamic-layers/aspeed-layer/recipes-*/*/*.bbappend \
    nuvoton-layer:${LAYERDIR}/dynamic-layers/nuvoton-layer/... \
"
```

Because `meta-aspeed` is in BBLAYERS, `meta-phosphor/dynamic-layers/aspeed-layer/` is automatically activated — including FSI firmware and Aspeed u-boot patches from phosphor's perspective.

---

## Summary: Who Owns What

| Concern | Owner Layer |
|---------|-------------|
| ARM architecture tuning | `meta-aspeed` |
| Kernel / DTS / fitImage | `meta-aspeed` + `meta-tiogapass` cfg fragment |
| U-Boot | `meta-aspeed` + `meta-tiogapass` cfg fragment |
| Flash layout | `meta-tiogapass` (tiogapass.conf) |
| Serial console | `meta-aspeed` default → `meta-facebook` override |
| KVM (disabled) | `meta-facebook/facebook.inc` removes feature |
| Core OpenBMC daemons | `meta-phosphor` |
| Sensor infrastructure | `meta-phosphor` + `meta-tiogapass` appends |
| IPMI | `meta-phosphor` + `meta-tiogapass` IPMB channels |
| GPIO / power sequencing | `meta-tiogapass` (fb-powerctrl) |
| BIOS flash | `meta-tiogapass` |
| Web UI, REST, Redfish | `meta-phosphor` (bmcweb) |
