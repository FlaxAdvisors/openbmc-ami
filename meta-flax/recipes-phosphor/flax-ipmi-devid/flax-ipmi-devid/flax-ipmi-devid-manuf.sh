#!/bin/sh
#
# Derive the IPMI "Get Device ID" Manufacturer ID and Product ID from the
# BASEBOARD FRU and cache them for intel-ipmi-oem's ipmiAppGetDeviceId handler.
# The same firmware image runs on Wiwynn and Quanta boards, so the values
# reported by "ipmitool mc info" must follow the board.  Reading the FRU here
# (once, at boot) keeps D-Bus out of the Get Device ID hot path.
#
# Only the baseboard is consulted.  A chassis carries several FRU EEPROMs
# (risers, adapters, PSUs) whose vendor has nothing to do with the board
# vendor, and busctl enumerates FruDevice objects in sorted path order -- so
# taking the first FRU that carries a manufacturer string picks whichever
# accessory happens to sort first.  On the Quanta board at .245 that is the
# Wiwynn-built "Ava-M.2-SSD-Adapter", which made a Quanta board report Wiwynn;
# the mirror case (a Quanta riser in a Wiwynn chassis) made a Wiwynn board
# report Quanta.  The baseboard is identified by its FRU product name
# containing "Tioga Pass": "Tioga Pass Single Side" on Quanta boards,
# "Type6 Tioga Pass Single Side" on Wiwynn/Wistron ones.
#
# PRODUCT_MANUFACTURER is preferred over BOARD_MANUFACTURER because it is the
# brand rather than the contract manufacturer -- Wiwynn boards report
# PRODUCT_MANUFACTURER "Wiwynn" but BOARD_MANUFACTURER "Wistron".
#
# The Manufacturer ID is the IANA enterprise number of the vendor the board
# actually names, not the identity the OEM image happened to ship:
#   Wiwynn -> manuf 40092 (0x9C9C) "Wiwynn Corporation"
#   Quanta -> manuf 7244  (0x1C4C) "Quanta Computer Inc."
# Earlier builds reported 40981 (Facebook) for Quanta boards, inherited from
# meta-facebook's dev_id.json.  Tioga Pass is a Facebook OCP design, but the
# board in the chassis is a Quanta board and that is what we report.
#
# The Product IDs are still the per-vendor values the stock images use (0x1C34
# Wiwynn, 0x3146 Facebook/Tioga Pass); no Quanta-assigned product ID for this
# platform is known, and inventing one would be worse than carrying this over.
#   unknown/unreadable -> Wiwynn defaults (never report Intel)
#
# Output (decimal): /var/cache/private/manufID and /var/cache/private/prodID

CACHE_DIR=/var/cache/private
MANUF_FILE="$CACHE_DIR/manufID"
PROD_FILE="$CACHE_DIR/prodID"
SVC=xyz.openbmc_project.FruDevice
IFACE=xyz.openbmc_project.FruDevice

# FruDevice probes the I2C EEPROMs asynchronously and the baseboard can take
# the better part of a minute to appear.  This service is ordered Before=
# phosphor-ipmi-host, so every second spent here is a second of delayed IPMI --
# keep each poll cheap.  An earlier revision re-read two name properties from
# every FRU object on every pass: ~27 busctl forks costing 3.2s per poll, which
# both delayed detection (4.2s granularity) and stole CPU from the FruDevice
# scan we were waiting on.
TIMEOUT_SECS=120

get_prop() {
    busctl get-property "$SVC" "$1" "$IFACE" "$2" 2>/dev/null \
        | sed -e 's/^s "//' -e 's/"$//'
}

fru_objects() {
    busctl tree --list "$SVC" 2>/dev/null | grep '^/xyz/openbmc_project/FruDevice/'
}

# PRODUCT_MANUFACTURER first: it is the brand, where BOARD_MANUFACTURER is the
# contract manufacturer (Wiwynn boards report BOARD_MANUFACTURER "Wistron").
manufacturer_of() {
    for prop in PRODUCT_MANUFACTURER BOARD_MANUFACTURER; do
        val=$(get_prop "$1" "$prop")
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    done
    return 1
}

# Fast path, one busctl call: FruDevice names each object after the board
# product name, so the baseboard appears as .../Tioga_Pass_Single_Side.
find_by_path() {
    for obj in $(fru_objects); do
        # Glob rather than $(echo|tr): case-folding every path forks a process
        # per FRU object, which dominated the cost of a poll.
        case "$obj" in
            *[Tt]ioga*) manufacturer_of "$obj" && return 0 ;;
        esac
    done
    return 1
}

# Safety net for a board whose object path is not derived from a decodable
# product name.  Costs two busctl calls per FRU object, so it runs at most
# once, after the fast path has failed for the whole timeout.
find_by_property() {
    for obj in $(fru_objects); do
        for prop in BOARD_PRODUCT_NAME PRODUCT_PRODUCT_NAME; do
            name=$(get_prop "$obj" "$prop" | tr 'A-Z' 'a-z')
            case "$name" in
                *"tioga pass"*) manufacturer_of "$obj" && return 0 ;;
            esac
        done
    done
    return 1
}

# Bound the wait on the clock, not on an iteration count: an iteration budget
# silently changes length whenever the cost of a poll changes.
MFG=""
START=$(date +%s)
while :; do
    MFG=$(find_by_path)
    [ -n "$MFG" ] && break
    ELAPSED=$(( $(date +%s) - START ))
    [ "$ELAPSED" -ge "$TIMEOUT_SECS" ] && break
    sleep 1
done

if [ -z "$MFG" ]; then
    MFG=$(find_by_property)
fi
ELAPSED=$(( $(date +%s) - START ))

MFG_LC=$(echo "$MFG" | tr 'A-Z' 'a-z')
case "$MFG_LC" in
    *wiwynn*) MID=40092; PID=7220  ;;   # Wiwynn Corporation  / 0x1C34
    *quanta*) MID=7244;  PID=12614 ;;   # Quanta Computer Inc. / 0x3146
    *)        MID=40092; PID=7220  ;;   # default: Wiwynn
esac

mkdir -p "$CACHE_DIR"
printf '%s\n' "$MID" > "$MANUF_FILE"
printf '%s\n' "$PID" > "$PROD_FILE"

if [ -n "$MFG" ]; then
    echo "flax-ipmi-devid: baseboard FRU manufacturer '$MFG' -> manuf_id $MID, prod_id $PID (${ELAPSED}s)"
else
    echo "flax-ipmi-devid: no baseboard FRU found after ${ELAPSED}s, defaulting to manuf_id $MID, prod_id $PID"
fi
