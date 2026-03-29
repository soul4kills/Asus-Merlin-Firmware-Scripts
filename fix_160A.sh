#!/bin/sh
# fix_160A.sh - Keep 5GHz radio on 160MHz
# Made for dual-band routers only
# Tri-band owners can try sticky_160 version with 2 copies, 1 for each interface, offset the cron jobs & set IFACE manually
# Runs via cron every 30 minutes (1,31 * * * *)

SCRIPT_NAME="fix_160A"      # Script name must match the actual filename without .sh
IFACE=""                    # 5GHz interface - leave empty for auto-detection, or set manually e.g. "eth6"
COOLDOWN=60                 # Minimum seconds between recovery attempts
CAC_WAIT=61                 # Seconds to wait for CAC to complete - set slightly above 61 to ensure completion
PREFERRED="100/160"         # Preferred 160MHz target (may be overridden by NVRAM if wl1_chanspec != 0)
DISABLE_FALLBACK=1          # 1=always stay in PREFERRED block, never try the other 160MHz block
STRICT_STICKY=0             # 0=jump to PREFERRED only if current channel is outside preferred block range (default)
                            # 1=jump to PREFERRED if not on the exact PREFERRED chanspec, even within the same block
                            # Note: automatically set to 1 when NVRAM wl1_chanspec overrides PREFERRED
MANAGE_CRON=1               # Set to 1/0 to add/remove cron and init-start entries
VERBOSE=2                   # 0=silent, 1=basic logging, 2=verbose (includes DFS status blocks)
LOG_ROTATE_RAM=1            # 0=use temp file (safer), 1=use RAM (no temp file on disk)
LOG_LINES=200

# Derived from SCRIPT_NAME - do not edit
SCRIPT_PATH="/jffs/scripts/${SCRIPT_NAME}.sh"
LOG_FILE="/jffs/scripts/${SCRIPT_NAME}.log"
LOCK_FILE="/tmp/${SCRIPT_NAME}.last_action"
INIT_START="/jffs/scripts/init-start"

# -----------------------------------------
# 1. Functions
# -----------------------------------------

log() {
    local level="$1"
    local message="$2"
    [ "$VERBOSE" -lt "$level" ] && return 0
    echo "$(date): $message" >> "$LOG_FILE"
}

# Writes [__END], rotates log, and exits cleanly
finish() {
#    log 1 "[__END]"
    if [ "$LOG_ROTATE_RAM" = "1" ]; then
        local content
        content=$(tail -n $LOG_LINES "$LOG_FILE")
        echo "$content" > "$LOG_FILE"
    else
        tail -n $LOG_LINES "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    exit 0
}

log_dfs_status() {
    [ "$VERBOSE" -lt 2 ] && return 0
    local label="$1"
    local status
    status=$(wl -i "$IFACE" dfs_ap_move 2>/dev/null)
    log 2 "[DFS_STATUS:$label]"
    echo "$status" | while IFS= read -r line; do
        echo "$(date):   $line" >> "$LOG_FILE"
    done
}

manage_cron_job() {
    local action="$1"
    local job_id="$SCRIPT_NAME"
    local cron_schedule="1,31 * * * * $SCRIPT_PATH"
    if [ "$action" = "add" ]; then
        if cru l 2>/dev/null | grep -q "$job_id"; then
            log 4 "[CRON] Cron job '$job_id' already exists. No action needed."
        else
            cru a "$job_id" "$cron_schedule"
            log 1 "[ACTION] Added cron job '$job_id'."
        fi
    elif [ "$action" = "remove" ]; then
        if cru l 2>/dev/null | grep -q "$job_id"; then
            cru d "$job_id"
            log 1 "[ACTION] Removed cron job '$job_id'."
        else
            log 4 "[CRON] Cron job '$job_id' does not exist. No action needed."
        fi
    fi
}

manage_init_start() {
    local action="$1"
    local entry="cru a \"$SCRIPT_NAME\" \"1,31 * * * * $SCRIPT_PATH\""
    if [ "$action" = "add" ]; then
        if [ ! -f "$INIT_START" ]; then
            printf '#!/bin/sh\n%s\n' "$entry" > "$INIT_START"
            chmod +x "$INIT_START"
            log 1 "[ACTION] Created '$INIT_START' and added entry."
        elif ! grep -qF "$entry" "$INIT_START"; then
            echo "$entry" >> "$INIT_START"
            log 1 "[ACTION] Added entry to existing '$INIT_START'."
        else
            log 4 "[INIT] Entry already present in '$INIT_START'. No action needed."
        fi
    elif [ "$action" = "remove" ]; then
        if [ ! -f "$INIT_START" ]; then
            log 4 "[INIT] '$INIT_START' does not exist. No action needed."
        elif grep -qF "$entry" "$INIT_START"; then
            sed -i "\|$SCRIPT_PATH|d" "$INIT_START"
            log 1 "[ACTION] Removed entry from '$INIT_START'."
        else
            log 4 "[INIT] Entry not found in '$INIT_START'. No action needed."
        fi
    fi
}

# Attempt dfs_ap_move to target chanspec.
# Sets MOVED=1 if accepted, MOVED=0 if rejected.
# Returns 0 if accepted, 1 if rejected.
try_dfs_ap_move() {
    local target="$1"
    local err result
    err=$(wl -i "$IFACE" dfs_ap_move "$target" 2>&1)
    result=$?
    if [ "$result" -eq 0 ]; then
        log 4 "[ACTION] dfs_ap_move accepted [$target]. Background CAC started."
        MOVED=1
        return 0
    else
        log 1 "[INFO] dfs_ap_move rejected [$target]: $err"
        MOVED=0
        return 1
    fi
}

# -----------------------------------------
# 2. NVRAM config override
#    Reads wl1_chanspec from NVRAM (the GUI's channel setting).
#    "0" means Auto - script uses config defaults above.
#    Any valid */160 chanspec overrides PREFERRED, forces DISABLE_FALLBACK=1
#    and STRICT_STICKY=1 so the script always targets the GUI-configured channel.
# -----------------------------------------
_NVRAM_CS=$(nvram get wl1_chanspec 2>/dev/null | tr -d ' ')
if [ -z "$_NVRAM_CS" ] || [ "$_NVRAM_CS" = "0" ]; then
    log 1 "[NVRAM] wl1_chanspec=auto (0). Using config defaults [PREFERRED=$PREFERRED, DISABLE_FALLBACK=$DISABLE_FALLBACK, STRICT_STICKY=$STRICT_STICKY]."
else
    _NVRAM_WIDTH="${_NVRAM_CS#*/}"
    _NVRAM_CHAN="${_NVRAM_CS%%/*}"
    if [ "$_NVRAM_WIDTH" = "160" ] && [ -n "$_NVRAM_CHAN" ]; then
        PREFERRED="$_NVRAM_CS"
        DISABLE_FALLBACK=1
        STRICT_STICKY=1
        log 1 "[NVRAM] wl1_chanspec=[$_NVRAM_CS]. Overriding: PREFERRED=[$PREFERRED], DISABLE_FALLBACK=1, STRICT_STICKY=1."
    else
        log 1 "[NVRAM] wl1_chanspec=[$_NVRAM_CS] is not a 160MHz chanspec. Using config defaults [PREFERRED=$PREFERRED]."
    fi
fi

# Derived from PREFERRED - do not edit
# (Placed here, after NVRAM override, so PREFERRED reflects any NVRAM changes)
PREFERRED_CHAN="${PREFERRED%%/*}"
if [ "$PREFERRED_CHAN" -ge 36 ] && [ "$PREFERRED_CHAN" -le 64 ]; then
    PREF_BLOCK_LO=36; PREF_BLOCK_HI=64
else
    PREF_BLOCK_LO=100; PREF_BLOCK_HI=128
fi

# -----------------------------------------
# 3. Self-registration
# -----------------------------------------
if [ "$MANAGE_CRON" = "1" ]; then
    manage_cron_job "add"
    manage_init_start "add"
else
    manage_cron_job "remove"
    manage_init_start "remove"
fi

# -----------------------------------------
# 4. Interface detection
# -----------------------------------------
if [ -z "$IFACE" ]; then
    for _if in $(nvram get sta_phy_ifnames 2>/dev/null); do
        _chan=$(wl -i "$_if" chanspec 2>/dev/null | awk '{print $1}')
        _chan="${_chan%%/*}"
        [ -n "$_chan" ] && [ "$_chan" -ge 36 ] && [ "$_chan" -le 165 ] 2>/dev/null || continue
        if [ -z "$IFACE" ]; then
            IFACE="$_if"
        else
            log 1 "[WARN] Multiple 5GHz interfaces found. Using [$IFACE]. Set IFACE manually to override."
            break
        fi
    done
    if [ -z "$IFACE" ]; then
        log 1 "[__END] No 5GHz interface found. Exiting."
        exit 1
    fi
    log 1 "[INFO] Auto-detected 5GHz interface [$IFACE]."
fi

# -----------------------------------------
# 5. Cooldown check
# -----------------------------------------
if [ -f "$LOCK_FILE" ]; then
    LAST_ACTION=$(cat "$LOCK_FILE")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_ACTION))
    if [ "$ELAPSED" -lt "$COOLDOWN" ]; then
        log 1 "[__END] Cooldown active. ${ELAPSED}s/${COOLDOWN}s elapsed."
        exit 0
    fi
fi

# -----------------------------------------
# 6. Radio up check
# -----------------------------------------
IS_UP=$(wl -i "$IFACE" isup 2>/dev/null)
if [ "$IS_UP" != "1" ]; then
    log 1 "[__END] Radio $IFACE is [DOWN]. Exiting."
    exit 0
fi

# -----------------------------------------
# 7. Read current radio state
# -----------------------------------------
CURRENT_SPEC=$(wl -i "$IFACE" chanspec 2>/dev/null | awk '{print $1}')
CURRENT_CHAN="${CURRENT_SPEC%%/*}"
CURRENT_WIDTH="${CURRENT_SPEC#*/}"

# -----------------------------------------
# 8. Check if already on 160MHz
#
# STRICT_STICKY=1 (strongest): Must be on the exact PREFERRED chanspec.
#   Any 160MHz chanspec that is not PREFERRED triggers a move back, even
#   within the same block. Evaluated before DISABLE_FALLBACK.
#
# DISABLE_FALLBACK=1 (independent of STRICT_STICKY): Must be on 160MHz within
#   the preferred block's channel range. A different channel in the same block
#   is acceptable; a different block triggers a move back to PREFERRED.
#
# DISABLE_FALLBACK=0 + STRICT_STICKY=0 (default): Any 160MHz chanspec is fine.
#   Exit early with no action.
# -----------------------------------------
if [ "$CURRENT_WIDTH" = "160" ]; then
    if [ "$STRICT_STICKY" = "1" ] && [ "$CURRENT_SPEC" != "$PREFERRED" ]; then
        log 1 "[INFO] On 160MHz [$CURRENT_SPEC] but not on exact preferred [$PREFERRED] (STRICT_STICKY). Jumping back."
        log_dfs_status "PRE-MOVE"
        if try_dfs_ap_move "$PREFERRED"; then
            date +%s > "$LOCK_FILE"
            log 1 "[INFO] Move to [$PREFERRED] accepted. Result confirmed on next cron run."
        else
            log 1 "[NOTICE] Move to [$PREFERRED] rejected. Holding until next cron run."
        fi
    elif [ "$DISABLE_FALLBACK" = "1" ] && \
       { [ "$CURRENT_CHAN" -lt "$PREF_BLOCK_LO" ] || [ "$CURRENT_CHAN" -gt "$PREF_BLOCK_HI" ]; }; then
        log 1 "[INFO] On 160MHz [$CURRENT_SPEC] but outside preferred block (${PREF_BLOCK_LO}-${PREF_BLOCK_HI}). Jumping back to [$PREFERRED]."
        log_dfs_status "PRE-MOVE"
        if try_dfs_ap_move "$PREFERRED"; then
            date +%s > "$LOCK_FILE"
            log 1 "[INFO] Move to [$PREFERRED] accepted. Result confirmed on next cron run."
        else
            log 1 "[NOTICE] Move to [$PREFERRED] rejected. Holding until next cron run."
        fi
    else
        log 1 "[__END] Already on 160MHz [$CURRENT_SPEC]. No action needed."
    fi
    finish
fi
log 1 "[INFO] Current width is [${CURRENT_WIDTH}MHz]. Attempting recovery."
log_dfs_status "PRE-MOVE"

# -----------------------------------------
# 9. Determine PRIMARY and FALLBACK targets.
#
# DISABLE_FALLBACK=1: Always attempt PREFERRED only. No cross-block fallback.
# DISABLE_FALLBACK=0: Derive PRIMARY from current block; try FALLBACK if rejected.
#   - Current chan 36-64   -> PRIMARY=36/160,  FALLBACK=100/160
#   - Current chan 100-128 -> PRIMARY=100/160, FALLBACK=36/160
#   - Outside both blocks  -> PRIMARY=PREFERRED, FALLBACK=opposite block
# -----------------------------------------
if [ "$DISABLE_FALLBACK" = "1" ]; then
    PRIMARY="$PREFERRED"
    FALLBACK=""
    log 1 "[INFO] Fallback disabled. Will only attempt PREFERRED [$PRIMARY]."
else
    if [ "$CURRENT_CHAN" -ge 36 ] && [ "$CURRENT_CHAN" -le 64 ]; then
        log 1 "[INFO] Channel $CURRENT_CHAN is in 36/160 block."
        PRIMARY="36/160"
        FALLBACK="100/160"
    elif [ "$CURRENT_CHAN" -ge 100 ] && [ "$CURRENT_CHAN" -le 128 ]; then
        log 1 "[INFO] Channel $CURRENT_CHAN is in 100/160 block."
        PRIMARY="100/160"
        FALLBACK="36/160"
    else
        log 1 "[INFO] Channel $CURRENT_CHAN is outside 160MHz blocks."
        PRIMARY="$PREFERRED"
        FALLBACK=$([ "$PREFERRED" = "100/160" ] && echo "36/160" || echo "100/160")
    fi
fi

log 1 "[INFO] Trying primary [$PRIMARY]."
if ! try_dfs_ap_move "$PRIMARY"; then
    if [ "$DISABLE_FALLBACK" = "1" ]; then
        log 1 "[INFO] Fallback disabled. No fallback attempted."
    else
        log 1 "[INFO] Falling back to [$FALLBACK]."
        try_dfs_ap_move "$FALLBACK"
    fi
fi

# -----------------------------------------
# 10. If no move was accepted, log and hold
# -----------------------------------------
if [ "$MOVED" = "0" ]; then
    log 1 "[NOTICE] All dfs_ap_move attempts rejected. Holding until next cron run."
    finish
fi

# -----------------------------------------
# 11. Stamp lockfile and wait for CAC to complete
# -----------------------------------------
date +%s > "$LOCK_FILE"
log 1 "[INFO] Waiting ${CAC_WAIT}s for CAC to complete..."
log_dfs_status "BGDFS-TRANSITION"
sleep 10
log_dfs_status "DURING-CAC"
sleep $((CAC_WAIT - 10))

# -----------------------------------------
# 12. Verify result
# -----------------------------------------
POST_SPEC=$(wl -i "$IFACE" chanspec 2>/dev/null | awk '{print $1}')
POST_WIDTH="${POST_SPEC#*/}"
log_dfs_status "POST-CAC"
log 1 "[INFO] Post-CAC state [CHANSPEC=$POST_SPEC]"

if [ "$POST_WIDTH" = "160" ]; then
    log 1 "[OK] Recovery successful. Now on [$POST_SPEC]."
else
    log 1 "[NOTICE] Recovery failed. Still on [$POST_SPEC]."
    if [ "$DISABLE_FALLBACK" = "1" ]; then
        log 1 "[NOTICE] Fallback disabled. Holding until next cron run."
    else
        log 1 "[NOTICE] Trying fallback [$FALLBACK]."
        if try_dfs_ap_move "$FALLBACK"; then
            date +%s > "$LOCK_FILE"
            log 1 "[INFO] Fallback [$FALLBACK] accepted. Result confirmed on next cron run."
        else
            log 1 "[NOTICE] Fallback [$FALLBACK] also rejected. Holding until next cron run."
        fi
    fi
fi

# -----------------------------------------
# 13. Rotate log and end
# -----------------------------------------
finish
