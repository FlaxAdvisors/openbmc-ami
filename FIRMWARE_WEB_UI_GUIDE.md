# TiogaPass Firmware Update — Web UI Guide

This guide covers the step-by-step Web UI interactions for updating BMC and BIOS
firmware on the TiogaPass platform using the MegaRAC OneTree web interface.

All field names, button labels, section titles, and modal text in this guide
are taken directly from the UI source — they match exactly what appears on screen.

Default credentials: **root** / **0penBmc**

---

## Table of Contents

1. [Logging In](#1-logging-in)
2. [Navigating to the Firmware Page](#2-navigating-to-the-firmware-page)
3. [Firmware Page Layout](#3-firmware-page-layout)
4. [BMC Firmware Update](#4-bmc-firmware-update)
5. [BIOS Firmware Update](#5-bios-firmware-update)
6. [Switching BMC Running / Backup Images](#6-switching-bmc-running--backup-images)
7. [Status Messages Reference](#7-status-messages-reference)

---

## 1. Logging In

1. Open a browser and navigate to `https://<bmc-ip>`
2. Accept the self-signed TLS certificate warning
3. On the login screen enter:
   - **Username**: `root`
   - **Password**: `0penBmc`
4. Click **Log in**

> Only **Administrator** role accounts can perform firmware updates.
> Operator and ReadOnly accounts will see the Update Firmware form disabled.

---

## 2. Navigating to the Firmware Page

The left-hand sidebar contains the main navigation. Click **Operations** to expand it.

The **Operations** submenu appears in this order:

| Position | Menu Item |
|----------|-----------|
| 1 | Server Power Operations |
| 2 | Serial Over LAN |
| 3 | KVM |
| 4 | Virtual Media |
| 5 | Reboot BMC |
| **6** | **Firmware** ← firmware updates |
| 7 | Backup and Restore |
| 8 | Tasks |
| 9 | Preserve Configuration |
| 10 | Factory Default |

Click **Firmware** (item 6). The page title **Firmware** appears at the top.

---

## 3. Firmware Page Layout

The Firmware page is divided into four visual areas from top to bottom:

```
┌─────────────────────────────────────────────────────────────┐
│  [!] Alert banner (only visible if server must be off)      │
├─────────────────────────────────────────────────────────────┤
│  BMC                                                        │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │  Running Image   │  │  Backup Image    │                │
│  │  Version: x.y.z  │  │  Version: x.y.z  │                │
│  │  (booted from    │  │  [Switch to      │                │
│  │   Active Image)  │  │   running]       │                │
│  └──────────────────┘  └──────────────────┘                │
├─────────────────────────────────────────────────────────────┤
│  Host                                                       │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────┐ │
│  │  Running Image   │  │  Backup Image    │  │  BIOS    │ │
│  │  Version: x.y.z  │  │  Version: x.y.z  │  │  Clear   │ │
│  │                  │  │                  │  │  Config  │ │
│  │                  │  │                  │  │  toggle  │ │
│  └──────────────────┘  └──────────────────┘  └──────────┘ │
├─────────────────────────────────────────────────────────────┤
│  Update Firmware                                            │
│  ┌─────────────────────────────────────┐                   │
│  │  Image File  [Choose File]          │                   │
│  │                                     │                   │
│  │  [↻ Start Update]                   │                   │
│  └─────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

### Alert banner (conditional)

A yellow warning banner appears at the top if the server must be powered off
before updating. It reads:

> **Server must be Powered Off:** Update Firmware
> [View Server Power Operations]

While this banner is visible and the server is on, the **Start Update** button
is greyed out and cannot be clicked.

### BMC section

Section title: **BMC**

| Card | Label | Content |
|------|-------|---------|
| Left | **Running Image** | **Version:** current running version string. Below the version: *(Running Image is booted from Active Image.)* or *(Running Image is booted from Backup Image.)* |
| Right | **Backup Image** | **Version:** backup version string (or `--` if none). **[Switch to running]** button (if backup switching is enabled) |

### Host section

Section title: **Host**

| Card | Label | Content |
|------|-------|---------|
| Left | **Running Image** | **Version:** current BIOS version string (or `--` if not detected) |
| Middle | **Backup Image** | **Version:** backup BIOS version string (or `--`) |
| Right | **BIOS Clear Configuration** | Toggle switch — **Enabled** or **Disabled**. When enabled, BIOS settings are reset to factory defaults during the next BIOS update. Set this before uploading the BIOS tar. |

### Update Firmware section

Section title: **Update Firmware**

| Field | Type | Description |
|-------|------|-------------|
| **Image File** | File chooser | Click **Choose File** to open a system file dialog. Select either the BMC update tar or the BIOS update tar — the same field accepts both. The MANIFEST `purpose` inside the tar tells the BMC which type of update to perform. |
| **Start Update** | Primary button (blue) | Submits the upload. Disabled (greyed out) if: no file is selected, the user is not Administrator, or (if server-off is required) the host is powered on. |

> If a **File Source** radio group is visible (**Workstation** / **TFTP Server**),
> select **Workstation** when uploading a local file.
> The TFTP option requires a reachable TFTP server accessible from the BMC.

---

## 4. BMC Firmware Update

### Prerequisites

- You are logged in as **Administrator**
- You have `tiogapass-bmc-update.tar` (built with `./make-update-tar.sh`)
- The host may be on or off — BMC updates do not require the host to be powered off

### Steps

**Step 1 — Navigate to the Firmware page**

Operations → **Firmware**

**Step 2 — Note the current running version**

In the **BMC** section, read the **Running Image** card:

```
Running Image
Version: flax-onetree-1.0.0-202604090356
(Running Image is booted from Active Image.)
```

**Step 3 — Select the update file**

In the **Update Firmware** section:

1. Click **Choose File** (next to the **Image File** label)
2. In the system file dialog, navigate to and select `tiogapass-bmc-update.tar`
3. The file name appears next to the button confirming selection

**Step 4 — Start the update**

Click **Start Update**

A confirmation modal appears:

```
┌─── Update Firmware ────────────────────────────────────────┐
│                                                             │
│  The new image will be uploaded and activated. After        │
│  that, the BMC or host will reboot automatically to         │
│  run from the new image.                                    │
│                                                             │
│                      [Cancel]  [Start Update]              │
└─────────────────────────────────────────────────────────────┘
```

Click **Start Update** to confirm, or **Cancel** to abort.

**Step 5 — Wait for upload and flash**

After confirming, a blue info toast appears at the top-right:

> **Update Started**
> Wait for the firmware update notification before making any changes.

A progress bar appears below the form, animating from 0% to 95% as the
BMC is flashed (~2 minutes). The page overlays with a dim mask during this time.

**Step 6 — BMC reboot**

When flashing completes, a modal dialog appears:

```
┌─── Success ────────────────────────────────────────────────┐
│                                                             │
│  BMC Firmware Reset has been called. Close the current      │
│  session and open a new session after a couple of minutes.  │
│                                                             │
│                                              [OK]           │
└─────────────────────────────────────────────────────────────┘
```

Click **OK**. The page goes dark (overlay remains).

**Step 7 — Reconnect**

Wait approximately 90 seconds for the BMC to reboot, then:

1. Close the current browser tab or navigate back to `https://<bmc-ip>`
2. Log in again with `root` / `0penBmc`
3. Go to Operations → Firmware
4. Verify the **Running Image** version in the **BMC** section shows the new version

---

## 5. BIOS Firmware Update

### Prerequisites

- You are logged in as **Administrator**
- You have `tiogapass-bios-update.tar` (built with `./make-update-tar.sh bios <bios.bin>`)
- **The host server must be powered off** before starting a BIOS update

### Steps

**Step 1 — Power off the host**

If the host is running, go to Operations → **Server Power Operations** and
initiate a graceful or forced power off. Wait for the power state to show **Off**.

Return to Operations → **Firmware**.

If the host was on, the yellow alert banner at the top of the page will now
be gone and the **Start Update** button will be enabled.

**Step 2 — Note the current BIOS version**

In the **Host** section, read the **Running Image** card:

```
Running Image
Version: 2.07.0
```

If the version shows `--` it means the BMC has not yet received SMBIOS data
from the host (host must POST at least once after BMC boot for BIOS version
to appear).

**Step 3 — Set BIOS Clear Configuration (optional)**

In the **Host** section, the third card is **BIOS Clear Configuration**:

```
BIOS Clear Configuration
[toggle]  Disabled
```

- Leave as **Disabled** (default) to preserve existing BIOS settings
- Switch to **Enabled** if you want BIOS settings reset to factory defaults
  during this update

A success toast confirms the toggle action:

> Successfully enabled Clear Configuration.  
> — or —  
> Successfully disabled Clear Configuration.

**Step 4 — Select the update file**

In the **Update Firmware** section:

1. Click **Choose File** (next to the **Image File** label)
2. Select `tiogapass-bios-update.tar`
3. The file name appears next to the button confirming selection

**Step 5 — Start the update**

Click **Start Update**

The same confirmation modal appears:

```
┌─── Update Firmware ────────────────────────────────────────┐
│                                                             │
│  The new image will be uploaded and activated. After        │
│  that, the BMC or host will reboot automatically to         │
│  run from the new image.                                    │
│                                                             │
│                      [Cancel]  [Start Update]              │
└─────────────────────────────────────────────────────────────┘
```

Click **Start Update** to confirm.

**Step 6 — Wait for upload and flash**

The info toast appears:

> **Update Started**
> Wait for the firmware update notification before making any changes.

A progress bar tracks the upload and activation. BIOS flash time depends on
the ROM size (typically 5–10 minutes).

**Step 7 — Completion**

When done, a green success toast appears:

> Successfully updated the Firmware.

Unlike a BMC update, the BMC itself does not reboot after a BIOS update.

**Step 8 — Power on the host**

Go to Operations → **Server Power Operations** and power the host on.
The new BIOS takes effect on the next POST.

**Step 9 — Verify**

After the host completes POST, return to Operations → Firmware. The
**Host** → **Running Image** → **Version** field should reflect the new
BIOS version (populated once the host sends SMBIOS data to the BMC).

---

## 6. Switching BMC Running / Backup Images

If a backup BMC image is present (shown in the **BMC** → **Backup Image** card
with a version other than `--`), it can be promoted to become the running image
without uploading a new file.

**Step 1** — In the **BMC** section, click **Switch to running** (link button
below the **Backup Image** version).

A confirmation modal appears:

```
┌─── Switch Images ──────────────────────────────────────────┐
│                                                             │
│  A BMC reboot is required to run the backup image. The      │
│  application might be unresponsive during this time.        │
│                                                             │
│  Are you sure you want to switch the backup image           │
│  (flax-onetree-1.0.0-20260115...)?                         │
│                                                             │
│                      [Cancel]  [OK]                        │
└─────────────────────────────────────────────────────────────┘
```

**Step 2** — Click **OK**.

An info toast confirms:

> **Reboot Started**
> Successfully started rebooting from backup image.

The BMC reboots (~90 seconds). After reconnecting, the **Running Image** card
will show the former backup version with *(Running Image is booted from Backup Image.)*.

---

## 7. Status Messages Reference

### Toasts (top-right corner, auto-dismiss)

| Colour | Title | Message | Meaning |
|--------|-------|---------|---------|
| Blue | Update Started | Wait for the firmware update notification before making any changes. | File uploaded; flash in progress |
| Green | *(none)* | Successfully updated the Firmware. | BIOS update complete |
| Green | *(none)* | Successfully enabled Clear Configuration. | BIOS clear config toggle on |
| Green | *(none)* | Successfully disabled Clear Configuration. | BIOS clear config toggle off |
| Green | Reboot Started | Successfully started rebooting from backup image. | BMC image switch initiated |
| Yellow | Verify Switch | Refresh the application to verify the running and backup images switched. | Switch timed out — reload to check |
| Red | *(none)* | Error in starting Firmware Update. | Upload or activation failed — see §Troubleshooting in BIOS_AND_BMC_UPDATE_GUIDE.md |
| Red | *(none)* | Error in switching running and backup images. | httpPushUriBusy stuck — see §7.1 of BIOS_AND_BMC_UPDATE_GUIDE.md |

### Modal dialogs

| Trigger | Title | Key text |
|---------|-------|----------|
| Click Start Update | Update Firmware | "The new image will be uploaded and activated. After that, the BMC or host will reboot automatically…" |
| BMC flash complete | Success | "BMC Firmware Reset has been called. Close the current session and open a new session after a couple of minutes." |
| Click Switch to running | Switch Images | "A BMC reboot is required to run the backup image…" |

### Alert banner

| Text | Meaning |
|------|---------|
| "Server must be Powered Off: Update Firmware" | Host is powered on; Start Update is disabled until host is off |
| "Server Power Operation is in progress." | A power action is running; wait before attempting update |
