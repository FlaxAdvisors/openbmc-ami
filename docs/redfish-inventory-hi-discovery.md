# TP26 BIOS Host-Interface Discovery & Credential Contract (Task 1.1)

How the closed TP26 BIOS reaches and authenticates to the Redfish Host Interface, so our
reimplemented HI presents what the BIOS expects. Sources: live OEM BMC (192.168.88.248) +
offline OEM rootfs (`WTPC_P407.ima`) + the KCS capture (`kcs-bytes-fullpush.txt`).

## The must-match HI contract (what our BMC must present)

| Property | OEM value (BIOS pushes here) | Our current value | Action |
|----------|------------------------------|-------------------|--------|
| HI network | `usb0` **169.254.0.17 / 16** (link-local) | `10.199.199.1/30` (bmcusb0) | **Re-address our HI to link-local 169.254.x** (or add a second HI interface) |
| USB function | CDC-ECM | CDC-ECM (`ecm.usb0`) | match ✓ (VID/PID TBD — see below) |
| Auth account | `HI-FW`, role **Administrator** | — | create an `HI-FW` Administrator account |
| Auth secret | **generated password** = the KCS `0x5d` `HostAuto*` token | — | KCS `0x5d` handler generates it; bmcweb HI-FW account accepts the same value |
| Auth method | HTTP Basic (`HI-FW` : token) over usb0 | — | accept Basic auth on the HI endpoint |
| HostInterfaceType | `NetworkHostInterface`, `InterfaceEnabled=true`, `ExternallyAccessible=false` | — | advertise likewise |
| Upload endpoint | `POST/PUT /redfish/v1/Oem/Ami/BiosStaticFiles` (inventory blob) | — | bmcweb OEM route saves body → our inventory file |

## Credential flow (confirmed)

From `hi-handlers/account.lua`: the `HI-FW` account (Administrator role) has a
`Generate_Password`. From the KCS capture: `cmd 0x5d` returns `HostAuto*` tokens. These are the
same thing — **the KCS-issued token IS the HI-FW account password**. Sequence:

1. BMC generates the HI-FW password.
2. BIOS requests it over KCS `cmd 0x5d` → receives the `HostAuto*` token.
3. BIOS authenticates HTTP Basic (`HI-FW` : `HostAuto*` token) to the HI Redfish over usb0 and
   POSTs the inventory blob.

**Our credential bridge:** the KCS `0x5d` handler (ipmid provider) generates a token, writes it
to a shared path (e.g. `/run/flax-hi-cred`) AND provisions the bmcweb `HI-FW` account password to
the same value — so the BIOS's KCS-obtained token authenticates against our HI.

## Confirmed on the live OEM BMC

- `usb0`: `169.254.0.17` mask `255.255.0.0` (link-local /16), MAC 9A:1A:66:9F:C5:22 (locally-admin).
- redis: `HostInterfaceType=NetworkHostInterface`, `InterfaceEnabled=true`,
  `ExternallyAccessible=false`, `FirmwareAuthRoleId=Administrator`,
  account `Redfish:AccountService:Accounts:HI-FW`.
- The USB gadget is NOT set up via configfs or legacy `g_ether` on the running OEM BMC (a
  compiled component brings up usb0), so idVendor/idProduct aren't readable from the BMC.

## Deferred to Phase 1 hardware (needs the x86 host OS / our own image)

These are host-side facts, naturally read when we flash our image and test:

1. **SMBIOS Type 42** — `dmidecode -t 42` on the host OS gives the BIOS's own HI descriptor:
   the **Host IP Assignment Type** (Static vs AutoConfigure/link-local — the `169.254` /16
   strongly implies AutoConfigure link-local), the **Redfish Service IP Discovery Type**, and
   the **USB Device Descriptor (idVendor/idProduct/serial)** the BIOS binds the HI to. This
   confirms whether we must match a specific VID/PID and whether the IP is fixed or negotiated.
2. If the BIOS binds on a specific VID/PID, set our `ecm.usb0` `idVendor`/`idProduct` to match.

## Default strategy if Type 42 is unavailable early

**Replicate the OEM's working HI exactly**: present our HI on usb0 at `169.254.0.17/16`,
CDC-ECM, `HI-FW`/Administrator with the KCS-`0x5d`-generated password, and the
`/Oem/Ami/BiosStaticFiles` upload route. Since the closed BIOS only knows its Type 42 + the KCS
bootstrap, matching the OEM's presentation should make it push to us identically. Confirm/adjust
via Type 42 if the Phase-1 hardware test shows the BIOS not pushing.

## Impact on the implementation plan (Task 1.3)

`create_usbeth.sh` changes: HI interface at `169.254.0.17/16` link-local (keep our existing
`10.199.199.x` in-band vNIC separate if both are needed — do not repurpose it). Add the
`HI-FW` account + the `/Oem/Ami/BiosStaticFiles` bmcweb route + the credential bridge from Task 1.2.
