#!/bin/sh
# Phase B capture, run ON the OEM BMC.  This one needs a host boot: it records
# the BIOS's inventory push as it happens.
#
#   ssh <oem-bmc> 'sh /tmp/capture-phase-b.sh start'
#   ... power on the host, let it POST to completion ...
#   ssh <oem-bmc> 'sh /tmp/capture-phase-b.sh stop'
#   scp <oem-bmc>:/tmp/oemcap-b.tar .
#
# Start BEFORE powering the host.  The push happens during POST and is not
# repeatable without another boot, so a missed start costs a full cycle.

OUT=/tmp/oemcap-b
REDIS_SOCK=/var/run/redis/redis.sock

case "$1" in
start)
    rm -rf "$OUT"; mkdir -p "$OUT"

    # Snapshot the inventory keys BEFORE the push -- the delta against the
    # after-snapshot is exactly what the BIOS wrote.
    if command -v redis-cli >/dev/null 2>&1; then
        for DB in 0 1; do
            redis-cli -s "$REDIS_SOCK" -n "$DB" KEYS '*' 2>/dev/null \
                | grep -iE "inventorydata|oem:ami:inventory|GroupCrcList" \
                > "$OUT/before-keys-db$DB.txt" 2>/dev/null
        done
        redis-cli -s "$REDIS_SOCK" monitor > "$OUT/monitor.log" 2>&1 &
        echo $! > "$OUT/monitor.pid"
        echo "redis monitor started (pid $(cat "$OUT/monitor.pid"))"
    else
        echo "WARNING: no redis-cli -- the semantic layer will be missing"
    fi

    # Ciphertext, but it still gives exact ordering, sizes and timing of every
    # request, which is what pins down the batched-vs-per-file and double-POST
    # divergences.
    if command -v tcpdump >/dev/null 2>&1; then
        for IF in usb0 eth0; do
            if ip link show "$IF" >/dev/null 2>&1; then
                tcpdump -i "$IF" -s 0 -w "$OUT/hi-$IF.pcap" >/dev/null 2>&1 &
                echo $! >> "$OUT/tcpdump.pids"
                echo "tcpdump started on $IF"
            fi
        done
    else
        echo "note: no tcpdump -- monitor.log alone is still the important half"
    fi

    echo "READY -- power on the host now."
    ;;

stop)
    [ -f "$OUT/monitor.pid" ] && kill "$(cat "$OUT/monitor.pid")" 2>/dev/null
    [ -f "$OUT/tcpdump.pids" ] && while read -r P; do kill "$P" 2>/dev/null; done \
        < "$OUT/tcpdump.pids"
    sleep 1

    if command -v redis-cli >/dev/null 2>&1; then
        for DB in 0 1; do
            redis-cli -s "$REDIS_SOCK" -n "$DB" KEYS '*' 2>/dev/null \
                | grep -iE "inventorydata|oem:ami:inventory|GroupCrcList" \
                > "$OUT/after-keys-db$DB.txt" 2>/dev/null
        done
        # Values of the inventory keys after the push.
        for DB in 0 1; do
            while read -r K; do
                [ -z "$K" ] && continue
                printf '%s\t%s\n' "$K" \
                    "$(redis-cli -s "$REDIS_SOCK" -n "$DB" GET "$K" 2>/dev/null)"
            done < "$OUT/after-keys-db$DB.txt" > "$OUT/after-values-db$DB.tsv" 2>/dev/null
        done
    fi

    [ -d /var/tmp/hi_inventory_files ] && \
        cp -r /var/tmp/hi_inventory_files "$OUT/" 2>/dev/null

    tar cf /tmp/oemcap-b.tar -C /tmp oemcap-b 2>/dev/null
    echo "DONE -- /tmp/oemcap-b.tar ($(wc -c < /tmp/oemcap-b.tar 2>/dev/null) bytes)"
    echo "monitor.log lines: $(wc -l < "$OUT/monitor.log" 2>/dev/null)"
    ;;

*)
    echo "usage: $0 start|stop"
    exit 1
    ;;
esac
