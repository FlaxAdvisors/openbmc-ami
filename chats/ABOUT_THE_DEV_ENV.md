# OpenBMC-AMI Development Environment Guide

A practical reference for developers new to Yocto, BitBake, and OpenBMC.

---

## Table of Contents

1. [What Is OpenBMC?](#what-is-openbmc)
2. [The Build System Stack](#the-build-system-stack)
3. [Core Yocto Concepts](#core-yocto-concepts)
4. [Repository Layout](#repository-layout)
5. [Layers in This Build](#layers-in-this-build)
6. [Build Flow: What Actually Happens](#build-flow-what-actually-happens)
7. [Key Directories After a Build](#key-directories-after-a-build)
8. [Common BitBake Commands](#common-bitbake-commands)
9. [VSCode BitBake Extension](#vscode-bitbake-extension)
10. [First Build Checklist](#first-build-checklist)

---

## What Is OpenBMC?

A BMC (Baseboard Management Controller) is a small, independent microcontroller embedded on a server motherboard. It runs even when the main server is powered off and handles:

- Remote power control (power on/off/cycle/reset)
- Hardware monitoring (temperatures, fan speeds, voltages)
- IPMI and Redfish management interfaces
- KVM-over-IP (remote console)
- Firmware update

OpenBMC is an open-source Linux distribution specifically for BMCs. It uses the same board (in this repo: the **TiogaPass** platform from Meta/Facebook, using an **Aspeed AST2500** BMC SoC) but replaces proprietary firmware with a Linux-based, customizable stack.

**openbmc-ami** is AMI's fork/integration of OpenBMC, tracking the upstream OpenBMC project with additional hardware support and patches.

---

## The Build System Stack

```
┌─────────────────────────────────────────────────────┐
│  OpenEmbedded (OE) - the core build framework       │
│  ┌───────────────────────────────────────────────┐  │
│  │  Yocto Project - OE + reference distro (Poky) │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  BitBake - the task execution engine    │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

- **OpenEmbedded (OE)**: The metadata framework. Defines how to describe software packages (recipes), how layers work, and the general build model.
- **Yocto Project**: An OE-compatible Linux Foundation project. Provides **Poky** (a reference distribution) and tools. When people say "Yocto build," they usually mean an OE build using Yocto's tools.
- **BitBake**: The actual build tool (think: `make` but for embedded Linux distributions). It reads recipe files, resolves dependencies, and runs tasks.
- **Poky**: The reference distribution. In this repo, `poky/` contains BitBake itself and the base `meta` layer.

---

## Core Yocto Concepts

### Recipes (`.bb` files)

A recipe describes how to build one software package:
- Where to fetch the source (git, tarball, local)
- How to configure it (`./configure`, `cmake`, etc.)
- How to compile it
- What files go into the final image

Example: `meta-phosphor/recipes-phosphor/dbus/phosphor-dbus-interfaces_git.bb`

### Classes (`.bbclass` files)

Reusable build logic that recipes can inherit. Like a base class in OOP.

Example: `inherit cmake` tells BitBake this recipe uses CMake.

### Append Files (`.bbappend` files)

Extend or override a recipe from a different layer without modifying the original. The primary customization mechanism.

Example: `meta-facebook/meta-tiogapass/recipes-bsp/u-boot/u-boot-aspeed-sdk_%.bbappend` adds TiogaPass-specific U-Boot patches on top of the base U-Boot recipe.

### Layers (`meta-*` directories)

A layer is a collection of recipes, classes, and configuration grouped by purpose. Layers stack on top of each other - later layers can override earlier ones.

Layer priority determines override order (higher number = higher priority).

### The `MACHINE` Variable

Tells BitBake what hardware target to build for. Set to `tiogapass` in `build/tiogapass/conf/local.conf`. Different machines have different:
- CPU architecture
- Bootloader configuration
- Device trees
- Flash layout
- Peripheral support

### Images

A BitBake "image" recipe is a special recipe that assembles a complete root filesystem from individual packages.

`obmc-phosphor-image` is the standard OpenBMC image: it includes the kernel, U-Boot bootloader, and all the phosphor management daemons.

### Distro

The distribution configuration. OpenBMC uses `openbmc-phosphor` as its distro, which sets global policies like init system (systemd), package format (ipk), C library (glibc), etc.

### `DISTRO_FEATURES` and `MACHINE_FEATURES`

Feature flags that control which optional components get compiled in. For example, `DISTRO_FEATURES += "ipv6"` enables IPv6 support across all packages that respect it.

### `sstate-cache` (Shared State Cache)

BitBake's build acceleration mechanism. After building a component, it saves a snapshot (the "sstate"). On subsequent builds (or across machines sharing a cache), it can restore from cache instead of rebuilding. This turns a 6-hour rebuild into a 5-minute one.

### `tmp/` Directory

Where BitBake puts everything during a build:
- `tmp/work/` - Per-recipe build directories (source, patches, objects)
- `tmp/deploy/images/` - **Final output images** (flash images, kernel, etc.)
- `tmp/sysroots/` - Staging area for cross-compilation

---

## Repository Layout

```
openbmc-ami/
├── setup                    ← Source this to initialize the build env
├── oe-init-build-env        ← Symlink to poky/oe-init-build-env (called by setup)
├── bitbake/                 ← Symlink to poky/bitbake (the bitbake tool)
├── meta/                    ← Symlink to poky/meta (Yocto base layer)
├── scripts/                 ← Symlink to poky/scripts (helper scripts)
├── poky/                    ← The Yocto/Poky base (BitBake + base layers)
├── meta-openembedded/       ← OE community layers (networking, Python, etc.)
├── meta-phosphor/           ← OpenBMC core layer (phosphor daemons, image def)
├── meta-aspeed/             ← Aspeed SoC BSP layer (AST2400/2500/2600)
├── meta-facebook/           ← Facebook/Meta platform layer
│   └── meta-tiogapass/      ← TiogaPass-specific recipes and config
├── meta-flax/               ← AMI/Flax customizations
├── meta-arm/                ← ARM architecture support
├── meta-security/           ← Security hardening recipes
├── meta-*/                  ← Many other hardware vendor layers
└── build/
    └── tiogapass/           ← Build output directory (created by `. setup tiogapass`)
        ├── conf/
        │   ├── local.conf   ← Your build settings (MACHINE, parallel jobs, etc.)
        │   └── bblayers.conf ← Which layers are active for this build
        ├── tmp/             ← Build artifacts (LARGE: 20-50GB when built)
        ├── cache/           ← BitBake's parse cache
        ├── sstate-cache/    ← Shared state cache (speeds up rebuilds)
        └── downloads/       ← Downloaded source archives (shared across builds)
```

---

## Layers in This Build

The active layers for the TiogaPass build (from `build/tiogapass/conf/bblayers.conf`), in priority order:

| Layer | Purpose |
|-------|---------|
| `meta` (poky) | Base OE/Yocto layer: toolchain, core utilities |
| `meta-openembedded/meta-oe` | Extended OE recipes: libraries, tools |
| `meta-openembedded/meta-networking` | Network-related packages |
| `meta-openembedded/meta-python` | Python packages |
| `meta-phosphor` | OpenBMC core: IPMI, Redfish, D-Bus interfaces, phosphor daemons |
| `meta-aspeed` | Aspeed AST2500 SoC support: kernel patches, U-Boot, hardware drivers |
| `meta-facebook` | Meta/Facebook common BMC recipes |
| `meta-facebook/meta-tiogapass` | **TiogaPass machine-specific config** (highest priority) |

---

## Build Flow: What Actually Happens

### 1. Environment Initialization

```bash
. setup tiogapass
```

This runs `oe-init-build-env` which:
- Sets `PATH` to include BitBake's `bin/` directory
- Sets `BUILDDIR` to `build/tiogapass/`
- Sets shell variables BitBake needs
- Changes your working directory to `build/tiogapass/`

**This must be re-sourced in every new terminal session** before using `bitbake`.

### 2. Parsing Phase

When you run `bitbake obmc-phosphor-image`, BitBake first:
- Reads `bblayers.conf` to find all active layers
- Parses every `.bb`, `.bbclass`, `.inc`, and `.conf` file in all layers
- Builds a complete dependency graph of all tasks
- This can take a few minutes on first run (cached after that)

### 3. Task Execution

BitBake breaks each recipe into tasks:
- `do_fetch` - Download source code
- `do_unpack` - Extract archives
- `do_patch` - Apply patches
- `do_configure` - Run `./configure` or `cmake`
- `do_compile` - Run `make`
- `do_install` - Install files to staging area
- `do_package` - Split into individual packages
- `do_rootfs` (image only) - Assemble the root filesystem
- `do_image` (image only) - Create the final flash image

BitBake runs tasks in parallel across recipes where dependencies allow.

### 4. Output

Final images land in `build/tiogapass/tmp/deploy/images/tiogapass/`:
- `flash-tiogapass` - Complete flash image to program the BMC
- `obmc-phosphor-image-tiogapass.static.mtd` - Same, named differently
- `fitImage` - Kernel + device tree (FIT format for U-Boot)
- Various intermediate files

---

## Key Directories After a Build

```
build/tiogapass/
├── tmp/deploy/images/tiogapass/    ← FINAL IMAGES (what you flash)
├── tmp/work/                       ← Per-recipe build dirs (useful for debugging)
│   └── arm926ejste-openbmc-linux-gnueabi/  ← ARM architecture work dirs
│       └── <recipe-name>/<version>/
│           ├── source/             ← Extracted + patched source
│           ├── build/              ← Compiled objects
│           └── image/              ← Installed files
├── tmp/log/                        ← Build logs (task failures show up here)
├── sstate-cache/                   ← Build cache (safe to delete to force rebuild)
└── downloads/                      ← Source tarballs (keep this; takes long to re-download)
```

---

## Common BitBake Commands

All these require the environment to be initialized first (`. setup tiogapass`).

```bash
# Build the complete BMC image
bitbake obmc-phosphor-image

# Build a single package (faster iteration)
bitbake phosphor-ipmi-host

# Force rebuild a specific task for a package
bitbake -c compile -f phosphor-ipmi-host

# Force rebuild everything for a package from scratch
bitbake -c cleansstate phosphor-ipmi-host && bitbake phosphor-ipmi-host

# Show what tasks a recipe has
bitbake -c listtasks phosphor-ipmi-host

# Open devshell for a recipe (gives you a shell with the cross-compile env set up)
bitbake -c devshell phosphor-ipmi-host

# Show the value of a variable (extremely useful for debugging)
bitbake -e phosphor-ipmi-host | grep ^SRC_URI

# Find which recipe provides a package
bitbake -s | grep phosphor

# Show layer information
bitbake-layers show-layers

# Find where a recipe is defined (and which layer overrides it)
bitbake-layers show-recipes phosphor-ipmi-host

# Check for common mistakes
bitbake-layers show-overlayed
```

---

## VSCode BitBake Extension

The workspace is **already configured** for the [Yocto BitBake VSCode extension](https://marketplace.visualstudio.com/items?itemName=yocto-project.yocto-bitbake).

### Install the Extension

VSCode should have prompted you to install the recommended extension (`yocto-project.yocto-bitbake`) when you opened this workspace. If not, install it via:
- `Ctrl+Shift+X` → search "Yocto BitBake" → Install

### What the Extension Provides

- **Syntax highlighting** for `.bb`, `.bbappend`, `.bbclass`, `.inc`, `.conf` files
- **Go-to-definition** for recipe variables and includes
- **Hover documentation** on BitBake variables
- **Recipe completion** suggestions
- A **BitBake panel** in the sidebar for running builds (optional)

### Existing Configuration (`.vscode/settings.json`)

The workspace settings are already correct for TiogaPass:

```json
"bitbake.pathToBitbakeFolder": "${workspaceFolder}/bitbake",
"bitbake.pathToEnvScript":    "${workspaceFolder}/oe-init-build-env",
"bitbake.pathToBuildFolder":  "${workspaceFolder}/build/tiogapass"
```

### Language Server Activation

The extension's language server (which powers go-to-definition, etc.) needs to connect to a running BitBake server. For initial development, **syntax highlighting works immediately** without any further setup. The Language Server feature requires the environment to be initialized; follow the extension's prompts in VSCode if you want to enable it.

### Note on File Excludes

The `.vscode/settings.json` already excludes large build directories (`tmp/`, `sstate-cache/`, `downloads/`) from VSCode's file watcher. This is important - these directories contain millions of files and would make VSCode unusable without exclusions.

---

## First Build Checklist

You have already:
- [x] Installed build prerequisites
- [x] Cloned the repository
- [x] Run `. setup tiogapass` (the `build/tiogapass/conf/` directory exists)

### Before Running the Build

**Disk space**: ~50-80 GB needed. You have ~82 GB available. It will be close - consider if you need space for anything else.

**RAM**: 8 GB minimum, 16 GB recommended for parallel builds.

**CPU**: More cores = faster build. Check `build/tiogapass/conf/local.conf` for `BB_NUMBER_THREADS` and `PARALLEL_MAKE` if you want to tune parallelism.

### Running the Build

In the terminal where you ran `. setup tiogapass` (or re-source it in a new terminal):

```bash
# If in a new terminal session:
cd /home/vagrant/openbmc-ami
. setup tiogapass          # re-initializes env and cd's to build/tiogapass/

# Then build:
bitbake obmc-phosphor-image
```

Yes, that one command is the complete build. BitBake handles everything else.

**Expect the first build to take 3-8 hours** depending on your CPU core count and download speed. Subsequent builds are much faster due to sstate-cache.

### Monitoring the Build

BitBake shows a progress UI in the terminal. Logs for failures are in:
```
build/tiogapass/tmp/work/<arch>/<recipe>/<version>/temp/log.do_<taskname>
```

Or use:
```bash
bitbake obmc-phosphor-image 2>&1 | tee build.log
```

### Build Output

When complete, the flash image will be at:
```
build/tiogapass/tmp/deploy/images/tiogapass/flash-tiogapass
```

This is the binary you write to the BMC's flash chip.
