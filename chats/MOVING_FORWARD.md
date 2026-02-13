# Moving Forward: Tiogapass on Linux Foundation OpenBMC

**Document type:** Firmware Architecture Plan
**Scope:** Modernising the Tiogapass BMC build to track the LF OpenBMC mainline while preserving all hardware-necessary customisations and fully realising the target feature set.

---

## 1. Problem Statement

The current build stacks three legacy layers — `meta-facebook`, `meta-facebook/meta-tiogapass`, and `meta-flax` — on top of `meta-phosphor`. Together these layers:

- **Replace** the entire upstream packagegroup system via `PREFERRED_PROVIDER` overrides in `facebook.inc`, routing all application management through a monolithic `packagegroup-fb-apps` that obscures feature selection.
- **Remove** capabilities that are explicit requirements: SSH-based SOL, IPMI LAN (net-ipmi), the web UI, LDAP, and iKVM are each disabled by Facebook-specific policy variables.
- **Introduce multi-host scaffolding** (`OBMC_HOST_INSTANCES`, `fb-consoles.inc`, dynamic ttyS assignment, multi-host rsyslog config) that is architecturally irrelevant for TiogaPass — a single-host platform.
- **Carry 40+ dead BBMASK entries** in `meta-flax/conf/layer.conf` that reference paths (`meta-ami/meta-common/`, `meta-common/meta-common/`) which **do not exist** in this repository. These are stale references to an earlier deployment where AMI maintained a private fork of Intel's common layer alongside the upstream. They mask nothing and break nothing today, but they are dead code that obscures the layer's true purpose.
- **Leave `meta-intel-openbmc` stranded.** This repository contains Intel's full reference OpenBMC stack at `meta-intel-openbmc/meta-common/` — an Apache-2.0 layer providing CPU error monitoring, Platform Firmware Resilience, Intel OEM IPMI commands, IPMB-to-Management-Engine wiring, structured Redfish event logging, and more. It is not in `bblayers.conf` and is therefore entirely inactive, leaving a significant capability gap.
- **Duplicate machine configuration** across `meta-facebook/meta-tiogapass/conf/machine/tiogapass.conf` (32 MB flash, now stale) and `meta-flax/conf/machine/tiogapass.conf` (64 MB flash, current), with no clear authority.
- **Compete** for the same upstream recipe via parallel `.bbappend` files in `meta-facebook` and `meta-flax`, making it difficult to reason about what is actually installed.

The result is a build that is hard to update, prevents clean upstream tracking, silently disables features that operators expect, and fails to activate Intel platform management capabilities that are already present in the repository.

---

## 2. Design Principles for the Migration

1. **Single authoritative platform layer.** All TiogaPass hardware customisations live in one new layer — `meta-tiogapass-lf`. Nothing platform-specific lives in a generic Facebook layer.
2. **Upstream-first.** If `meta-phosphor` or `meta-aspeed` already provides a recipe, use it. Only write a `.bbappend` or new recipe when the hardware requires deviation.
3. **Minimal override surface.** Prefer `PACKAGECONFIG` additions and `SRC_URI` additions over forking full recipes or replacing `PREFERRED_PROVIDER` chains.
4. **Full feature parity with stated requirements.** Every capability in the feature list (IPMI 2.0/DCMI, Web UI, REST, D-Bus, SSH SOL, KVM, user management, code update, virtual media) must be derivable from `IMAGE_FEATURES` on the upstream `obmc-phosphor-image`.
5. **No Facebook inheritance chain.** The machine conf must not include `facebook.inc`, `facebook-withhost.inc`, `facebook-compute.inc`, or `facebook-compute-singlehost.inc`.
6. **No BBMASK.** Layer conflicts are resolved by removing the conflicting layer from `bblayers.conf`, not by masking recipes inside it.

---

## 3. Current Layer Interference Map

This section documents exactly what each Facebook/Flax construct blocks or overrides, and what the upstream replacement is.

### 3.1 `meta-facebook/conf/machine/include/facebook.inc`

| What it does | Why it is wrong | Upstream replacement |
|---|---|---|
| `PREFERRED_PROVIDER_virtual/obmc-*` → `packagegroup-fb-apps` | Replaces all phosphor packagegroups with a single monolith | Remove; let `obmc-phosphor-image` use its own packagegroup tree |
| `IMAGE_FEATURES:remove = "obmc-ikvm"` | Disables KVM globally for all Facebook machines | Remove the removal; iKVM is a stated requirement |
| `IMAGE_FEATURES:append = "allow-root-login"` | Enables root login permanently | Replace with `phosphor-user-manager`'s privilege model |
| `DISTRO_FEATURES:remove = "avahi ldap slp"` | Disables LDAP (and thus user management completeness) | Remove; keep ldap in DISTRO_FEATURES |
| `require phosphor-no-webui.inc` | Disables web UI | Remove; `obmc-bmcweb` is a stated requirement |
| `SERIAL_CONSOLES:facebook = "57600;ttyS4"` | Overrides baud rate | Move this single line into the new machine conf |
| `DISTROOVERRIDES .= ":facebook"` | Enables all `facebook` conditional code paths | Not needed once the Facebook layer is gone |

### 3.2 `meta-facebook/conf/machine/include/facebook-withhost.inc`

| What it does | Why it is wrong | Upstream replacement |
|---|---|---|
| `VIRTUAL-RUNTIME_obmc-chassis-state-mgr = "x86-power-control"` | Hard-wires x86-power-control globally | Move to tiogapass machine conf only |
| `VIRTUAL-RUNTIME_obmc-host-state-mgr = "x86-power-control"` | Same | Same |
| `MACHINEOVERRIDES =. "fb-withhost:"` | Activates all `fb-withhost` conditional recipes | Not needed; remove the include |

### 3.3 `meta-facebook/conf/machine/include/facebook-compute-singlehost.inc`

| What it does | Why it is wrong | Upstream replacement |
|---|---|---|
| `PREFERRED_PROVIDER_virtual/obmc-host-ipmi-hw = "phosphor-ipmi-kcs"` | Correct for x86 — but is buried 4 includes deep | Move this one line into the new machine conf |
| `MACHINE_FEATURES += "obmc-host-ipmi"` | Correct but redundant | Move to new machine conf |

### 3.4 `meta-facebook/recipes-phosphor/console/obmc-console_%.bbappend`

| What it does | Why it is wrong | Upstream replacement |
|---|---|---|
| `PACKAGECONFIG:remove = "ssh"` | Disables SSH console (SOL) | Remove this line; SSH SOL is a stated requirement |
| Dynamic multi-host `SERVER_CONFS` generation | Unnecessary complexity for single host | Replace with a static `server.ttyS2.conf` install |

### 3.5 `meta-facebook/recipes-fb/packagegroups/packagegroup-fb-apps.bb`

This recipe exists only because `PREFERRED_PROVIDER_virtual/obmc-*` routes to it. Once those PREFERRED_PROVIDERs are removed, this packagegroup becomes unreachable and can be deleted from the new layer.

### 3.6 `meta-facebook/recipes-phosphor/images/fb-phosphor-image.inc`

| What it does | Why it is wrong | Upstream replacement |
|---|---|---|
| `IMAGE_FEATURES:remove = "obmc-net-ipmi"` | Disables IPMI LAN — breaks IPMI 2.0 compliance | Remove; `phosphor-ipmi-net` must be in the image |
| `IMAGE_FEATURES:remove = "obmc-user-mgmt-ldap"` | Removes LDAP | Remove |
| `IMAGE_FEATURES:remove = "ssh-server-dropbear"` + `append = "ssh-server-openssh"` | Replaces SSH server | A platform choice; keep OpenSSH if preferred but make it explicit in the new layer |
| Debug tools: `curl dbus-top strace tcpdump …` | Development convenience | Move to a separate debug image or `EXTRA_IMAGE_FEATURES` |

### 3.7 `meta-flax/conf/layer.conf` BBMASK block

**The BBMASK entries are entirely dead code.** The 40+ entries reference paths under `meta-ami/meta-common/` and `meta-common/meta-common/` — neither of these directories exists anywhere in this repository. Bitbake BBMASK works by pattern-matching against recipe file paths that are actually found; patterns that match nothing have no effect.

The BBMASK was written for a prior deployment context where AMI had checked out:
1. Its own private fork of Intel's common layer at `meta-ami/meta-common/`
2. Possibly a second checkout of the same Intel code at `meta-common/meta-common/`

The intent was to suppress the AMI fork in favour of Intel's upstream originals from `meta-intel-openbmc/meta-common/`. That upstream Intel layer **is present** in this repository but is **also not in `bblayers.conf`**, meaning the BBMASK prevented an AMI fork that doesn't exist here from competing with an Intel original that is also not active. The net result is that none of the Intel platform management recipes are built at all.

The correct resolution: delete the BBMASK block, add `meta-intel-openbmc` to `bblayers.conf` (see Section 5), and let its recipes build normally.

### 3.8 `meta-flax/conf/machine/tiogapass.conf`

This file contains two genuinely platform-necessary items and several Facebook-legacy items:

| Item | Keep / discard |
|---|---|
| `FLASH_SIZE = "65536"` and partition offsets | **Keep** — port to new layer |
| `OBMC_IMAGE_EXTRA_INSTALL:append = " x86-power-control"` | **Keep** — port to new layer |
| `SYSTEMD_MASK += "phosphor-multi-gpio-monitor.service"` | **Evaluate** — re-enable GPIO monitoring if device tree describes the GPIOs; mask only if DTS omits them |
| `OBMC_COMPATIBLE_NAMES` containing `com.meta.Hardware.*` | **Replace** with an OCP/LF-compatible name, e.g. `org.openbmc.Hardware.BMC.TiogaPass` |

---

## 4. What to Keep from the Facebook/Flax Layers

The following items are genuine hardware requirements and must be ported to the new platform layer verbatim or minimally adapted.

### 4.1 Kernel Configuration Fragment

**Source:** `meta-facebook/meta-tiogapass/recipes-kernel/linux/linux-aspeed/tiogapass.cfg`

Retain all of:
- `CONFIG_PECI=y`, `CONFIG_PECI_ASPEED=y`, `CONFIG_PECI_CHARDEV=y` — Intel PECI thermal interface
- `CONFIG_SENSORS_PECI_CPUTEMP=y`, `CONFIG_SENSORS_PECI_DIMMTEMP=y` — CPU/DIMM temperature
- `CONFIG_MFD_INTEL_PECI_CLIENT=y` — PECI client framework
- `CONFIG_SENSORS_TMP421=y` — on-board temperature sensor
- `CONFIG_SENSORS_MAX31785=y` — fan controller
- `CONFIG_RTC_DRV_RV8803=y` — real-time clock
- `CONFIG_TCG_TPM=y`, `CONFIG_TCG_TIS_I2C_INFINEON=y` — TPM security
- `CONFIG_NCSI_OEM_CMD_GET_MAC=y` — NCSI NIC MAC retrieval
- `CONFIG_I2C_SLAVE=y` — BMC as I2C slave device

### 4.2 Flash Layout Patch

**Source:** `meta-flax/recipes-kernel/linux/linux-aspeed/0001-Increased-flash-chip-size.patch`

The DTS change that enlarges the kernel partition to 40 MB and enables the 64 MB NOR is mandatory. Port this patch to the new layer.

### 4.3 U-Boot Configuration

**Source:** `meta-flax/recipes-bsp/u-boot/u-boot-aspeed-sdk/tiogapass.cfg`

Retain:
```
CONFIG_BAUDRATE=57600
CONFIG_BOOTARGS="console=ttyS4,57600n8 root=/dev/ram rw"
CONFIG_BOOTCOMMAND="sf probe; sf read 0x83000000 0x100000 0x2400000; bootm 0x83000000"
```
This reflects the actual hardware boot path from the 64 MB flash.

### 4.4 IPMB Channel Configuration

**Source:** `meta-facebook/meta-tiogapass/recipes-phosphor/ipmi/phosphor-ipmi-ipmb_%.bbappend`

IPMB buses 4 and 9 at addresses `0x44` and `0x96` are physical I2C topology on the board. Port directly.

### 4.5 NVMe Sensor Configuration

**Source:** `meta-facebook/meta-tiogapass/recipes-phosphor/sensors/phosphor-nvme/nvme_config.json`

Six NVMe drives on I2C buses 20, 21, 24–27 with `criticalHigh = 75°C`. Port the JSON and the bbappend.

### 4.6 Virtual Sensor Configuration

**Source:** `meta-facebook/meta-tiogapass/recipes-phosphor/sensors/phosphor-virtual-sensor/virtual_sensor_config.json`

Platform-derived computed sensors. Port the JSON.

### 4.7 Intel CPU Sensor Enable

**Source:** `meta-facebook/meta-tiogapass/recipes-phosphor/sensors/dbus-sensors_%.bbappend`
```
PACKAGECONFIG:append = " intelcpusensor"
```
Required for PECI-based CPU temperature monitoring.

### 4.8 BIOS Update Service and Script

**Source:** `meta-facebook/meta-tiogapass/recipes-phosphor/flash/phosphor-software-manager/`

The `obmc-flash-host-bios@.service` template and `bios-update` script encode the TiogaPass-specific SPI flash topology. Port both.

### 4.9 x86 Host Power Control

**Source:** `meta-flax/conf/machine/tiogapass.conf` and `meta-facebook/recipes-x86/chassis/x86-power-control_%.bbappend`

`x86-power-control` is the correct OpenBMC daemon for x86 host state management. Keep it and set:
```
VIRTUAL-RUNTIME_obmc-chassis-state-mgr = "x86-power-control"
VIRTUAL-RUNTIME_obmc-host-state-mgr = "x86-power-control"
```
directly in the new machine conf.

### 4.10 Default Admin User Creation

**Source:** `meta-flax/recipes-phosphor/users/phosphor-user-manager-default-admin.bb` and `create-admin-user.sh`

A first-boot admin account is necessary for initial access. Port the recipe and script; harden the default credential policy (force password change on first login).

### 4.11 KCS3 IPMI Channel Config

**Source:** `meta-flax/recipes-phosphor/ipmi/phosphor-ipmi-config.bbappend` + `channel_config.json`

Additional KCS channel needed for DCMI. Port directly.

### 4.12 SEL Logger Delete Capability

**Source:** `meta-flax/recipes-phosphor/sel-logger/phosphor-sel-logger_git.bbappend`

Enables the SEL clear command via Redfish and IPMI. Port directly.

### 4.13 State Manager Requires→Wants Fix

**Source:** `meta-flax/recipes-phosphor/state/phosphor-state-manager_%.bbappend`

Removes the `multi-user.target.requires/xyz.openbmc_project.State.Host@0.service` and `...Chassis@0.service` hard requirements to prevent D-Bus name collision boot failures. Port directly.

### 4.14 libmctp Patch

**Source:** `meta-flax/recipes-phosphor/libmctp/libmctp_%.bbappend`

Fixes a compile warning that becomes a build error. Port directly.

---

## 5. Activating `meta-intel-openbmc`

`meta-intel-openbmc` is an Apache-2.0 layer maintained by Intel in the LF OpenBMC upstream
(`github.com/openbmc/`). It is present in this repository at [meta-intel-openbmc/](meta-intel-openbmc/)
and has a `meta-common` sub-layer and a `meta-s2600wf` machine sub-layer. It is currently
**absent from `bblayers.conf`** and therefore provides nothing to the build.

### 5.1 What `meta-intel-openbmc/meta-common` Provides

| Recipe / Service | D-Bus name / binary | Capability gap it fills |
|---|---|---|
| `host-error-monitor_git.bb` | `xyz.openbmc_project.HostErrorMonitor.service` | CPU hardware error detection and reporting via PECI |
| `pfr-manager_git.bb` | `xyz.openbmc_project.PFR.Manager.service` | Intel Platform Firmware Resilience — automated recovery from corrupt BMC or host firmware |
| `intel-ipmi-oem_git.bb` | `libzinteloemcmds.so` | Intel OEM IPMI command library loaded by both KCS and LAN channels |
| `phosphor-ipmi-ipmb_%.bbappend` | `ipmb-channels.json` | IPMB bridge to Intel Management Engine on `/dev/ipmb-5` (addr `0x2C`) |
| `packagegroup-intel-apps.bb` | `virtual/obmc-chassis-mgmt` etc. | Intel-aligned application bundle wiring — replaces `packagegroup-fb-apps` |
| `intel-led-manager-config-native.bb` | `virtual/phosphor-led-manager-config-native` | LED group definitions: status_ok (green), status_critical (amber), enclosure_identify |
| `phosphor-pid-control_%.bbappend` | `swampd` | D-Bus dynamic PID fan configuration with auto-restart |
| `bmcweb_%.bbappend` | — | Enables `redfish-cpu-log` and `redfish-bmc-journal`; disables legacy REST API |
| `x86-power-control_%.bbappend` | — | Enables PLT_RST warm-reset detection, ignores soft resets during POST, AC boot tracking |
| `rsyslog_%.bbappend` | `rotate-event-logs.service` | Routes journal events to structured `/var/log/ipmi_sel` and `/var/log/redfish`; 60-second log rotation |
| `phosphor-sel-logger_%.bbappend` | — | Enables `log-threshold` SEL filtering for Intel sensor events |
| `phosphor-webui_%.bbappend` | — | Web console 100×32, VT100+ keyboard mode |

### 5.2 What Is Currently Missing Because This Layer Is Inactive

| Missing capability | Consequence |
|---|---|
| No `host-error-monitor` | CPU hardware errors (correctable/uncorrectable) are not reported to BMC logs or Redfish |
| No `pfr-manager` | No automated firmware recovery — a corrupted BMC flash has no self-healing path |
| No `intel-ipmi-oem` | Intel OEM IPMI command set absent; tooling that relies on these commands will fail |
| No IPMB-to-ME channel | Management Engine is unreachable via IPMB; ME-based power telemetry and out-of-band management unavailable |
| No structured Redfish/SEL log routing | `/var/log/ipmi_sel` and `/var/log/redfish` are not populated; event audit trail is absent |
| No Intel LED definitions | `phosphor-led-manager` has no platform LED group config; status LEDs are non-functional |

### 5.3 `meta-intel-openbmc/conf/machine/include/intel.inc`

This include file sets the `virtual/obmc-*` PREFERRED_PROVIDER mappings to `packagegroup-intel-apps`,
which is the Intel equivalent of `packagegroup-fb-apps` — except that it uses the standard
phosphor recipe infrastructure rather than replacing it. Including `intel.inc` from `tiogapass.conf`
makes the Intel application bundle the provider of the virtual chassis/fan/flash/system management
slots, replacing the Facebook version cleanly.

### 5.4 `meta-intel-openbmc/meta-s2600wf`

The S2600WF sub-layer is a sibling Intel server machine (dual Xeon, AST2500 BMC) that is a
useful reference for GPIO and power-config JSON structure applicable to TiogaPass. It should not
be added to `bblayers.conf`; it serves as documentation only.

### 5.5 IPMB Channel Reconciliation

`meta-intel-openbmc/meta-common` configures IPMB for:
- `/dev/ipmb-5` → Management Engine at address `0x2C`
- `/dev/ipmb-13` → inter-board at address `0x38`

The existing TiogaPass Facebook config uses:
- `/dev/ipmb-4` → address `0x44`
- `/dev/ipmb-9` → address `0x96`

These reflect different physical I2C topologies. The new `phosphor-ipmi-ipmb_%.bbappend` in
`meta-tiogapass-lf` must define all required channels explicitly rather than inheriting blindly
from either source. Verify against the TiogaPass board schematics before finalising.

---

## 6. New Layer Architecture

### 6.1 Proposed `bblayers.conf`

```
meta                                   # Poky base
meta-openembedded/meta-oe
meta-openembedded/meta-networking
meta-openembedded/meta-python
meta-phosphor                          # LF OpenBMC core
meta-aspeed                            # AST2500 SoC support
meta-intel-openbmc                     # Intel server management stack (was present but inactive)
meta-tiogapass-lf                      # NEW: single platform layer (replaces all Facebook/Flax layers)
build/tiogapass/workspace              # devtool overlay (optional)
```

`meta-facebook`, `meta-facebook/meta-tiogapass`, and `meta-flax` are **removed from `bblayers.conf`**.
`meta-ami` and `meta-common` as standalone top-level directories **do not exist** in this repository
and were never in `bblayers.conf`; their BBMASK entries in `meta-flax` were already dead code.
With the Facebook/Flax layers gone, there is no BBMASK needed — `meta-intel-openbmc` has no
competitors in the new stack.

### 6.2 `meta-tiogapass-lf` Directory Structure

```
meta-tiogapass-lf/
├── conf/
│   ├── layer.conf
│   └── machine/
│       ├── tiogapass.conf              ← single authoritative machine conf
│       └── include/
│           └── tiogapass-flash.inc     ← flash size/layout constants
├── recipes-bsp/
│   └── u-boot/
│       └── u-boot-aspeed-sdk_%.bbappend
│           └── tiogapass.cfg           ← 64MB boot command
├── recipes-kernel/
│   └── linux/
│       └── linux-aspeed_%.bbappend
│           ├── tiogapass.cfg           ← PECI/TPM/sensor kernel config
│           └── 0001-flash-64mb.patch   ← DTS partition layout
├── recipes-phosphor/
│   ├── console/
│   │   └── obmc-console_%.bbappend     ← ttyS2 static server conf, SSH enabled
│   ├── fans/
│   │   └── phosphor-pid-control_%.bbappend ← dbus config enable
│   ├── flash/
│   │   └── phosphor-software-manager_%.bbappend
│   │       ├── bios-update
│   │       └── obmc-flash-host-bios@.service
│   ├── images/
│   │   └── tiogapass-image.inc         ← thin image customisation
│   ├── ipmi/
│   │   ├── phosphor-ipmi-config.bbappend
│   │   │   └── channel_config.json     ← KCS3 channel
│   │   └── phosphor-ipmi-ipmb_%.bbappend ← ipmb-4, ipmb-9
│   ├── sel-logger/
│   │   └── phosphor-sel-logger_git.bbappend ← delete enable
│   ├── sensors/
│   │   ├── dbus-sensors_%.bbappend     ← intelcpusensor enable
│   │   ├── phosphor-nvme_%.bbappend
│   │   │   └── nvme_config.json
│   │   └── phosphor-virtual-sensor_%.bbappend
│   │       └── virtual_sensor_config.json
│   ├── state/
│   │   └── phosphor-state-manager_%.bbappend ← requires→wants fix
│   └── users/
│       └── tiogapass-admin-user.bb
│           └── create-admin-user.sh
└── recipes-x86/
    └── chassis/
        └── x86-power-control_%.bbappend ← compile fix patch
```

### 6.3 New `tiogapass.conf`

```bitbake
#
# Tiogapass machine configuration — LF OpenBMC
# Single-socket x86 server; AST2500 BMC; 64 MB NOR flash
#

require conf/machine/include/ast2500.inc
require conf/machine/include/obmc-bsp-common.inc
require conf/machine/include/image-type/static-norootfs.inc

# Intel platform management features and packagegroup-intel-apps wiring
# (from meta-intel-openbmc/conf/machine/include/intel.inc)
require conf/machine/include/intel.inc

KMACHINE = "aspeed"
KERNEL_DEVICETREE = "aspeed/aspeed-bmc-facebook-tiogapass.dtb"

# Bootloader
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-aspeed-sdk"
PREFERRED_PROVIDER_u-boot             = "u-boot-aspeed-sdk"
PREFERRED_PROVIDER_u-boot-fw-utils    = "u-boot-fw-utils-aspeed-sdk"
UBOOT_MACHINE     = "evb-ast2500_defconfig"
UBOOT_DEVICETREE  = "ast2500-evb"

# Serial console (ttyS4 is the BMC UART; ttyS2 is the host UART)
SERIAL_CONSOLES = "57600;ttyS4"

# Host state management — x86 power sequencing via LPC/GPIO
VIRTUAL-RUNTIME_obmc-chassis-state-mgr = "x86-power-control"
VIRTUAL-RUNTIME_obmc-host-state-mgr    = "x86-power-control"

# IPMI transport: KCS is the in-band channel on this platform
PREFERRED_PROVIDER_virtual/obmc-host-ipmi-hw = "phosphor-ipmi-kcs"
MACHINE_FEATURES += "obmc-host-ipmi hw-rng"

# 64 MB NOR flash layout
FLASH_SIZE            = "65536"
FLASH_UBOOT_OFFSET    = "0"
FLASH_KERNEL_OFFSET   = "1024"
FLASH_ROFS_OFFSET     = "40960"
FLASH_RWFS_OFFSET     = "41984"

# udev rules for Aspeed peripherals
MACHINE_EXTRA_RRECOMMENDS += "udev-aspeed-vuart udev-aspeed-mtd-partitions"

# Platform compatible string (LF/OCP-aligned)
OBMC_COMPATIBLE_NAMES = "org.openbmc.Hardware.BMC.TiogaPass"

# Extra packages — hardware-specific only
OBMC_IMAGE_EXTRA_INSTALL:append = " x86-power-control"
```

---

## 7. Feature Restoration Plan

The following capabilities must be **re-enabled** in the new image. The first group was disabled by Facebook policy decisions; the second group was absent because `meta-intel-openbmc` was not activated.

### 7.1 Features Suppressed by Facebook Layers

| Feature | Disabled by | Action |
|---|---|---|
| `obmc-bmcweb` (Web UI + Redfish REST) | `phosphor-no-webui.inc` included by `facebook.inc` | Stop including; feature is on by default in `obmc-phosphor-image` |
| `obmc-net-ipmi` (IPMI LAN / IPMI 2.0 LAN channel) | `fb-phosphor-image.inc:remove` | Remove the remove; `phosphor-ipmi-net` must be present |
| `obmc-user-mgmt-ldap` | `fb-phosphor-image.inc:remove` | Remove the remove |
| SSH SOL via `obmc-console` | `obmc-console_%.bbappend PACKAGECONFIG:remove = "ssh"` | Remove this override; add `PACKAGECONFIG:append = " ssh"` in the new layer |
| `obmc-ikvm` (Remote KVM) | `facebook.inc IMAGE_FEATURES:remove` | Remove the removal; iKVM is a stated requirement |
| `obmc-settings-mgmt` | `packagegroup-obmc-apps.bbappend` in flax | Remove the removal; phosphor-settings-manager provides BMC-level settings |

### 7.2 Features Absent Because `meta-intel-openbmc` Was Inactive

These are restored automatically by adding `meta-intel-openbmc` to `bblayers.conf` (Section 6.1).

| Feature | Provided by | Effect |
|---|---|---|
| CPU hardware error monitoring | `host-error-monitor_git.bb` | PECI-based CPU/DIMM errors reported to BMC log and Redfish |
| Platform Firmware Resilience | `pfr-manager_git.bb` | Self-healing firmware recovery for corrupt BMC or host flash |
| Intel OEM IPMI commands | `intel-ipmi-oem_git.bb` | Intel OEM IPMI command library on KCS and LAN channels |
| IPMB to Management Engine | `phosphor-ipmi-ipmb_%.bbappend` | ME reachable at `/dev/ipmb-5`; power telemetry and OOB management enabled |
| Structured SEL / Redfish log routing | `rsyslog_%.bbappend` | `/var/log/ipmi_sel` and `/var/log/redfish` populated with structured events |
| Platform LED status groups | `intel-led-manager-config-native.bb` | status_ok (green), status_critical (amber), enclosure_identify all functional |
| Redfish CPU/journal log API | `bmcweb_%.bbappend` | Redfish LogService entries for CPU errors and BMC journal |
| PLT_RST warm-reset detection | `x86-power-control_%.bbappend` | Distinguishes warm resets from power cycles; improves host state accuracy |

### 7.3 `tiogapass-image.inc` (thin overlay)

```bitbake
# Hardware-specific additions only — upstream IMAGE_FEATURES are inherited from
# obmc-phosphor-image. Do NOT remove upstream features here.

# BIOS update and platform power control
OBMC_IMAGE_EXTRA_INSTALL:append = " \
    x86-power-control \
"

# Development / diagnostic tools (comment out for production build)
# OBMC_IMAGE_EXTRA_INSTALL:append = " \
#     dbus-top strace tcpdump iproute2 \
# "
```

The final image recipe in the new layer simply does:
```bitbake
require recipes-phosphor/images/obmc-phosphor-image.bb
require tiogapass-image.inc
```

---

## 8. Handling the Multi-Host Infrastructure

The entire `OBMC_HOST_INSTANCES` / `fb-consoles.inc` / dynamic `SERVER_CONFS` infrastructure in the Facebook layer is designed for multi-socket sled platforms. TiogaPass has one host. The replacement is trivial:

**New `obmc-console_%.bbappend`:**
```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# One static server config for the host UART
SRC_URI:append = " file://server.ttyS2.conf"

# Ensure SSH SOL is enabled
PACKAGECONFIG:append = " ssh concurrent-servers"
```

The `server.ttyS2.conf` file is a standard obmc-console config (four lines). This replaces the entire dynamic Python function in `fb-consoles.inc`.

---

## 9. Handling `fb-ipmi-oem`

`fb-ipmi-oem` provides Facebook-proprietary IPMI OEM commands (NetFn 0x38, command set for Facebook internal tooling). For an LF OpenBMC deployment:

- **Audit** which OEM commands are actively used by operators or automation.
- **Standard IPMI 2.0 OEM commands** that correspond to published OCP specs can be retained; the recipe is available in upstream at `github.com/openbmc/fb-ipmi-oem`.
- **Facebook-internal commands** (BIC bridge, FBTP-specific) should be evaluated; if unused in this deployment they can be dropped entirely.
- If any OEM commands are needed, the recipe can be included directly in the new layer without requiring the `meta-facebook` layer to be present.

---

## 10. Migration Execution Sequence

### Phase 1 — Create the new platform layer and activate Intel stack

1. Create `meta-tiogapass-lf/conf/layer.conf` with priority 12 (above `meta-aspeed` at 9, below nothing else).
2. Add `meta-intel-openbmc` to `bblayers.conf` (before `meta-tiogapass-lf`). Do **not** add `meta-intel-openbmc/meta-s2600wf` — that is a different machine.
3. Copy the authoritative `tiogapass.conf` (Section 6.3 above) into place, including `require conf/machine/include/intel.inc`.
4. Port kernel config fragment from `meta-facebook/meta-tiogapass/recipes-kernel/linux/linux-aspeed/tiogapass.cfg`.
5. Port flash DTS patch from `meta-flax/recipes-kernel/linux/linux-aspeed/0001-Increased-flash-chip-size.patch`.
6. Port U-Boot config from `meta-flax/recipes-bsp/u-boot/u-boot-aspeed-sdk/tiogapass.cfg`.
7. Verify `bitbake tiogapass-image` builds and boots to U-Boot prompt with correct flash layout.

### Phase 2 — Restore sensors and IPMI

8. Port `dbus-sensors_%.bbappend` (intelcpusensor).
9. Port `phosphor-nvme_%.bbappend` + `nvme_config.json`.
10. Port `phosphor-virtual-sensor_%.bbappend` + `virtual_sensor_config.json`.
11. Write `phosphor-ipmi-ipmb_%.bbappend` for all required channels (reconcile TiogaPass buses 4/9 with ME bus 5 from Intel layer — see Section 5.5).
12. Port `phosphor-ipmi-config.bbappend` + `channel_config.json` (KCS3).
13. Verify `ipmitool sdr list` and `ipmitool sensor list` return correct data over KCS.
14. Verify IPMI LAN channel responds on UDP 623 (`ipmitool -I lanplus`).
15. Verify `host-error-monitor` and `pfr-manager` services are running (`systemctl status`).

### Phase 3 — Re-enable web and console features

16. Port `obmc-console_%.bbappend` with static `server.ttyS2.conf` and SSH enabled.
17. Verify SSH SOL: `ssh -p 2200 root@<bmc-ip>` connects to host console.
18. Verify `bmcweb` serves Redfish at `https://<bmc-ip>/redfish/v1/`.
19. Verify WebUI loads at `https://<bmc-ip>/`.
20. Verify `/var/log/ipmi_sel` and `/var/log/redfish` are being populated (from Intel rsyslog config).

### Phase 4 — Re-enable user and access management

21. Port `tiogapass-admin-user.bb` (first-boot admin creation).
22. Verify LDAP/AD binding via `phosphor-user-manager`.
23. Verify Redfish AccountService creates and modifies users correctly.

### Phase 5 — Re-enable code update and KVM

24. Port `phosphor-software-manager_%.bbappend` + BIOS update script.
25. Verify BMC firmware upload via Redfish `UpdateService`.
26. Verify BIOS flash via `obmc-flash-host-bios@.service`.
27. Enable `obmc-ikvm`; verify VNC KVM session through bmcweb proxy.

### Phase 6 — Remove old layers

28. Remove `meta-facebook`, `meta-facebook/meta-tiogapass`, and `meta-flax` from `bblayers.conf`.
26. Run a full clean build.
27. Confirm no recipe uses a path from the removed layers.
28. Archive the removed layers in a `legacy/` directory or separate branch.

---

## 11. Risk Register

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Device tree upstream is still the Facebook-named DTS | Medium | Low | The DTS file name does not affect runtime; it can be renamed in a future kernel contribution |
| `x86-power-control` GPIO assignments differ from `fb-powerctrl` | Medium | High | Compare `power-config.json` against the TiogaPass schematics before removing `fb-powerctrl` |
| IPMB channel conflict between TiogaPass buses (4, 9) and Intel ME bus (5) | Medium | Medium | Write a single `phosphor-ipmi-ipmb_%.bbappend` in `meta-tiogapass-lf` that defines all channels; do not inherit blindly from either source (see Section 5.5) |
| IPMI LAN re-enablement exposes unauthenticated surface | Low | High | Confirm `phosphor-ipmi-net` uses PAM authentication (it does by default); audit firewall rules |
| `intel-ipmi-oem` and `fb-ipmi-oem` define overlapping OEM NetFn commands | Medium | Medium | With `fb-ipmi-oem` removed, only Intel OEM commands remain; audit any operator tooling that used Facebook NetFn 0x38 commands |
| `host-error-monitor` PECI dependency requires kernel PECI support | Low | Low | Kernel config already enables `CONFIG_PECI`, `CONFIG_PECI_ASPEED`, `CONFIG_PECI_CHARDEV` — no additional work needed |
| `pfr-manager` requires I2C access to a PFR device not present on TiogaPass | Medium | Low | If no PFR device is present, the service will log an error but not crash; mask it if it causes boot delays |
| iKVM frame rate is inadequate on AST2500 without Facebook's patched driver | Low | Medium | Test with upstream `obmc-ikvm`; if performance is insufficient, the feature can be deferred |
| `phosphor-settings-manager` re-enablement conflicts with `meta-flax` removal of settings | Low | Low | With `meta-flax` removed, the upstream recipe is unmodified; no conflict |
| First-boot admin password in `create-admin-user.sh` is hardcoded | High | High | Replace with a provisioning-time credential injection mechanism or a mandatory password-change-at-first-login PAM policy |

---

## 12. Layers to Remove from the Build Tree

Once Phase 6 is complete, the following layers are no longer needed and should be removed from
`bblayers.conf` and archived in a `legacy/` branch:

```
meta-facebook/                   # entire Facebook layer — remove from bblayers.conf
meta-facebook/meta-tiogapass/    # tiogapass sub-layer — remove from bblayers.conf
meta-flax/                       # flax overlay — remove from bblayers.conf
```

**Note:** `meta-ami` and `meta-common` as standalone top-level directories **do not exist** in
this repository. They were referenced only in dead BBMASK entries inside `meta-flax` and were
never in `bblayers.conf`. There is nothing to remove.

**Note:** `meta-intel-openbmc/meta-s2600wf` is **not** added to `bblayers.conf` — it remains
in the repository as a reference machine and does not interfere with the build.

Inside the surviving `meta-tiogapass-lf/`, the only Facebook-originated files that remain are
hardware configuration data (JSON sensor configs, kernel fragments, DTS patch). All Python-based
dynamic logic (`fb-consoles.inc`, `fb_get_consoles()`) is gone. All Intel-stack recipes
(`host-error-monitor`, `pfr-manager`, `intel-ipmi-oem`, etc.) come from `meta-intel-openbmc`
directly with no duplication.

---

## 13. AMI GitHub Repositories — Not Viable for AST2500

AMI's public GitHub organisation (`ocp-hm-openbmc-opf-ami`) hosts 45 repositories including
`meta-ami`, `meta-core`, and forks of bmcweb, phosphor-host-ipmid, and phosphor-networkd.
A full evaluation is documented in [HUNT_FOR_AST2500.md](HUNT_FOR_AST2500.md). Key findings:

- **`meta-ami` and `meta-core` have no AST2500 support.** AMI dropped AST2500 from their
  "OneTree" product line. These layers target AST2600/AST2700 only and cannot produce a
  TiogaPass image.
- **The dead BBMASK entries in `meta-flax`** (Section 3.7) were the conflict-resolution
  mechanism for when `meta-ami` was cloned alongside this repo. That deployment context
  no longer applies.
- **`meta-intel-openbmc` (already in-tree) is the correct Intel platform layer** for AST2500.
  AMI's `meta-core` is a newer, AST2600-only Intel BKC that does not replace it.
- **AMI's hardware-agnostic daemon forks** (bmcweb, phosphor-host-ipmid, phosphor-networkd)
  carry useful patches but should be consumed via BitBake `SRC_URI` overrides in
  `meta-tiogapass-lf`, not as git submodules. This is a Phase 3+ optimisation, not a
  prerequisite for the migration.
- **Git submodules are the wrong mechanism** for Yocto component consumption. BitBake
  manages source fetching natively via `SRC_URI` in recipes.

---

## 14. Upstreaming Opportunities

After the migration stabilises, the following items are candidates to contribute to the LF OpenBMC mainline:

| Item | Upstream target |
|---|---|
| `aspeed-bmc-facebook-tiogapass.dts` with 64 MB flash layout | `linux-aspeed` kernel tree |
| TiogaPass kernel config fragment | `meta-aspeed` |
| `tiogapass.conf` (new, clean form) | `meta-aspeed` or a new `meta-ocp-compute` layer |
| `channel_config.json` with KCS3 | `meta-phosphor` (per-platform example) |
| BIOS update service template | `meta-phosphor` (generic host SPI flash update) |
| TiogaPass-specific IPMB channel JSON | `meta-intel-openbmc/meta-common` (alongside the S2600WF example) |

Contributing these upstream eliminates the need for a separate platform layer for the portions that are SoC-generic, reducing the long-term maintenance burden to near zero.

---

## 15. Summary

| Action | Files affected | Effect |
|---|---|---|
| Add `meta-intel-openbmc` to `bblayers.conf` | `bblayers.conf` | Activates host-error-monitor, pfr-manager, intel-ipmi-oem, LED config, structured log routing |
| Create `meta-tiogapass-lf` | New layer (~25 files) | Single source of truth for all platform-specific customisation |
| Include `intel.inc` in `tiogapass.conf` | `tiogapass.conf` | Wires `packagegroup-intel-apps` as the virtual provider for chassis/fan/flash/system management |
| Remove `facebook.inc` inheritance chain | `tiogapass.conf` | Restores upstream packagegroup system; eliminates multi-host scaffolding |
| Remove `fb-phosphor-image.inc` | Image recipe | Restores IPMI LAN, LDAP, WebUI |
| Remove `obmc-console` SSH removal | Console bbappend | Restores SSH SOL with static single-host config |
| Remove `IMAGE_FEATURES:remove = "obmc-ikvm"` | Machine conf | Restores KVM |
| Discard `meta-flax` BBMASK block | Dead code — no files to change | Removes 40+ pattern matches that pointed to non-existent paths |
| Port 14 hardware-specific items | See Section 4 | Preserves all hardware support: flash layout, PECI, NVMe, IPMB, BIOS update |
| Remove 3 layers from `bblayers.conf` | `bblayers.conf` | Clean LF OpenBMC dependency graph — meta-facebook, meta-tiogapass, meta-flax |
| No action needed for meta-ami / meta-common | — | These directories do not exist in this repository; BBMASK references to them were already dead |
