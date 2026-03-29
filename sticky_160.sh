#!/bin/sh
# sticky_160.sh - Keep 5GHz radio on preferred range at 160MHz
# Runs via cron every 30 minutes

SCRIPT_NAME="sticky_160"   # Must match the actual filename without .sh
IFACE="eth6"
PREFERRED_CHAN="100/160"   # Chanspec to force back to if outside preferred range
PREFERRED_RANGE="100-128"  # Channel range considered preferred (e.g. 100-128 or 36-64)
CRON_OFFSET=1              # Minute offset for cron job (e.g. 3 = runs at :03 and :33)
VERBOSE=1                  # 0=silent, 1=basic logging
MANAGE_CRON=0              # Set to 1/0 to add/remove cron job
LOG_LINES=100
INIT_START="/jffs/scripts/init-start"

# Derived from SCRIPT_NAME and CRON_OFFSET - do not edit
SCRIPT_PATH="/jffs/scripts/${SCRIPT_NAME}.sh"
LOG_FILE="/jffs/scripts/${SCRIPT_NAME}.log"
CRON_TIME="${CRON_OFFSET},$((CRON_OFFSET + 30)) * * * *"
CRON_SCHEDULE="$CRON_TIME $SCRIPT_PATH"
INIT_ENTRY="cru a \"$SCRIPT_NAME\" \"$CRON_TIME $SCRIPT_PATH\""

# Parse preferred range bounds
RANGE_LOW="${PREFERRED_RANGE%-*}"
RANGE_HIGH="${PREFERRED_RANGE#*-}"

# -----------------------------------------
# 1. Functions
# -----------------------------------------

log() {
    local level="$1" message="$2"
    [ "$VERBOSE" -lt "$level" ] && return 0
    echo "$(date): $message" >> "$LOG_FILE"
}
cleanup_and_exit() {
    tail -n $LOG_LINES "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    exit "${1:-0}"
}

# -----------------------------------------
# 2. Cron and init-start self-registration
# -----------------------------------------

log 1 "[__START] Script triggered by cron"
if [ "$MANAGE_CRON" = "1" ]; then
    cru l 2>/dev/null | grep -q "$SCRIPT_NAME" || cru a "$SCRIPT_NAME" "$CRON_SCHEDULE"
    if [ ! -f "$INIT_START" ]; then
        printf '#!/bin/sh\n%s\n' "$INIT_ENTRY" > "$INIT_START"
        chmod +x "$INIT_START"
        log 1 "[ACTION] Created '$INIT_START' and added entry."
    elif ! grep -qF "$INIT_ENTRY" "$INIT_START"; then
        echo "$INIT_ENTRY" >> "$INIT_START"
        log 1 "[ACTION] Added entry to existing '$INIT_START'."
    fi
else
    cru l 2>/dev/null | grep -q "$SCRIPT_NAME" && cru d "$SCRIPT_NAME"
    grep -qF "$INIT_ENTRY" "$INIT_START" 2>/dev/null && sed -i "\|$SCRIPT_PATH|d" "$INIT_START"
fi

# -----------------------------------------
# 3. Radio up check
# -----------------------------------------

if [ "$(wl -i "$IFACE" isup 2>/dev/null)" != "1" ]; then
    log 1 "[OFFLINE] Radio $IFACE is [DOWN]. Exiting."
    cleanup_and_exit 0
fi

# -----------------------------------------
# 4. Read and evaluate current state
# -----------------------------------------

CURRENT_SPEC=$(wl -i "$IFACE" chanspec 2>/dev/null | awk '{print $1}')
CURRENT_CHAN="${CURRENT_SPEC%%/*}"
CURRENT_WIDTH="${CURRENT_SPEC#*/}"

# -----------------------------------------
# 5. Outside preferred range or in range at 80MHz move to preferred channel
# -----------------------------------------

log 1 "[INFO] Current state [CHANSPEC=$CURRENT_SPEC]"
if [ "$CURRENT_CHAN" -lt "$RANGE_LOW" ] || [ "$CURRENT_CHAN" -gt "$RANGE_HIGH" ] || [ "$CURRENT_WIDTH" = "80" ]; then
    log 1 "[ACTION] Moving to [$PREFERRED_CHAN]. dfs_ap_move initiated."
    wl -i "$IFACE" dfs_ap_move "$PREFERRED_CHAN" 2>/dev/null
else
    log 1 "[OK] In range at 160MHz [$CURRENT_SPEC]. No action needed."
fi

log 1 "[__END] Script completed successfully"
cleanup_and_exit 0