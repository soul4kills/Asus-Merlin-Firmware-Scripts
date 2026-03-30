#!/bin/sh
# hindsight160.sh - Keep 5GHz radio(s) on 160MHz
# Dual-band: one 5GHz radio, full fallback logic.
# Tri-band:  two 5GHz radios, fixed block assignments, no fallback.
# Mode is determined by IFACE1/IFACE2 config or auto-detection.
# Runs via cron every 30 minutes (1,31 * * * *)

# Script name determined automatically
SCRIPT_NAME="${0##*/}"
SCRIPT_NAME="${SCRIPT_NAME%.*}"

IFACE1=""               # Leave empty for auto-detection.
                        # If only IFACE1 is set, dual-band mode is assumed.
                        # If both IFACE1 and IFACE2 are set, tri-band mode is assumed.
IFACE2=""               # Second 5GHz interface for tri-band mode only.

# Dual-band options (ignored in tri-band mode)
PREFERRED="100/160"     # Preferred 160MHz target (may be overridden by NVRAM if wl1_chanspec != 0/AUTO)
DISABLE_FALLBACK=0      # 1=always stay in PREFERRED block, never try the other 160MHz block

# Shared options
COOLDOWN=60             # Minimum seconds between recovery attempts (per radio in tri-band)
CAC_POLL=60             # Seconds between each CAC status poll
CAC_TIMEOUT=660         # Maximum seconds to wait for CAC completion before giving up
                        # 60s = standard DFS channels, 600s = weather radar channels (120/124/128)
                        # 660s default covers all regions with a one poll interval buffer
STRICT_STICKY=0         # 0=any 160MHz channel within assigned block is acceptable (default)
                        # 1=must be on the exact preferred chanspec; any deviation triggers a move
                        # Note: automatically set to 1 when NVRAM wl1_chanspec overrides PREFERRED (dual-band only)
MANAGE_CRON=1           # Set to 1/0 to add/remove cron and init-start entries
VERBOSE=2               # 0=silent, 1=basic logging, 2=verbose (includes DFS status blocks)
LOG_ROTATE_RAM=1        # 0=use temp file (safer), 1=use RAM (no temp file on disk)
LOG_LINES=200

# Derived from SCRIPT_NAME - do not edit
SCRIPT_PATH="/jffs/scripts/${SCRIPT_NAME}.sh"
LOG_FILE="/jffs/scripts/${SCRIPT_NAME}.log"
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

finish() {
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
    local iface="$1"
    local label="$2"
    local status
    status=$(wl -i "$iface" dfs_ap_move 2>/dev/null)
    log 2 "[$iface][DFS_STATUS:$label]"
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

try_dfs_ap_move() {
    local iface="$1"
    local target="$2"
    local err result
    err=$(wl -i "$iface" dfs_ap_move "$target" 2>&1)
    result=$?
    if [ "$result" -eq 0 ]; then
        log 1 "[$iface][ACTION] dfs_ap_move accepted [$target]. Background CAC started."
        return 0
    else
        log 1 "[$iface][INFO] dfs_ap_move rejected [$target]: $err"
        return 1
    fi
}

# Poll dfs_ap_move status until move status=-1 (CAC complete) or CAC_TIMEOUT is reached.
# Returns 0 if CAC completed successfully, 1 if timed out.
wait_for_cac() {
    local iface="$1"
    local elapsed=0
    local status move_status

    log 1 "[$iface] Polling for CAC completion (poll=${CAC_POLL}s, timeout=${CAC_TIMEOUT}s)..."
    log_dfs_status "$iface" "BGDFS-TRANSITION"

    sleep 5

    while [ "$elapsed" -lt "$CAC_TIMEOUT" ]; do
        sleep "$CAC_POLL"
        elapsed=$((elapsed + CAC_POLL))
        status=$(wl -i "$iface" dfs_ap_move 2>/dev/null)
        move_status=$(echo "$status" | grep -o "move status=[0-9-]*" | head -1)
        log 1 "[$iface] CAC poll ${elapsed}s: $move_status"
        if [ "$VERBOSE" -ge 2 ]; then
            log 2 "[$iface][DFS_STATUS:POLL-${elapsed}s]"
            echo "$status" | while IFS= read -r line; do
                echo "$(date):   $line" >> "$LOG_FILE"
            done
        fi
        if echo "$move_status" | grep -q "move status=-1"; then
            log 1 "[$iface] CAC complete after ${elapsed}s."
            return 0
        fi
    done

    log 1 "[$iface] CAC timed out after ${elapsed}s. Holding until next cron run."
    return 1
}
# -----------------------------------------
# 2. Unified process_radio
# Args: iface, preferred, block_lo, block_hi, fallback
#   fallback: empty string in tri-band mode (no cross-block attempts)
#   lock_file: derived from iface name
# -----------------------------------------
process_radio() {
    local iface="$1"
    local preferred="$2"
    local block_lo="$3"
    local block_hi="$4"
    local fallback="$5"
    local lock_file="/tmp/${SCRIPT_NAME}_${iface}.last_action"

    log 1 "[$iface] RANGE=[${block_lo}-${block_hi}], PREFERRED=[$preferred]"

    # Cooldown check
    if [ -f "$lock_file" ]; then
        local last_action now elapsed
        last_action=$(cat "$lock_file")
        now=$(date +%s)
        elapsed=$((now - last_action))
        if [ "$elapsed" -lt "$COOLDOWN" ]; then
            log 1 "[$iface] Cooldown active. ${elapsed}s/${COOLDOWN}s elapsed. Skipping."
            return
        fi
    fi

    # Radio up check
    local is_up
    is_up=$(wl -i "$iface" isup 2>/dev/null)
    if [ "$is_up" != "1" ]; then
        log 1 "[$iface] Radio is DOWN. Skipping."
        return
    fi

    # Read current radio state
    local current_spec current_chan current_width
    current_spec=$(wl -i "$iface" chanspec 2>/dev/null | awk '{print $1}')
    current_chan="${current_spec%%/*}"
    current_width="${current_spec#*/}"

    # Already on 160MHz
    if [ "$current_width" = "160" ]; then
        if [ "$STRICT_STICKY" = "1" ] && [ "$current_spec" != "$preferred" ]; then
            log 1 "[$iface] On 160MHz [$current_spec] not preferred (STRICT_STICKY). Jumping back to [$preferred]."
            log_dfs_status "$iface" "PRE-MOVE"
            if try_dfs_ap_move "$iface" "$preferred"; then
                date +%s > "$lock_file"
                log 1 "[$iface] Move to [$preferred] accepted. Result confirmed on next cron run."
            else
                log 1 "[$iface] Move to [$preferred] rejected. Holding until next cron run."
            fi
        elif [ "$current_chan" -lt "$block_lo" ] || [ "$current_chan" -gt "$block_hi" ]; then
            log 1 "[$iface] On 160MHz [$current_spec] but outside assigned block (${block_lo}-${block_hi}). Jumping to [$preferred]."
            log_dfs_status "$iface" "PRE-MOVE"
            if try_dfs_ap_move "$iface" "$preferred"; then
                date +%s > "$lock_file"
                log 1 "[$iface] Move to [$preferred] accepted. Result confirmed on next cron run."
            else
                log 1 "[$iface] Move to [$preferred] rejected. Holding until next cron run."
            fi
        else
            log 1 "[$iface] Already on 160MHz [$current_spec] in preferred block. No action needed."
        fi
        return
    fi

    # Not on 160MHz - determine recovery target
    local target
    if [ "$STRICT_STICKY" = "1" ]; then
        target="$preferred"
    elif [ "$current_chan" -ge "$block_lo" ] && [ "$current_chan" -le "$block_hi" ]; then
        target="${current_chan}/160"
    else
        target="$preferred"
    fi

    log 1 "[$iface] Current width [${current_width}MHz]. Attempting recovery to [$target]."
    log_dfs_status "$iface" "PRE-MOVE"

    local moved=0
    if try_dfs_ap_move "$iface" "$target"; then
        moved=1
    elif [ -n "$fallback" ]; then
        log 1 "[$iface] Falling back to [$fallback]."
        if try_dfs_ap_move "$iface" "$fallback"; then
            moved=1
            target="$fallback"
        fi
    fi

    if [ "$moved" = "0" ]; then
        log 1 "[$iface] All dfs_ap_move attempts rejected. Holding until next cron run."
        return
    fi

    date +%s > "$lock_file"

    if ! wait_for_cac "$iface"; then
        return
    fi

    local post_spec post_width
    post_spec=$(wl -i "$iface" chanspec 2>/dev/null | awk '{print $1}')
    post_width="${post_spec#*/}"
    log_dfs_status "$iface" "POST-CAC"
    log 1 "[$iface] Post-CAC state [CHANSPEC=$post_spec]"

    if [ "$post_width" = "160" ]; then
        log 1 "[$iface] Recovery successful. Now on [$post_spec]."
    else
        log 1 "[$iface] Recovery failed. Still on [$post_spec]."
        if [ -n "$fallback" ] && [ "$target" != "$fallback" ]; then
            log 1 "[$iface] Trying fallback [$fallback]."
            if try_dfs_ap_move "$iface" "$fallback"; then
                date +%s > "$lock_file"
                log 1 "[$iface] Fallback [$fallback] accepted. Result confirmed on next cron run."
            else
                log 1 "[$iface] Fallback [$fallback] also rejected. Holding until next cron run."
            fi
        else
            log 1 "[$iface] Holding until next cron run."
        fi
    fi
}

# -----------------------------------------
# 3. Mode runners
# -----------------------------------------
run_dualband() {
    local iface="$1"
    local pref_chan pref_block_lo pref_block_hi fallback
    pref_chan="${PREFERRED%%/*}"
    if [ "$pref_chan" -ge 36 ] && [ "$pref_chan" -le 64 ]; then
        pref_block_lo=36; pref_block_hi=64
    else
        pref_block_lo=100; pref_block_hi=128
    fi
    if [ "$DISABLE_FALLBACK" = "1" ]; then
        fallback=""
    else
        fallback=$([ "$PREFERRED" = "100/160" ] && echo "36/160" || echo "100/160")
    fi
    process_radio "$iface" "$PREFERRED" "$pref_block_lo" "$pref_block_hi" "$fallback"
}

run_triband() {
    process_radio "$IFACE1" "36/160"  36  64  ""
    sleep 10
    process_radio "$IFACE2" "100/160" 100 128 ""
}

# -----------------------------------------
# 4. NVRAM config override (dual-band only)
# -----------------------------------------
nvram_override() {
    local nvram_cs
    nvram_cs=$(nvram get wl1_chanspec 2>/dev/null | tr -d ' ')
    if [ -z "$nvram_cs" ] || [ "$nvram_cs" = "0" ]; then
        log 1 "[NVRAM] wl1_chanspec=auto (0). Using config defaults [PREFERRED=$PREFERRED]."
    elif [ "${nvram_cs#*/}" = "160" ]; then
        PREFERRED="$nvram_cs"
        DISABLE_FALLBACK=1
        STRICT_STICKY=1
        log 1 "[NVRAM] wl1_chanspec=[$nvram_cs]. Overriding: PREFERRED=[$PREFERRED], DISABLE_FALLBACK=1, STRICT_STICKY=1."
    else
        log 1 "[NVRAM] wl1_chanspec=[$nvram_cs] not 160MHz chanspec. Using config defaults [PREFERRED=$PREFERRED]."
    fi
}

# -----------------------------------------
# 5. Self-registration
# -----------------------------------------
if [ "$MANAGE_CRON" = "1" ]; then
    manage_cron_job "add"
    manage_init_start "add"
else
    manage_cron_job "remove"
    manage_init_start "remove"
fi

# -----------------------------------------
# 6. Interface detection and mode selection
# -----------------------------------------
if [ -n "$IFACE1" ] && [ -n "$IFACE2" ]; then
    log 1 "[INFO] Tri-band mode. IFACE1=[$IFACE1], IFACE2=[$IFACE2]."
    run_triband

elif [ -n "$IFACE1" ] && [ -z "$IFACE2" ]; then
    log 1 "[INFO] Dual-band mode. IFACE1=[$IFACE1]."
    nvram_override
    run_dualband "$IFACE1"

else
    _count=0
    for _if in $(nvram get wl_ifnames 2>/dev/null); do
        _chan=$(wl -i "$_if" chanspec 2>/dev/null | awk '{print $1}')
        _chan="${_chan%%/*}"
        [ -n "$_chan" ] && [ "$_chan" -ge 36 ] && [ "$_chan" -le 165 ] 2>/dev/null || continue
        _count=$((_count + 1))
        [ "$_count" -eq 1 ] && IFACE1="$_if"
        [ "$_count" -eq 2 ] && IFACE2="$_if"
    done

    if [ "$_count" -eq 0 ]; then
        log 1 "[__END] No 5GHz interfaces found. Exiting."
        exit 1
    elif [ "$_count" -eq 1 ]; then
        log 1 "[INFO] Auto-detected dual-band mode. IFACE1=[$IFACE1]."
        nvram_override
        run_dualband "$IFACE1"
    else
        log 1 "[INFO] Auto-detected tri-band mode. IFACE1=[$IFACE1], IFACE2=[$IFACE2]."
        run_triband
    fi
fi

# -----------------------------------------
# 7. Rotate log and end
# -----------------------------------------
finish
