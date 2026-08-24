# OEM BMC chip swap — capture plan

Goal: come away with a **byte-exact reference** for
`GET /redfish/v1/Oem/Ami/InventoryData` and the CRC semantics behind it, plus
the full BIOS↔BMC host-interface conversation, so the OEM inventory path can be
implemented from a spec instead of guessed at.

Why this needs the live box (established 2026-08-14, do not re-derive):

- The string `InventoryData` appears **nowhere** in the OEM firmware — not in
  the full rootfs cramfs (`0x460000`, mounted at `/mnt/oemroot`), not in the web
  cramfs (`0x1e40000`), not in the raw image. `GroupCrcList` appears exactly
  once, in `usr/local/sync-agent/subagents/redfish-2-redfishgroup.lua`.
- The OEM Redfish stack is **redis-backed and data-driven**: the resource is a
  render of keys under `Redfish:Oem:Ami:InventoryData:*`, which the 2026-07-23
  monitor logs show being GET/SET live. The HI handler library
  (`libspx_restservice_hostinterface.so`) holds only internal handler names
  (`/host_inventory/host_interface_{system,processor,memory,storage,
  pcie_device_function,thermal,power,baseboard}_info`).
- So the body is **runtime state, not code**. Static analysis cannot produce it;
  a packet trace cannot either (the HI is HTTPS, and ECDHE means even the server
  key would not decrypt it). Redis is the plaintext layer.

Stakes: three attempts to reconstruct this body by guesswork all crashed the
BIOS at a constant `RIP 674D113B`, making the host unbootable until reverted.
This capture is what replaces guessing.

## Scripts

The two phases are scripted so the chip-swap window is spent capturing, not
typing.  Both are POSIX sh for the OEM's busybox (no bash, no curl), and every
step is non-fatal so a missing tool cannot cost the rest of the capture:

They live in the separate host-side tools repo, under `oem-capture/`:

- `capture-phase-a.sh` — at rest, no host boot
- `capture-phase-b.sh start|stop` — around a host boot

Each tars its output to `/tmp/oemcap.tar` / `/tmp/oemcap-b.tar` for a single
scp back.  The steps below are what those scripts do, kept here so the capture
can also be driven by hand if a box detail differs.

## Access

```bash
ssh brain
sshpass -p superuser ssh -o StrictHostKeyChecking=no sysadmin@192.168.88.248
```

Same IP as our build (one physical box, chip swapped). On the OEM BMC:
`redis-cli -s /var/run/redis/redis.sock` (db0 default; the inventory CRC keys
live in `-n 1`). There is **no curl** — use `wget`.

## Phase A — at rest, no host boot needed (~15 min)

The keys persist from the last push, so most of the prize is available the
moment the OEM BMC is up.

1. **The resource itself.** This is the whole point; do it first.

   ```bash
   wget --no-check-certificate -qO /tmp/cap-inventorydata-local.json \
        --user=admin --password=<oem-pw> \
        https://127.0.0.1/redfish/v1/Oem/Ami/InventoryData
   wc -c /tmp/cap-inventorydata-local.json     # expect ~3105
   ```

   If it 403s (the endpoint may be gated to the HI interface/account), retry
   against the HI address `https://169.254.0.17/...` and with the HI-FW
   account. **Record which combination works** — that tells us how the OEM
   gates it, which we need for our own route anyway.

2. **Full redis dump, both DBs**, values included and TYPE-aware (the older
   dumps in `protocol-reverse/` used plain GET and are littered with
   `WRONGTYPE`, losing every set/hash):

   ```bash
   for db in 0 1; do
     redis-cli -s /var/run/redis/redis.sock -n $db KEYS '*' | while read k; do
       t=$(redis-cli -s /var/run/redis/redis.sock -n $db TYPE "$k")
       case $t in
         string) v=$(redis-cli -s /var/run/redis/redis.sock -n $db GET "$k");;
         hash)   v=$(redis-cli -s /var/run/redis/redis.sock -n $db HGETALL "$k");;
         list)   v=$(redis-cli -s /var/run/redis/redis.sock -n $db LRANGE "$k" 0 -1);;
         set)    v=$(redis-cli -s /var/run/redis/redis.sock -n $db SMEMBERS "$k");;
         zset)   v=$(redis-cli -s /var/run/redis/redis.sock -n $db ZRANGE "$k" 0 -1);;
         *)      v="($t)";;
       esac
       printf '%s\t%s\t%s\n' "$t" "$k" "$v"
     done > /tmp/cap-redis-db$db.tsv
   done
   ```

   Priority keys if the full dump is too slow: `Redfish:Oem:Ami:InventoryData*`,
   `Redfish:oem:ami:inventory:*` (db1), `Redfish:Chassis:Self:PCIeDevices:*`,
   `Redfish:Systems:Self:Storage:*`, `Redfish:Chassis:Self:NetworkAdapters:*`.

3. **The stored push files**: `/var/tmp/hi_inventory_files/` (the OEM keeps a
   full `inventory.json` there) — copy the whole directory.

4. **Config/identity**: `ip addr`, the HI account list, and the TLS cert the HI
   serves (`openssl s_client` is unlikely to exist; just copy the cert files
   from `/conf`). Confirms our minted-cert assumptions.

## Phase B — live push, needs a host boot (~45 min)

5. Start capture **before** powering the host:

   ```bash
   redis-cli -s /var/run/redis/redis.sock monitor > /tmp/cap-monitor.log &
   tcpdump -i usb0 -s 0 -w /tmp/cap-hi.pcap &     # ciphertext, but gives exact
                                                  # ordering, sizes and timing
   ```

6. Power the host, let it POST to completion.

7. Stop the captures and re-dump the `InventoryData*` keys (they change on
   push — the delta between before and after is exactly what the BIOS wrote).

8. Optional second cycle with BIOS "Restore Defaults" first, to see a **full**
   push rather than the ~852-byte delta.

Cross-check against `protocol-reverse/COMPARISON-2026-08-11.md`, which lists
the five known divergences we still cannot explain (batched vs per-file
`BiosStaticFiles`, the double `POST Systems/Self/Bios`, the never-sent
`POST Oem/Ami/InventoryData`, the `SecureBoot.ResetKeys` GET, and the 3105 vs
191 byte body).

## Phase C — restore

Power off, swap our chip back, boot, and confirm: `flax-hi-inventory.path`
enabled, Redfish Memory = 12 / Processors = 2. Our chip is untouched
throughout — nothing is reflashed, so there is no recovery risk to our build.

## Acceptance criteria before we ever serve that GET again

The rule that would have prevented the three crashes: **prove the body offline
first.**

1. Generate our body on the bench and diff it against
   `cap-inventorydata-local.json` — same keys, same nesting, same types, same
   order. Only CRCs and timestamps may legitimately differ.
2. Our CRC implementation must reproduce the OEM's captured values from the
   captured inventory content: `DIMM 2764192848`, `CPU 3032237160`,
   `PCIE 3797810510`. Until it does, we do not understand the handshake.
3. Only then point the BIOS at it — with the file-based kill switch (answer the
   GET with 405, which is today's working behaviour) staged and tested first, so
   recovery is one file touch and a bmcweb restart rather than a reflash.

## What this unlocks if it works

Not just PCIe. The same OEM push carries, per the captures already in hand:

- **PCIe**: 25 devices / 47 functions with VendorId, DeviceId, ClassCode,
  RevisionId, SubsystemId, SubsystemVendorId, DeviceClass.
- **Storage**: `INTEL SSDPEKNW512G8`, serial `BTNH90350E9W512A`, capacity,
  SATA controllers — the CLAUDE.md "Storage" target.
- **NetworkAdapters**: Mellanox `FirmwarePackageVersion 14.27.26.06`, ports and
  link status — bears on the "blocked on AMI" host-NIC inventory item.

DIMMs and CPUs already work via the fallback path and do **not** depend on any
of this.
