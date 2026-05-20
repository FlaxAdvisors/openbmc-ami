# TiogaPass BMC & BIOS Firmware Update Guide

Audience: system administrators applying firmware updates to a TiogaPass server.

Default BMC credentials: `root` / `0penBmc`
Replace `<bmc-ip>` with the management IP of the BMC.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Update File Format](#2-update-file-format)
3. [Redfish Session Management](#3-redfish-session-management)
4. [Active BMC Firmware Update](#4-active-bmc-firmware-update)
   - 4.1 [Web UI](#41-web-ui)
   - 4.2 [Redfish — Basic Auth](#42-redfish--basic-auth)
   - 4.3 [Redfish — Session Token](#43-redfish--session-token)
   - 4.4 [Monitoring Progress](#44-monitoring-progress)
5. [BIOS Firmware Update](#5-bios-firmware-update)
   - 5.1 [Web UI](#51-web-ui)
   - 5.2 [Redfish — Basic Auth](#52-redfish--basic-auth)
   - 5.3 [Redfish — Session Token](#53-redfish--session-token)
6. [Update Image on Backup EEPROM](#6-update-image-on-backup-eeprom)
7. [Checking Active Firmware Versions](#7-checking-active-firmware-versions)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Prerequisites

- Network access to the BMC management IP
- The BMC's TLS certificate is self-signed — pass `-k` to curl or import the certificate into your trust store
- `curl` ≥ 7.58 (multipart form support is required for BIOS uploads)
- The update tar files supplied by the vendor:
  - `tiogapass-bmc-update.tar` — for the active BMC firmware (and the backup BMC chip)
  - `tiogapass-bios-update.tar` — for the host BIOS

---

## 2. Update File Format

Both update files are uncompressed tar archives that contain a firmware image plus a `MANIFEST` text file. There is no extraction or unpacking step on the administrator side — upload the `.tar` file as-is. The BMC verifies the manifest and rejects mismatched or corrupted payloads automatically.

A BMC update tar must declare `CompatibleName=com.meta.Hardware.BMC.Model.TiogaPass`; if it does not, the BMC will reject the upload. The tar version string shown in the Web UI and Redfish inventory comes from the manifest.

---

## 3. Redfish Session Management

Using a session token is preferred over repeating credentials in every request, especially for multi-step procedures such as the BIOS update.

### Create a session

```bash
TOKEN=$(curl -sk -X POST https://<bmc-ip>/redfish/v1/SessionService/Sessions \
  -H "Content-Type: application/json" \
  -d '{"UserName":"root","Password":"0penBmc"}' \
  -D /dev/stderr 2>&1 >/dev/null | grep -i x-auth-token | awk '{print $2}' | tr -d '\r')
```

### Verify the session

```bash
curl -sk -H "X-Auth-Token: $TOKEN" \
  https://<bmc-ip>/redfish/v1/SessionService/Sessions | python3 -m json.tool
```

### Delete the session (logout)

```bash
curl -sk -X DELETE -H "X-Auth-Token: $TOKEN" \
  https://<bmc-ip>/redfish/v1/SessionService/Sessions/<session-id>
```

---

## 4. Active BMC Firmware Update

A BMC firmware update is uploaded as a simple binary POST. The BMC validates the image, flashes it, then reboots automatically. The total time is roughly **3–5 minutes**: about 2 minutes of flashing followed by a reboot.

The persistent settings partition (network configuration, users, etc.) is preserved across a BMC firmware update.

### 4.1 Web UI

1. Navigate to `https://<bmc-ip>` and log in
2. Go to **Settings → Firmware**
3. Under **BMC firmware**, click **Choose file** and select `tiogapass-bmc-update.tar`
4. Click **Start update**
5. A progress bar appears; the BMC reboots automatically when flashing completes
6. Wait for the BMC to come back online; the login page will reload

If the progress bar shows "Error in switching running and backup images", see [Troubleshooting §8.1](#81-update-fails-immediately-or-shows-error-in-switching-running-and-backup-images).

### 4.2 Redfish — Basic Auth

```bash
curl -k -u root:0penBmc \
  -X POST https://<bmc-ip>/redfish/v1/UpdateService/update \
  -H "Content-Type: application/octet-stream" \
  --data-binary @tiogapass-bmc-update.tar
```

Expected response (HTTP 200):

```json
{
  "@odata.id": "/redfish/v1/TaskService/Tasks/0",
  "@odata.type": "#Task.v1_4_3.Task",
  "Id": "0",
  "TaskState": "Running",
  "TaskStatus": "OK"
}
```

### 4.3 Redfish — Session Token

```bash
# Step 1: create session (see §3)
TOKEN=$(curl -sk -X POST https://<bmc-ip>/redfish/v1/SessionService/Sessions \
  -H "Content-Type: application/json" \
  -d '{"UserName":"root","Password":"0penBmc"}' \
  -D /dev/stderr 2>&1 >/dev/null | grep -i x-auth-token | awk '{print $2}' | tr -d '\r')

# Step 2: upload the BMC image
curl -k -X POST https://<bmc-ip>/redfish/v1/UpdateService/update \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @tiogapass-bmc-update.tar
```

### 4.4 Monitoring Progress

The POST returns a Task `@odata.id` like `/redfish/v1/TaskService/Tasks/1`. Poll that URL to watch progress:

```bash
curl -sk -u root:0penBmc \
  https://<bmc-ip>/redfish/v1/TaskService/Tasks/1 | python3 -m json.tool
```

`TaskState` transitions `Running` → `Completed`, after which the BMC reboots into the new image. The Task ID in the URL matches whatever the POST response returned — it is not always `1`.

---

## 5. BIOS Firmware Update

The BIOS update uses a **multipart POST** with the `UpdateParameters` part. The host server must be **powered off** before the update is started.

A BIOS update typically takes 5–10 minutes. The new BIOS takes effect on the next host power-on.

### 5.1 Web UI

1. Navigate to `https://<bmc-ip>` and log in
2. **Power off the host** if it is running (Operations → Server power → Power off)
3. Go to **Settings → Firmware**
4. Under **Host firmware**, click **Choose file** and select `tiogapass-bios-update.tar`
5. Click **Start update**
6. Wait for the update to complete (5–10 minutes)
7. Power the host back on — the new BIOS takes effect on the next POST

If the update page shows an error and does not recover, see [Troubleshooting §8.2](#82-bios-update-failed-and-the-ui-will-not-let-you-retry).

### 5.2 Redfish — Basic Auth

```bash
curl -k -u root:0penBmc \
  -X POST https://<bmc-ip>/redfish/v1/UpdateService/update \
  -F "UpdateFile=@tiogapass-bios-update.tar;type=application/octet-stream" \
  -F 'UpdateParameters={"Targets":["/redfish/v1/Managers/bmc"],"@Redfish.OperationApplyTime":"Immediate"};type=application/json'
```

> The `Targets` value `/redfish/v1/Managers/bmc` is required by the BMC's multipart parser. It does not mean the BMC is being updated — the BIOS routing is determined by the manifest inside the tar.

### 5.3 Redfish — Session Token

```bash
# Step 1: create session (see §3)
TOKEN=$(curl -sk -X POST https://<bmc-ip>/redfish/v1/SessionService/Sessions \
  -H "Content-Type: application/json" \
  -d '{"UserName":"root","Password":"0penBmc"}' \
  -D /dev/stderr 2>&1 >/dev/null | grep -i x-auth-token | awk '{print $2}' | tr -d '\r')

# Step 2: power off the host (if running)
curl -sk -X POST https://<bmc-ip>/redfish/v1/Systems/system/Actions/ComputerSystem.Reset \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ResetType":"ForceOff"}'

# Step 3: wait for host off (poll)
until curl -sk -H "X-Auth-Token: $TOKEN" \
    https://<bmc-ip>/redfish/v1/Systems/system \
    | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d['PowerState']=='Off' else 1)"; do
  echo "Waiting for host off..."; sleep 5
done

# Step 4: upload the BIOS image
curl -k -X POST https://<bmc-ip>/redfish/v1/UpdateService/update \
  -H "X-Auth-Token: $TOKEN" \
  -F "UpdateFile=@tiogapass-bios-update.tar;type=application/octet-stream" \
  -F 'UpdateParameters={"Targets":["/redfish/v1/Managers/bmc"],"@Redfish.OperationApplyTime":"Immediate"};type=application/json'

# Step 5: power on (after update completes)
curl -sk -X POST https://<bmc-ip>/redfish/v1/Systems/system/Actions/ComputerSystem.Reset \
  -H "X-Auth-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ResetType":"On"}'
```

---

## 6. Update Image on Backup EEPROM

TiogaPass has an optional second SPI flash chip (the **backup EEPROM**) installed in a secondary socket on the motherboard. The backup EEPROM holds a complete, ready-to-boot BMC image that can be used to recover the system if the primary chip becomes corrupted.

The backup EEPROM is **never selected automatically** — it cannot be activated through the Web UI, Redfish, or any software switch. Recovery is a **hardware procedure**: the BMC is powered down, the backup chip is physically swapped into the primary socket, and the system is powered back up. Contact your hardware vendor for the chip-swap instructions specific to your chassis.

What administrators **can** do at any time is keep the image on the backup EEPROM up to date so that a future swap leaves the BMC running a known-good current firmware rather than something stale.

> Updating the backup EEPROM is not exposed in the Web UI or Redfish API. It is performed from the BMC shell over SSH. The same `tiogapass-bmc-update.tar` used in the Active BMC procedure is **not** used here — the backup tool writes a raw `image-bmc` directly to the chip.

### When to refresh the backup EEPROM

- After applying a BMC firmware update that you have verified is stable, so the backup chip mirrors the production version.
- **Immediately after a recovery swap** — see [§6.3](#63-after-a-recovery-swap-refresh-the-new-backup) below.

### 6.1 Prerequisites

- A `image-bmc` file for the version you want on the backup chip. This is the raw BMC flash image; if you only have the update tar, extract it first:

  ```bash
  tar -xf tiogapass-bmc-update.tar image-bmc
  ```

- The backup EEPROM must be physically installed on the motherboard. If it is not present, the procedure will fail with `'bmc-backup' MTD partition not found` and no software change can work around it.

### 6.2 Procedure

1. Copy the raw image onto the BMC:

   ```bash
   scp image-bmc root@<bmc-ip>:/tmp/
   ```

2. SSH into the BMC and run the backup flash tool:

   ```bash
   ssh root@<bmc-ip>
   /sbin/backup-bmc-flash /tmp/image-bmc
   ```

   The tool locates the backup chip, validates the image size, and writes the chip (approximately 2 minutes). It prints `done — backup chip is ready.` on success. The active BMC keeps running normally throughout — no reboot is required.

3. Clean up the staged image:

   ```bash
   rm /tmp/image-bmc
   ```

### 6.3 After a recovery swap, refresh the new backup

If you swapped the backup chip into the primary socket because the original primary was corrupted, the BMC is now running from what used to be the backup, and the slot that used to hold the primary is now empty (or holds a chip with the corrupted image).

Once the BMC is back up and confirmed healthy, run the §6.2 procedure again on the running BMC with the current `image-bmc` so that the chip in the (now empty / previously corrupted) backup socket holds a fresh copy of the same firmware. Without this step the system has no backup left for a future failure.

If the corrupted chip was removed and not replaced, contact your hardware vendor to source and install a replacement chip before re-running §6.2.

---

## 7. Checking Active Firmware Versions

### Web UI

The active BMC and BIOS versions are shown on the **Overview** page and under **Settings → Firmware**.

### Redfish

```bash
# BMC version
curl -sk -u root:0penBmc \
  https://<bmc-ip>/redfish/v1/Managers/bmc | python3 -m json.tool | grep FirmwareVersion

# Full firmware inventory (BMC + BIOS)
curl -sk -u root:0penBmc \
  https://<bmc-ip>/redfish/v1/UpdateService/FirmwareInventory | python3 -m json.tool
```

---

## 8. Troubleshooting

### 8.1 Update fails immediately, or shows "Error in switching running and backup images"

**Symptom:** A second BMC update attempt fails without the BMC having rebooted, or curl returns HTTP 423 (`resourceInUse`).

**Fix:** Try clearing the busy flag:

```bash
curl -sk -u root:0penBmc \
  -X PATCH https://<bmc-ip>/redfish/v1/UpdateService \
  -H "Content-Type: application/json" \
  -d '{"HttpPushUriTargetsBusy": false}'
```

If that does not help, reboot the BMC and retry:

```bash
curl -sk -u root:0penBmc \
  -X POST https://<bmc-ip>/redfish/v1/Managers/bmc/Actions/Manager.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType":"GracefulRestart"}'
```

The BMC takes 60–90 seconds to come back online.

### 8.2 BIOS update failed and the UI will not let you retry

**Symptom:** A BIOS update reports failure; subsequent attempts are rejected.

**Fix:** Reboot the BMC (see §8.1) and retry the BIOS update. Make sure the host is powered off before retrying.

### 8.3 Upload is rejected as incompatible

**Symptom:** The upload succeeds but the activation never starts, or the Web UI reports a compatibility error.

**Cause:** The BMC update tar does not match this machine.

**Fix:** Confirm with your vendor that the tar is built for TiogaPass and that its manifest contains `CompatibleName=com.meta.Hardware.BMC.Model.TiogaPass`. Do not attempt to flash a BMC image built for a different platform.

### 8.4 BIOS update reports failure with the host powered on

**Symptom:** A BIOS update fails almost immediately and the host stays powered on.

**Fix:** Power the host off and retry. The BIOS flash path cannot run while the host owns the BIOS SPI bus:

```bash
curl -sk -u root:0penBmc \
  -X POST https://<bmc-ip>/redfish/v1/Systems/system/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType":"ForceOff"}'
```

Wait until `PowerState` reaches `Off`:

```bash
curl -sk -u root:0penBmc \
  https://<bmc-ip>/redfish/v1/Systems/system | python3 -m json.tool | grep PowerState
```

### 8.5 Host will not power on after a BIOS update

**Symptom:** After a successful BIOS flash, the host fails to power on through the Web UI or Redfish.

**Fix:** Perform a full AC power cycle of the chassis (unplug the system, wait 30 seconds, plug it back in). The BIOS flash path can leave the PSU in a state that only an AC cycle clears. Soft power-on works normally after that.
