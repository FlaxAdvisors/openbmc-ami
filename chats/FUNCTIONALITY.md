# OpenBMC AMI — Tiogapass Functionality Reference

This document maps each BMC capability to the build recipes, configuration files, and hardware
descriptors that implement it. Layer ownership follows the priority stack:

```
meta (Poky base) → meta-openembedded → meta-phosphor → meta-aspeed
  → meta-facebook → meta-facebook/meta-tiogapass → meta-flax
```

Higher layers override lower layers. `meta-flax` is the current active platform layer for the
64 MB flash variant.

---

## Host Management: Power, Cooling, LEDs, Inventory, Events, Watchdog

### Power Control

| Artifact | Path |
|---|---|
| Platform power recipe | `meta-facebook/meta-tiogapass/recipes-tiogapass/fb-powerctrl/fb-powerctrl_0.1.bb` |
| Core chassis power | `meta-phosphor/recipes-phosphor/chassis/obmc-phosphor-power_git.bb` |
| Skeleton power control | `meta-phosphor/recipes-phosphor/chassis/phosphor-skeleton-control-power_git.bb` |
| Power sequencer links | `meta-phosphor/recipes-phosphor/power/phosphor-power-systemd-links-sequencer.bb` |
| State manager | `meta-phosphor/recipes-phosphor/state/phosphor-state-manager_git.bb` |
| State manager override | `meta-facebook/meta-tiogapass/recipes-phosphor/state/phosphor-state-manager_%.bbappend` |
| Host POST code daemon | `meta-phosphor/recipes-phosphor/host/phosphor-host-postd_git.bb` |
| Host POST code override | `meta-facebook/meta-tiogapass/recipes-phosphor/host/phosphor-host-postd_%.bbappend` |
| POST code manager | `meta-phosphor/recipes-phosphor/state/phosphor-post-code-manager_git.bb` |

**Platform-installed files** (from `fb-powerctrl`):
- `setup_gpio` — initializes AST2500 GPIO pins at boot
- `power-util` — host power management CLI utility
- `host-gpio.service`, `host-poweron.service`, `host-poweroff.service` — systemd power lifecycle units

**IMAGE_FEATURE → PACKAGEGROUP mapping:**
`IMAGE_FEATURES += "obmc-chassis-state-mgmt"` → `packagegroup-obmc-apps` → `obmc-phosphor-power`

---

### Cooling / Fan Control

| Artifact | Path |
|---|---|
| Fan monitor/control | `meta-phosphor/recipes-phosphor/fans/phosphor-fan_git.bb` |
| PID fan control | `meta-phosphor/recipes-phosphor/fans/phosphor-pid-control_git.bb` |
| Fan monitor config | `meta-phosphor/recipes-phosphor/fans/phosphor-fan-monitor-config.bb` |
| Fan presence config | `meta-phosphor/recipes-phosphor/fans/phosphor-fan-presence-config.bb` |
| FB apps packagegroup | `meta-facebook/recipes-fb/packagegroups/packagegroup-fb-apps.bb` |

The PID fan controller (`phosphor-pid-control`) implements a software PID loop reading sensor
D-Bus objects and writing fan PWM targets via sysfs. Configuration is per-platform JSON.

**IMAGE_FEATURE:** `obmc-fan-control` → `packagegroup-obmc-apps-fans`

---

### LED Management

| Artifact | Path |
|---|---|
| LED manager daemon | `meta-phosphor/recipes-phosphor/leds/phosphor-led-manager_git.bb` |
| LED sysfs bridge | `meta-phosphor/recipes-phosphor/leds/phosphor-led-sysfs_git.bb` |
| LED YAML provider | `meta-phosphor/recipes-phosphor/leds/phosphor-led-manager-yaml-provider_git.bb` |
| LED MRW config | `meta-phosphor/recipes-phosphor/leds/phosphor-led-manager-config-mrw-native.bb` |

`phosphor-led-manager` exposes LEDs as D-Bus objects under `xyz.openbmc_project.Led.Groups`.
Physical LED control is via `phosphor-led-sysfs`, which maps sysfs `/sys/class/leds` entries.

**IMAGE_FEATURE:** `obmc-leds` → `packagegroup-obmc-apps-leds`

---

### Inventory Management

| Artifact | Path |
|---|---|
| Inventory manager | `meta-phosphor/recipes-phosphor/inventory/phosphor-inventory-manager_git.bb` |
| Asset tag support | `meta-phosphor/recipes-phosphor/inventory/phosphor-inventory-manager-assettag.bb` |
| IPMI sensor inventory | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-sensor-inventory*.bb` |
| IPMI FRU properties | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-fru-properties*.bb` |
| Entity manager | `meta-phosphor/recipes-phosphor/configuration/entity-manager_git.bb` |
| IPMI FRU daemon | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-fru_git.bb` |

`entity-manager` reads JSON configuration files describing physical hardware and publishes
D-Bus objects for sensors, FRUs, and associations. The inventory manager aggregates these into
the OpenBMC inventory tree.

**IMAGE_FEATURE:** `obmc-inventory` → `packagegroup-obmc-apps`

---

### Event / SEL Logging

| Artifact | Path |
|---|---|
| SEL logger | `meta-phosphor/recipes-phosphor/sel-logger/phosphor-sel-logger_git.bb` |
| Phosphor logging | `meta-phosphor/recipes-phosphor/logging/phosphor-logging_git.bb` |
| Debug collector | `meta-phosphor/recipes-phosphor/dump/phosphor-debug-collector_git.bb` |
| Debug errors native | `meta-phosphor/recipes-phosphor/dump/phosphor-debug-errors-native.bb` |
| Remote logging (rsyslog) | included via `obmc-remote-logging` packagegroup feature |

`phosphor-logging` implements `xyz.openbmc_project.Logging.Internal.Manager` — the central
error and event log D-Bus service. `phosphor-sel-logger` translates these events into IPMI SEL
records accessible via `ipmitool sel list`.

**IMAGE_FEATURE:** `obmc-logging-mgmt` → `packagegroup-obmc-apps-logging`

---

### Watchdog

| Artifact | Path |
|---|---|
| Watchdog daemon | `meta-phosphor/recipes-phosphor/watchdog/phosphor-watchdog_git.bb` |

`phosphor-watchdog` implements `xyz.openbmc_project.State.Watchdog` on D-Bus, interfacing with
the Linux hardware watchdog driver. IPMI watchdog commands (`Set Watchdog Timer`,
`Reset Watchdog Timer`) are handled via the IPMI host stack through this service.

---

## Full IPMI 2.0 Compliance with DCMI

### IPMI Transport Channels

| Channel | Recipe | Interface |
|---|---|---|
| LAN (out-of-band) | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-net_git.bb` | UDP port 623 |
| KCS (in-band) | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-kcs_git.bb` | `/dev/ipmi0` |
| BT (in-band) | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-bt_git.bb` | `/dev/bt` |
| SSIF (SMBus) | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-ssif_git.bb` | SMBus device |
| IPMB | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-ipmb_git.bb` | `/dev/ipmb-*` |

**TiogaPass IPMB channels** (`meta-facebook/meta-tiogapass/recipes-phosphor/ipmi/phosphor-ipmi-ipmb_%.bbappend`):
- `/dev/ipmb-4` remote address `0x44`
- `/dev/ipmb-9` remote address `0x96`

### IPMI Application Recipes

| Capability | Recipe |
|---|---|
| IPMI host daemon | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-host_git.bb` |
| FRU (Field Replaceable Unit) | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-fru_git.bb` |
| Flash / firmware blobs | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-flash_git.bb` |
| Blob transfer framework | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-blobs_git.bb` |
| Binary blob store | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-blobs-binarystore_git.bb` |
| Facebook OEM extensions | `meta-facebook/recipes-fb/ipmi/fb-ipmi-oem_git.bb` |

### DCMI

DCMI (Data Center Manageability Interface) is exposed through the IPMI LAN channel.
Channel configuration is at:

```
meta-flax/recipes-phosphor/ipmi/phosphor-ipmi-config/channel_config.json
```

DCMI commands (power management, thermal, sensors) map onto standard IPMI interfaces
served by `phosphor-ipmi-host` + `phosphor-ipmi-net`.

**IMAGE_FEATURE:** `obmc-host-ipmi` → `packagegroup-obmc-apps-ipmi`

---

## Code Update: Multiple BMC/BIOS Images

### Software Manager Stack

| Artifact | Path |
|---|---|
| Software manager | `meta-phosphor/recipes-phosphor/flash/phosphor-software-manager_git.bb` |
| YAML interface provider | `meta-phosphor/recipes-phosphor/flash/phosphor-software-manager-yaml-provider_git.bb` |
| Host firmware image | `meta-phosphor/recipes-phosphor/flash/phosphor-hostfw-image.bb` |
| Image signing | `meta-phosphor/recipes-phosphor/flash/phosphor-image-signing.bb` |
| IPMI flash handler | `meta-phosphor/recipes-phosphor/ipmi/phosphor-ipmi-flash_git.bb` |

**Subpackages** provided by `phosphor-software-manager`:
- `-version` — image version detection
- `-download-mgr` — downloads images via Redfish / TFTP
- `-updater` — writes images to MTD / UBI flash partitions
- `-updater-ubi`, `-updater-mmc` — storage-specific updater variants
- `-sync` — synchronizes dual-image partitions
- `-usb` — USB code update support
- `-side-switch` — active/standby partition switching

### TiogaPass BIOS Update

| Artifact | Path |
|---|---|
| Software manager bbappend | `meta-facebook/meta-tiogapass/recipes-phosphor/flash/phosphor-software-manager_%.bbappend` |
| BIOS flash service | `meta-facebook/meta-tiogapass/recipes-phosphor/flash/phosphor-software-manager/obmc-flash-host-bios@.service` |
| BIOS update script | `meta-facebook/meta-tiogapass/recipes-phosphor/flash/phosphor-software-manager/bios-update` |

The BIOS update path writes to the host SPI flash through the AST2500 LPC/PECI bridge.
The systemd template unit `obmc-flash-host-bios@.service` is instantiated per-image-id.

**Flash layout** (64 MB NOR, `meta-flax/conf/machine/tiogapass.conf`):

| Region | Offset | Size | Purpose |
|---|---|---|---|
| U-Boot | `0x000000` | 1 MB | `u-boot-aspeed-sdk` bootloader |
| Kernel | `0x100000` | 39 MB | `linux-aspeed` fitImage + initramfs |
| ROFS | `0xA00000` | 1 MB | Read-only root filesystem (cpio.xz) |
| RWFS | `0xA40000` | remainder | Read-write overlay (overlayfs-etc) |

**IMAGE_FEATURE:** `obmc-software` → `packagegroup-obmc-apps-fw-mgmt`

---

## Web-Based User Interface

### BMCWeb (Redfish + WebUI Host)

| Artifact | Path |
|---|---|
| bmcweb recipe | `meta-phosphor/recipes-phosphor/interfaces/bmcweb_git.bb` |
| Facebook bmcweb override | `meta-facebook/recipes-phosphor/interfaces/bmcweb_%.bbappend` |
| Vue.js frontend | `meta-phosphor/recipes-phosphor/webui/webui-vue_git.bb` |
| Legacy WebUI | `meta-phosphor/recipes-phosphor/webui/phosphor-webui_git.bb` |

`bmcweb` is a single C++ binary that:
- Serves the **Redfish** REST API (`/redfish/v1/`)
- Hosts the **Vue.js SPA** (`webui-vue`) for the browser-based dashboard
- Handles **mutual TLS authentication** and PAM-based credential validation
- Exposes Redfish resources by querying D-Bus services via `sdbusplus`

**PACKAGECONFIG options** in `bmcweb_git.bb`:
- `mutual-tls-auth` — client certificate authentication
- `insecure-redfish-expand` — allow `$expand` without auth (development only)

**System user:** `bmcweb` with group membership: `web`, `redfish`, `hostconsole`

**IMAGE_FEATURE:** `obmc-bmcweb` → `packagegroup-obmc-apps-bmcweb`

---

## REST Interfaces

The REST and Redfish API surface is entirely served by **bmcweb** (see above). Key endpoints:

| Endpoint prefix | Function |
|---|---|
| `/redfish/v1/Systems` | Host system state, power, BIOS |
| `/redfish/v1/Chassis` | Sensor data, FRUs, power |
| `/redfish/v1/Managers` | BMC configuration, logs, firmware |
| `/redfish/v1/AccountService` | User and LDAP management |
| `/redfish/v1/UpdateService` | Firmware upload and activation |
| `/redfish/v1/EventService` | Event subscriptions (SSE/push) |

Each Redfish resource handler internally calls D-Bus methods on the relevant phosphor service,
translating Redfish JSON payloads to/from D-Bus properties and method calls.

---

## D-Bus Based Interfaces

### Core D-Bus Infrastructure

| Artifact | Path |
|---|---|
| D-Bus interface definitions (YAML) | `meta-phosphor/recipes-phosphor/dbus/phosphor-dbus-interfaces_git.bb` |
| Object mapper | `meta-phosphor/recipes-phosphor/dbus/phosphor-objmgr_git.bb` |
| D-Bus monitor daemon | `meta-phosphor/recipes-phosphor/dbus/phosphor-dbus-monitor_git.bb` |
| D-Bus permissions config | `meta-phosphor/recipes-phosphor/dbus/dbus-perms/org.openbmc.conf` |
| sdbusplus library | dependency of all phosphor daemons |

`phosphor-dbus-interfaces` provides the canonical YAML definitions (compiled to C++ by
`sdbus++`) for all OpenBMC D-Bus interfaces under the `xyz.openbmc_project.*` namespace.

`phosphor-objmgr` (the **Object Mapper**) maintains a real-time map of which D-Bus service
owns which object paths, enabling service discovery across the entire BMC.

### Key D-Bus Service Namespaces

| Namespace | Service |
|---|---|
| `xyz.openbmc_project.State.*` | `phosphor-state-manager` |
| `xyz.openbmc_project.Logging.*` | `phosphor-logging` |
| `xyz.openbmc_project.Software.*` | `phosphor-software-manager` |
| `xyz.openbmc_project.Sensor.*` | `dbus-sensors`, `phosphor-hwmon` |
| `xyz.openbmc_project.User.*` | `phosphor-user-manager` |
| `xyz.openbmc_project.Led.*` | `phosphor-led-manager` |
| `xyz.openbmc_project.Inventory.*` | `phosphor-inventory-manager` |
| `xyz.openbmc_project.Network.*` | `phosphor-network` |
| `xyz.openbmc_project.Watchdog` | `phosphor-watchdog` |
| `xyz.openbmc_project.Ldap.*` | `phosphor-user-manager` (LDAP) |

---

## SSH-Based Serial Over LAN (SOL)

### Console Architecture

| Artifact | Path |
|---|---|
| obmc-console recipe | `meta-phosphor/recipes-phosphor/console/obmc-console_git.bb` |
| Facebook console override | `meta-facebook/recipes-phosphor/console/obmc-console_%.bbappend` |
| Dropbear PAM config (flax) | `meta-flax/recipes-extended/pam/libpam/dropbear` |

`obmc-console` provides a Unix socket connected to the host UART. It is exposed over SSH via:
- `obmc-console-ssh@.service` — per-console SSH session handler
- `obmc-console-ssh.socket` — systemd socket activation on the SOL port

**PACKAGECONFIG** in `obmc-console_git.bb`:
- `udev` — udev-based console device discovery
- `ssh` — SSH SOL support (enabled by default)
- `concurrent-servers` — multiple simultaneous SOL sessions

**Serial configuration** (`meta-aspeed` / `meta-facebook` override):
- Default: `SERIAL_CONSOLES = "115200;ttyS4"` (from `aspeed.inc`)
- Facebook override: `SERIAL_CONSOLES:facebook = "57600;ttyS4"` (from `facebook.inc`)

SSH server is Dropbear, included via `IMAGE_FEATURES += "ssh-server-dropbear"`.

**IMAGE_FEATURE:** `obmc-console` → `packagegroup-obmc-apps-console`

---

## Remote KVM

### ipKVM Stack

| Artifact | Path |
|---|---|
| obmc-ikvm recipe | `meta-phosphor/recipes-graphics/obmc-ikvm/obmc-ikvm_git.bb` |
| IMAGE_FEATURES remove | `meta-facebook/conf/machine/include/facebook.inc` |

`obmc-ikvm` implements a VNC server that reads video frames from the AST2500's V4L2
video capture device (hardware video engine) and serves them as a JPEG stream to remote
KVM clients.

- **Dependency:** `libvncserver`
- **Service:** `start-ipkvm.service`
- **Protocol:** VNC over HTTPS (proxied through bmcweb)

> **Note for Tiogapass:** KVM is **disabled** in the Facebook layer stack.
> `facebook.inc` contains `IMAGE_FEATURES:remove = "obmc-ikvm"`. To re-enable, remove
> this line from `meta-facebook/conf/machine/include/facebook.inc` or override it in
> `meta-flax`.

---

## User Management

### User Manager Stack

| Artifact | Path |
|---|---|
| User manager daemon | `meta-phosphor/recipes-phosphor/users/phosphor-user-manager_git.bb` |
| Default admin user (flax) | `meta-flax/recipes-phosphor/users/phosphor-user-manager-default-admin.bb` |
| Admin creation script | `meta-flax/recipes-phosphor/users/phosphor-user-manager-default-admin/create-admin-user.sh` |
| Admin creation service | `create-admin-user.service` |

`phosphor-user-manager` exposes `xyz.openbmc_project.User.Manager` on D-Bus. It manages:
- Local PAM-backed user accounts
- Privilege groups: `priv-admin`, `priv-operator`, `priv-user`, `hostconsole`
- LDAP/Active Directory integration via `nss-pam-ldapd`
- Root account management (`root-user-mgmt` PACKAGECONFIG, enabled by default)

### LDAP Support

| Artifact | Path |
|---|---|
| LDAP config service | `xyz.openbmc_project.Ldap.Config.service` |
| LDAP binary | `phosphor-ldap-conf` |

LDAP is configured via the Redfish `AccountService` or D-Bus methods on
`xyz.openbmc_project.Ldap.Config.Manager`.

**IMAGE_FEATURE:** `obmc-user-mgmt` → `packagegroup-obmc-apps`
**IMAGE_FEATURE:** `obmc-user-mgmt-ldap` → `packagegroup-obmc-apps`

---

## Virtual Media

### Current Build Status

Virtual media (remote ISO/USB mounting) is **not explicitly enabled** in the Tiogapass image.
The `obmc-ikvm` feature (which would share the bmcweb virtual media handler) is removed by
`meta-facebook/conf/machine/include/facebook.inc`.

The NVMe and virtual sensor infrastructure that exists is for **local NVMe drive monitoring**,
not network virtual media:

| Artifact | Path | Purpose |
|---|---|---|
| NVMe sensor recipe | `meta-phosphor/recipes-phosphor/sensors/phosphor-nvme_git.bb` | NVMe drive temp/health |
| NVMe TiogaPass config | `meta-facebook/meta-tiogapass/recipes-phosphor/sensors/phosphor-nvme_%.bbappend` | 6-drive config |
| NVMe JSON config | `meta-facebook/meta-tiogapass/recipes-phosphor/sensors/phosphor-nvme/nvme_config.json` | Bus IDs 20,21,24-27 |
| Virtual sensor recipe | `meta-phosphor/recipes-phosphor/sensors/phosphor-virtual-sensor_git.bb` | Computed sensors |
| Virtual sensor config | `meta-facebook/meta-tiogapass/recipes-phosphor/sensors/phosphor-virtual-sensor/virtual_sensor_config.json` | Derived values |

To enable true virtual media (network ISO/USB), the following would be required:
1. Re-enable `obmc-ikvm` IMAGE_FEATURE (or enable the bmcweb virtual-media handler separately)
2. Add `virtual-media` to bmcweb PACKAGECONFIG
3. Provide a platform USB gadget or NBD driver configuration

---

## Hardware Descriptor Files (AST2500 Platform)

> **Note:** The AST2500 SoC is no longer supported by AMI's current "OneTree" product line.
> AMI's `meta-ami` and `meta-core` layers target AST2600/AST2700 only. The in-tree
> `meta-intel-openbmc` (S2600WF reference) remains the only Intel platform layer with AST2500
> content. See [HUNT_FOR_AST2500.md](HUNT_FOR_AST2500.md) for full analysis.

These files provide the low-level hardware description consumed by the kernel and bootloader.

### Device Tree

| Artifact | Path |
|---|---|
| Kernel DTS (upstream) | `arch/arm/boot/dts/aspeed/aspeed-bmc-facebook-tiogapass.dts` (in kernel source) |
| DTB variable | `KERNEL_DEVICETREE = "aspeed/aspeed-bmc-facebook-tiogapass.dtb"` (in `aspeed.inc`) |

The device tree describes: LPC/IPMI controllers, I2C buses and mux topology, SPI flash,
UART consoles, PWM/fan controllers, ADC, GPIO banks, watchdog, video engine, and USB.

### Kernel Configuration Fragments

| Layer | Path |
|---|---|
| TiogaPass kernel config | `meta-facebook/meta-tiogapass/recipes-kernel/linux/linux-aspeed/tiogapass.cfg` |
| TiogaPass bbappend | `meta-facebook/meta-tiogapass/recipes-kernel/linux/linux-aspeed_%.bbappend` |
| Flax kernel bbappend | `meta-flax/recipes-kernel/linux/linux-aspeed_%.bbappend` |

### U-Boot Configuration

| Layer | Path |
|---|---|
| TiogaPass U-Boot config | `meta-facebook/meta-tiogapass/recipes-bsp/u-boot/u-boot-aspeed-sdk/tiogapass.cfg` |
| TiogaPass bbappend | `meta-facebook/meta-tiogapass/recipes-bsp/u-boot/u-boot-aspeed-sdk_%.bbappend` |
| Flax U-Boot config | `meta-flax/recipes-bsp/u-boot/u-boot-aspeed-sdk/tiogapass.cfg` |
| U-Boot FW utils | `meta-facebook/meta-tiogapass/recipes-bsp/u-boot/u-boot-fw-utils-aspeed-sdk_%.bbappend` |

U-Boot base: `UBOOT_MACHINE = evb-ast2500_defconfig` (from `aspeed.inc`)

### Machine Configuration Inheritance

```
meta-flax/conf/machine/tiogapass.conf          (active, 64 MB flash)
meta-facebook/meta-tiogapass/conf/machine/tiogapass.conf
  └── meta-aspeed/conf/machine/include/ast2500.inc
        └── meta-aspeed/conf/machine/include/aspeed.inc
  └── meta-facebook/conf/machine/include/facebook-compute-singlehost.inc
        └── facebook-compute.inc
              └── facebook-withhost.inc
                    └── facebook.inc           (removes obmc-ikvm)
  └── meta-phosphor/conf/machine/include/obmc-bsp-common.inc
  └── meta-phosphor/conf/machine/include/image-type/static-norootfs.inc
```

---

## IMAGE_FEATURE to Packagegroup Summary

| IMAGE_FEATURE | Packagegroup | Key Packages |
|---|---|---|
| `obmc-sensors` | `packagegroup-obmc-apps-sensors` | `phosphor-hwmon`, `dbus-sensors` |
| `obmc-console` | `packagegroup-obmc-apps-console` | `obmc-console` |
| `obmc-bmcweb` | `packagegroup-obmc-apps-bmcweb` | `bmcweb`, `phosphor-certificate-manager` |
| `obmc-host-ipmi` | `packagegroup-obmc-apps-ipmi` | `phosphor-ipmi-host`, `phosphor-ipmi-net` |
| `obmc-fan-control` | `packagegroup-obmc-apps-fans` | `phosphor-fan-monitor` |
| `obmc-leds` | `packagegroup-obmc-apps-leds` | `phosphor-led-manager`, `phosphor-led-sysfs` |
| `obmc-logging-mgmt` | `packagegroup-obmc-apps-logging` | `phosphor-logging`, `phosphor-sel-logger` |
| `obmc-network-mgmt` | `packagegroup-obmc-apps-network` | `phosphor-network` |
| `obmc-software` | `packagegroup-obmc-apps-fw-mgmt` | `phosphor-software-manager` |
| `obmc-inventory` | `packagegroup-obmc-apps` | `phosphor-inventory-manager` |
| `obmc-user-mgmt` | `packagegroup-obmc-apps` | `phosphor-user-manager` |
| `obmc-user-mgmt-ldap` | `packagegroup-obmc-apps` | `phosphor-user-manager` (LDAP) |
| `obmc-chassis-state-mgmt` | `packagegroup-obmc-apps` | `obmc-phosphor-power` |
| `obmc-ikvm` | `packagegroup-obmc-apps` | `obmc-ikvm` (**removed** by `facebook.inc`) |
| `obmc-webui` | `packagegroup-obmc-apps` | `webui-vue` |
| `obmc-debug-collector` | `packagegroup-obmc-apps` | `phosphor-debug-collector` |
| `obmc-health-monitor` | `packagegroup-obmc-apps` | `phosphor-health-monitor` |
| `obmc-telemetry` | `packagegroup-obmc-apps` | `telemetry` |
| `obmc-dmtf-pmci` | `packagegroup-obmc-apps` | PLDM, MCTP |

Packagegroup definitions:
- `meta-phosphor/recipes-phosphor/packagegroups/packagegroup-obmc-apps.bb`
- `meta-facebook/recipes-fb/packagegroups/packagegroup-fb-apps.bb`
