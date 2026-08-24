# Redfish HI inventory: take the OEM path, safely

Design, 2026-08-13. Implements the receive side of the TP26 BIOS host-interface
inventory push, using the AMI OEM protocol rather than the generic Redfish
fallback.

## Background

Evidence: `/vagrant/oem-reference/protocol-reverse/FINDINGS-2026-08-13-real-inventory-endpoints.md`.

The BIOS has two modes, and **our answer to `GET /redfish/v1/Oem/Ami/InventoryData`
selects which one**:

| our answer | BIOS behaviour |
|---|---|
| 200 + OEM-shaped body | **OEM path** — one `POST Oem/Ami/InventoryData` (~74 KB, everything), then `PATCH` |
| 405 | fallback — generic `DELETE`/`POST` on `Systems/system/Memory`, `/Processors`, `Chassis/Cpld/PCIeDevices` |
| 200 + our old malformed body | **#GP in RfInventory, host unbootable** |

We take the OEM path. It needs one correct GET body plus the POST/PATCH handlers
we already have, versus registering new verbs on three upstream-owned collection
paths (which hits the "handler already exists" abort documented in patch 0010).
It also delivers one atomic payload instead of fragmented per-member POSTs.

## Scope

One file: `redfish-core/lib/flax_host_interface.hpp`. **No upstream bmcweb files
are touched.**

Three routes on `/redfish/v1/Oem/Ami/InventoryData`: GET (steer), POST (receive),
PATCH (finalize).

## 1. The GET body

A **bare JSON object with exactly three members** — `GroupCrcList`, `Systems`,
`Chassis` — mirroring `oem-reference/protocol-reverse/inventory.json`.

**No `@odata.id`, `@odata.type`, `Id` or `Name`.** This is the one structural
difference from the OEM that survived every earlier attempt: patch 0011 added
`Systems`/`Chassis` but kept the boilerplate and still crashed the BIOS. It is
the prime suspect and the variable this change isolates.

Sources — D-Bus first, safe literal fallback, so **no member is ever null or
absent**:

| field | source |
|---|---|
| `Systems[0].UUID` | `xyz.openbmc_project.Common.UUID`, else machine-id derived |
| `Systems[0].SerialNumber` / `.SKU` / `.Manufacturer` | baseboard FRU |
| `Systems[0].BiosVersion` | `bios_active` version, else `TPC_P26C` |
| `Systems[0].Status` / `.TrustedModules` | literal, OEM shape |
| `Chassis[0]` | baseboard FRU + `ChassisType: RackMount` |
| `GroupCrcList` | `{DIMM, CPU, PCIE}` — CRC32 of each group held, `0` when none |

Zeros mean "we hold nothing, send everything". They were present in the crashing
build, so if removing the boilerplate is insufficient, CRCs are suspect two — try
the OEM's literal values (`DIMM 2764192848, CPU 3032237160, PCIE 926580983`) to
isolate.

## 2. Kill switch — TEMPORARY SCAFFOLDING

The GET returns **405** if `/var/lib/flax-inventory/disable-inventorydata-get`
exists, checked per request.

Serving this route is the only known way to make the host unbootable. Without
the switch, recovery is rebuild + hot-deploy with the host down; with it,
recovery is one SSH command plus a host power cycle.

**REMOVE THIS** once the boot sequence is stable and the GET body is proven.
It exists only to make iterating on the body affordable. Tracked in
`docs/CONTINUE-rfinventory-gp-bisect.md`.

## 3. Security gate

`isHostInterfaceClient(req)` requires **both**:

- **Transport** — remote address within `169.254.0.0/16`. The BIOS is
  `::ffff:169.254.0.18`; that prefix exists only on `usb0`. Sound against
  spoofing from the management LAN: replies to a forged source route out `usb0`,
  so the TCP handshake cannot complete.
- **Identity** — authenticated user is `HostAutoFW` or `HI-FW`.

Applied to **POST and PATCH only**. GET keeps ordinary Redfish auth — it is
read-only, and the OEM served it to any authenticated caller (its log shows
external `curl` getting 401 for missing credentials, not for being external).

Gate failure → **403 `InsufficientPrivilege`**. Not 404: the resource is already
discoverable via GET, so hiding it buys nothing and misleads debugging.

Note the HI accounts currently carry `priv-admin`, and their password is
obtainable over KCS by any host-side software. Identity alone is therefore a weak
gate — the transport check is what carries the security. Narrowing those accounts
to a minimal role is worthwhile future work, out of scope here.

## 4. Receive path

**POST** — write `inventory.json.tmp`, `fsync`, `rename()` into place, *then*
write `transfer-complete`. Atomic: a truncated transfer can never present as
complete to the Phase-2 translator. Returns **201**.

**PATCH** — same treatment into `inventory-patch.json`. Returns **204**. Kept
separate so it can never clobber the main payload.

**Size cap 2 MB → 413**, plus a free-space check before writing. `/var` is a
19.4 MB overlay and the real payload is ~74 KB; without a cap one oversized POST
fills the BMC's writable storage.

## 5. Testing

Everything except the GET body is testable **without spending a boot**, over the
HI link from the booted host OS:

| test | from | expect |
|---|---|---|
| POST as `HostAutoFW` | host OS (169.254.0.18) | 201, payload on disk, `transfer-complete` present |
| POST as `HostAutoFW` | brain over eth0 | 403 |
| POST >2 MB | host OS | 413 |
| POST anonymous | brain | 401 |
| PATCH as `HostAutoFW` | host OS | 204 |
| GET | brain, authenticated | 200, body has exactly 3 members |

Only the **GET body's effect on the BIOS** needs a boot. That isolates the risky
change to one variable; if the boot faults, the kill switch recovers in seconds
and the cause is unambiguous.

## Out of scope

- Phase-2 translation of `inventory.json` into D-Bus inventory
- Narrowing HI account privileges
- The generic-collection fallback handlers (documented as plan B in FINDINGS)
- `PATCH /redfish/v1/Systems/system` (400) and
  `PATCH /redfish/v1/oem/ami/configuredbsnapshot` (404) — only reached on the
  fallback path, which we are leaving
