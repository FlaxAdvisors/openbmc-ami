#!/bin/sh
# Phase A capture, to be run ON the OEM BMC (chip swapped in).  No host boot
# needed -- the redis keys persist from the last BIOS push.
#
#   scp tools/oem-capture/capture-phase-a.sh <oem-bmc>:/tmp/
#   ssh <oem-bmc> 'sh /tmp/capture-phase-a.sh'
#   scp <oem-bmc>:/tmp/oemcap.tar .
#
# Target is AMI MegaRAC busybox: POSIX sh only, no curl, no bash.  Every step
# is independent and non-fatal -- a missing tool must not cost us the rest of
# the capture, because the box is only in this state for a short window.
#
# Override credentials if the defaults are wrong:
#   RF_USER=admin RF_PASS=... sh /tmp/capture-phase-a.sh

OUT=/tmp/oemcap
RF_USER="${RF_USER:-sysadmin}"
RF_PASS="${RF_PASS:-superuser}"
REDIS_SOCK=/var/run/redis/redis.sock

rm -rf "$OUT"; mkdir -p "$OUT"
exec 2>&1
log() { echo "=== $*" | tee -a "$OUT/capture.log"; }

log "capture started: $(date 2>/dev/null)"
log "uname: $(uname -a 2>/dev/null)"

# ---------------------------------------------------------------------------
# 0. Box identity -- which OEM build this is, and how the HI is wired.
# ---------------------------------------------------------------------------
{
    echo "--- /etc/os-release"; cat /etc/os-release 2>/dev/null
    echo "--- version files"; cat /etc/*version* 2>/dev/null
    echo "--- ip addr"; ip addr 2>/dev/null || ifconfig 2>/dev/null
    echo "--- listening"; netstat -lnp 2>/dev/null
    echo "--- processes"; ps w 2>/dev/null || ps 2>/dev/null
} > "$OUT/00-box-identity.txt" 2>&1
log "box identity captured"

# ---------------------------------------------------------------------------
# 1. THE PRIZE: the InventoryData resource body the BIOS actually receives.
#    Try every plausible address/credential combination and keep them all --
#    which one answers tells us how the OEM gates the endpoint, which we need
#    for our own route regardless.
# ---------------------------------------------------------------------------
URI=/redfish/v1/Oem/Ami/InventoryData
i=0
for HOST in 127.0.0.1 169.254.0.17 localhost; do
    i=$((i + 1))
    F="$OUT/01-inventorydata-$i-$HOST.json"
    wget --no-check-certificate -q -O "$F" \
         --user="$RF_USER" --password="$RF_PASS" \
         "https://$HOST$URI" 2>>"$OUT/01-wget-errors.txt"
    if [ -s "$F" ]; then
        log "GOT InventoryData from $HOST: $(wc -c < "$F") bytes (expect ~3105)"
    else
        rm -f "$F"
        # retry without auth -- some OEM builds leave the HI endpoints open
        # to the link-local interface only
        wget --no-check-certificate -q -O "$F" "https://$HOST$URI" \
             2>>"$OUT/01-wget-errors.txt"
        if [ -s "$F" ]; then
            log "GOT InventoryData from $HOST (no auth): $(wc -c < "$F") bytes"
        else
            rm -f "$F"
            log "no InventoryData from $HOST"
        fi
    fi
done

# Neighbouring resources worth having while we are here.
for R in /redfish/v1/Oem/Ami \
         /redfish/v1/Chassis/Self/PCIeDevices \
         /redfish/v1/Systems/Self/Storage \
         /redfish/v1/Chassis/Self/NetworkAdapters; do
    N=$(echo "$R" | tr '/' '_')
    wget --no-check-certificate -q -O "$OUT/02-res$N.json" \
         --user="$RF_USER" --password="$RF_PASS" "https://127.0.0.1$R" \
         2>>"$OUT/01-wget-errors.txt" || rm -f "$OUT/02-res$N.json"
done
log "neighbouring resources fetched"

# ---------------------------------------------------------------------------
# 2. Redis, TYPE-aware.  The earlier dumps in protocol-reverse/ used a plain
#    GET on every key and are full of WRONGTYPE, which silently lost every
#    set/hash -- do not repeat that.
# ---------------------------------------------------------------------------
if [ -S "$REDIS_SOCK" ] && command -v redis-cli >/dev/null 2>&1; then
    RC="redis-cli -s $REDIS_SOCK"
    for DB in 0 1; do
        $RC -n "$DB" KEYS '*' 2>/dev/null | while read -r K; do
            [ -z "$K" ] && continue
            T=$($RC -n "$DB" TYPE "$K" 2>/dev/null)
            case "$T" in
                string) V=$($RC -n "$DB" GET "$K" 2>/dev/null) ;;
                hash)   V=$($RC -n "$DB" HGETALL "$K" 2>/dev/null | tr '\n' '|') ;;
                list)   V=$($RC -n "$DB" LRANGE "$K" 0 -1 2>/dev/null | tr '\n' '|') ;;
                set)    V=$($RC -n "$DB" SMEMBERS "$K" 2>/dev/null | tr '\n' '|') ;;
                zset)   V=$($RC -n "$DB" ZRANGE "$K" 0 -1 2>/dev/null | tr '\n' '|') ;;
                *)      V="($T)" ;;
            esac
            printf '%s\t%s\t%s\n' "$T" "$K" "$V"
        done > "$OUT/03-redis-db$DB.tsv" 2>/dev/null
        log "redis db$DB: $(wc -l < "$OUT/03-redis-db$DB.tsv") keys"
    done

    # The inventory/CRC namespace on its own, so it is easy to read.
    for DB in 0 1; do
        grep -iE "inventorydata|oem:ami:inventory|GroupCrcList" \
             "$OUT/03-redis-db$DB.tsv" >> "$OUT/04-inventory-keys.tsv" 2>/dev/null
    done
    log "inventory keys: $(wc -l < "$OUT/04-inventory-keys.tsv" 2>/dev/null) rows"
else
    log "WARNING: no redis-cli or socket at $REDIS_SOCK -- check paths in 00-box-identity"
fi

# ---------------------------------------------------------------------------
# 3. The stored push files.  The OEM keeps a full inventory.json here.
# ---------------------------------------------------------------------------
for D in /var/tmp/hi_inventory_files /conf/inv.txt /conf/inventory.ini \
         /conf/invphypresence.txt; do
    [ -e "$D" ] && cp -r "$D" "$OUT/" 2>/dev/null && log "copied $D"
done

# ---------------------------------------------------------------------------
# 4. The CRC producer, in case this build differs from the image we unpacked.
# ---------------------------------------------------------------------------
[ -d /usr/local/sync-agent ] && \
    tar cf "$OUT/05-sync-agent.tar" -C /usr/local sync-agent 2>/dev/null && \
    log "sync-agent copied"

tar cf /tmp/oemcap.tar -C /tmp oemcap 2>/dev/null
log "DONE -- /tmp/oemcap.tar ($(wc -c < /tmp/oemcap.tar 2>/dev/null) bytes)"
echo
echo "Pull it with:  scp <oem-bmc>:/tmp/oemcap.tar ."
