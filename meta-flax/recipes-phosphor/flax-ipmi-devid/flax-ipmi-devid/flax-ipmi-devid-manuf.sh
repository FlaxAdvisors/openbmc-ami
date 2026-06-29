#!/bin/sh
#
# Derive the IPMI "Get Device ID" Manufacturer ID and Product ID from the board
# FRU and cache them for intel-ipmi-oem's ipmiAppGetDeviceId handler.  The same
# firmware image runs on Wiwynn and Quanta boards, so the values reported by
# "ipmitool mc info" must follow the FRU rather than being hard-coded.  Reading
# the FRU here (once, at boot) keeps D-Bus out of the Get Device ID hot path.
#
# These values mirror what the respective OEM/stock images report:
#   Wiwynn -> manuf 40092 (0x9C9C), product 7220  (0x1C34)
#   Quanta -> manuf 40981 (0xA015), product 12614 (0x3146)
#   unknown/unreadable -> Wiwynn defaults (never report Intel)
#
# Output (decimal): /var/cache/private/manufID and /var/cache/private/prodID

CACHE_DIR=/var/cache/private
MANUF_FILE="$CACHE_DIR/manufID"
PROD_FILE="$CACHE_DIR/prodID"
SVC=xyz.openbmc_project.FruDevice
IFACE=xyz.openbmc_project.FruDevice

read_manufacturer() {
    # Walk every FRU object; return the first non-empty PRODUCT/BOARD
    # manufacturer string.
    for obj in $(busctl tree --list "$SVC" 2>/dev/null \
                 | grep '^/xyz/openbmc_project/FruDevice/'); do
        for prop in PRODUCT_MANUFACTURER BOARD_MANUFACTURER; do
            val=$(busctl get-property "$SVC" "$obj" "$IFACE" "$prop" 2>/dev/null \
                  | sed -e 's/^s "//' -e 's/"$//')
            if [ -n "$val" ]; then
                echo "$val"
                return 0
            fi
        done
    done
    return 0
}

# FruDevice probes EEPROMs asynchronously after its service starts, so the
# manufacturer property may not be populated immediately.  Poll for up to ~30s.
MFG=""
i=0
while [ "$i" -lt 30 ]; do
    MFG=$(read_manufacturer)
    [ -n "$MFG" ] && break
    sleep 1
    i=$((i + 1))
done

MFG_LC=$(echo "$MFG" | tr 'A-Z' 'a-z')
case "$MFG_LC" in
    *wiwynn*) MID=40092; PID=7220  ;;   # 0x9C9C / 0x1C34
    *quanta*) MID=40981; PID=12614 ;;   # 0xA015 / 0x3146
    *)        MID=40092; PID=7220  ;;   # default: Wiwynn
esac

mkdir -p "$CACHE_DIR"
printf '%s\n' "$MID" > "$MANUF_FILE"
printf '%s\n' "$PID" > "$PROD_FILE"
echo "flax-ipmi-devid: FRU manufacturer '$MFG' -> manuf_id $MID, prod_id $PID"
