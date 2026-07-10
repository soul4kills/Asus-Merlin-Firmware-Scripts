#!/bin/sh
# hindsight160.sh - Keep 5GHz radio(s) on 160MHz
# Dual-band: one 5GHz radio, full fallback logic.
# Tri-band:  two 5GHz radios, fixed block assignments, no fallback.
# Mode is determined by IFACE1/IFACE2 config or auto-detection.
# Runs via cron every 30 minutes (1,31 * * * *)
#
# Usage:
# hindsight160.sh           - Execute script or Open configuration menu
# hindsight160.sh menu      - Open configuration menu directly
# hindsight160.sh exec      - Run script (used by cron)
# hindsight160.sh install	- Creates cron job & init-start entries
# hindsight160.sh uninstall	- Removes cron job & init-start entries

# Script name determined automatically
SCRIPT_NAME="${0##*/}"
SCRIPT_NAME="${SCRIPT_NAME%.*}"

ENABLE_MENU=0           # Set to true to enable menu on direct execution (e.g. via SSH)
                        # Menu can also be accessed via "hindsight160.sh menu" regardless of this setting.
IFACE1=""               # Leave empty for auto-detection.
                        # If only IFACE1 is set, dual-band mode is assumed.
                        # If both IFACE1 and IFACE2 are set, tri-band mode is assumed.
IFACE2=""               # Second 5GHz interface for tri-band mode only.

# Dual-band options (ignored in tri-band mode)
PREFERRED="100/160"     # Preferred 160MHz target (may be overridden by NVRAM if wl1_chanspec != 0/AUTO)
ENABLE_FALLBACK=1       # 0=always stay in PREFERRED range, never try the other 160MHz block
                        # 1=fallback to alternate 160MHz range if PREFERRED fails
STRICT_STICKY=1         # 0=any 160MHz channel within the assigned block is acceptable (default)
                        # 1=must be on the exact preferred chanspec; any deviation triggers a move
                        # Note: automatically sets to 1 when NVRAM wl1_chanspec is set to FIXED channel (dual-band only)

# Shared options
REQUIRE_160_CLIENT=1    # 0=skip the 160MHz-capable-client check entirely; always attempt recovery
                        # 1=only attempt recovery when an associated client advertises SGI160 (default)
COOLDOWN=60             # Minimum seconds between recovery attempts (per radio in tri-band)
CAC_POLL=60             # Seconds between each CAC status poll
CAC_TIMEOUT=660         # Maximum seconds to wait for CAC completion before giving up
                        # 60s = standard DFS channels, 600s = weather radar channels (120/124/128)
                        # 660s default covers all regions with a one poll interval buffer
MANAGE_CRON=1           # Set to 1/0 to add/remove cron and init-start entries
VERBOSE=2               # 0=silent, 1=basic logging, 2=verbose (includes DFS status blocks)
LOG_ROTATE_RAM=1        # 0=use temp file (safer), 1=use RAM (no temp file on disk)
LOG_LINES=100

# Derived from SCRIPT_NAME - do not edit
SCRIPT_PATH="/jffs/scripts/${SCRIPT_NAME}.sh"
LOG_FILE="/jffs/scripts/${SCRIPT_NAME}.log"
INIT_START="/jffs/scripts/init-start"

# -----------------------------------------
# 1. Core functions
# -----------------------------------------

log() {
    local level="$1"
    local message="$2"
    [ "$VERBOSE" -lt "$level" ] && return 0
    echo "$(date): $message" >> "$LOG_FILE"
}

finish() {
    if [ "$VERBOSE" -eq 0 ]; then
        exit 0
    fi

    if [ -f "$LOG_FILE" ]; then
        if [ "$LOG_ROTATE_RAM" = "1" ]; then
            local content
            content=$(tail -n "$LOG_LINES" "$LOG_FILE")
            echo "$content" > "$LOG_FILE"
        else
            tail -n "$LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" &&
            mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    else
        : > "$LOG_FILE"
    fi
    exit 0
}

log_dfs_status() {
    [ "$VERBOSE" -lt 2 ] && return 0
    local iface="$1" label="$2" status
    status=$(wl -i "$iface" dfs_ap_move 2>/dev/null)
    log 2 "[$iface][DFS:$label]"
    echo "$status" | while IFS= read -r line; do
        echo "$(date):   $line" >> "$LOG_FILE"
    done
}

manage_cron_job() {
    local action="$1"
    local cron_schedule="1,31 * * * * $SCRIPT_PATH exec"
    if [ "$action" = "add" ]; then
        if ! cru l 2>/dev/null | grep -q "$SCRIPT_NAME"; then
            cru a "$SCRIPT_NAME" "$cron_schedule"
            log 1 "[ACTION] Added cron job '$SCRIPT_NAME'."
        fi
    elif [ "$action" = "remove" ]; then
        if cru l 2>/dev/null | grep -q "$SCRIPT_NAME"; then
            cru d "$SCRIPT_NAME"
            log 1 "[ACTION] Removed cron job '$SCRIPT_NAME'."
        fi
    fi
}

manage_init_start() {
    local action="$1"
    local entry="cru a \"$SCRIPT_NAME\" \"1,31 * * * * $SCRIPT_PATH exec\""
    if [ "$action" = "add" ]; then
        if [ ! -f "$INIT_START" ]; then
            printf '#!/bin/sh\n%s\n' "$entry" > "$INIT_START"
            chmod 755 "$INIT_START"
            log 1 "[ACTION] Created '$INIT_START' with cron entry."
        elif ! grep -qF "$entry" "$INIT_START"; then
            echo "$entry" >> "$INIT_START"
            log 1 "[ACTION] Added cron entry to '$INIT_START'."
        fi
    elif [ "$action" = "remove" ]; then
        if [ -f "$INIT_START" ] && grep -qF "$entry" "$INIT_START"; then
            sed -i "\|$SCRIPT_PATH|d" "$INIT_START"
            log 1 "[ACTION] Removed cron entry from '$INIT_START'."
        fi
    fi
}

# Sets MOVED=1 if accepted, MOVED=0 if rejected. Returns 0/1 accordingly.
try_dfs_ap_move() {
    local iface="$1" target="$2" err result
    err=$(wl -i "$iface" dfs_ap_move "$target" 2>&1)
    result=$?
    if [ "$result" -eq 0 ]; then
        log 3 "[$iface][ACTION] dfs_ap_move [$target] accepted. CAC started."
        MOVED=1; return 0
    else
        log 1 "[$iface][WARN] dfs_ap_move [$target] rejected: $err"
        MOVED=0; return 1
    fi
}

# Polls until CAC completes (move status=-1) or CAC_TIMEOUT is reached.
# Returns 0 on success, 1 on timeout.
wait_for_cac() {
    local iface="$1" elapsed=0 status move_status
    log_dfs_status "$iface" "POLL-START"

    # Early abort check
    sleep 5
    status=$(wl -i "$iface" dfs_ap_move 2>/dev/null)
    if echo "$status" | grep -q "move status=3"; then
        # log_dfs_status "$iface" "EARLY-EXIT"
        log 1 "[$iface][WARN] CAC aborted early (move status=3) after 5s."
        return 1
    elif echo "$status" | grep -q "move status=-1"; then
        # log_dfs_status "$iface" "EARLY-EXIT"
        log 1 "[$iface][WARN] CAC complete after 5s."
        return 0
    fi

    while [ "$elapsed" -lt "$CAC_TIMEOUT" ]; do
        sleep "$CAC_POLL"
        elapsed=$((elapsed + CAC_POLL))
        status=$(wl -i "$iface" dfs_ap_move 2>/dev/null)
        move_status=$(echo "$status" | grep -o "move status=[0-9-]*" | head -1)
        if [ "$VERBOSE" -ge 2 ]; then
            log 2 "[$iface][DFS:POLL-${elapsed}s]"
            echo "$status" | while IFS= read -r line; do
                echo "$(date):   $line" >> "$LOG_FILE"
            done
        fi
        echo "$move_status" | grep -q "move status=-1" && {
            log 1 "[$iface] CAC complete after ${elapsed}s."
            return 0
        }
        echo "$move_status" | grep -q "move status=3" && {
            log 1 "[$iface][WARN] CAC aborted (move status=3) after ${elapsed}s."
            return 1
        }
    done
    log 1 "[$iface][WARN] CAC timed out after ${elapsed}s."
    return 1
}

# Client-capability gate. Controlled entirely by REQUIRE_160_CLIENT.
# REQUIRE_160_CLIENT=0 -> always returns 0 (gate bypassed, recovery always attempted).
# REQUIRE_160_CLIENT=1 (default) -> returns 0 if at least one associated client
#   advertises SGI160 in VHT caps. Only if no such client is found does it then
#   check whether the current channel is above 128 (non-DFS upper UNII-3
#   channels in most regions, e.g. 149-165); if so, the gate still passes.
# Returns 1 if the gate is not satisfied (caller should skip this run).
is_160_active_or_capable() {
    local iface="$1" info current_chan

    # Bypass check if REQUIRE_160_CLIENT=0, allowing recovery even with no 160MHz-capable clients.
    if [ "$REQUIRE_160_CLIENT" != "1" ]; then
        log 1 "[$iface] Client capability check bypassed (REQUIRE_160_CLIENT=0)."
        return 0
    fi

    # No connected clients will produce an error -> skip recovery as no clients are present to benefit from 160MHz.
    info=$(wl -i "$iface" assoclist 2>/dev/null | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}' 2>/dev/null | xargs -r -I {} wl -i "$iface" sta_info {} 2>/dev/null) || return 1

    if echo "$info" | grep -qE "SGI160"; then
        log 3 "[$iface] 160MHz-capable client found."
        return 0
    fi

    # If no 160MHz-capable clients are found, check if the current channel is above 128. If so, bypass the client-capability check and recover to 160MHz.
    current_chan=$(wl -i "$iface" chanspec 2>/dev/null | awk '{print $1}')
    current_chan="${current_chan%%/*}"
    if [ "${current_chan:-129}" -gt 128 ] 2>/dev/null; then
        log 3 "[$iface] Channel [$current_chan] above 128. Bypassing client-capability check."
        return 0
    fi

    return 1
}

# -----------------------------------------
# 2. process_radio
#   Args: iface, preferred, block_lo, block_hi, fallback
#   fallback: empty in tri-band or when ENABLE_FALLBACK=0 (no cross-block recovery).
#   lock_file: per-interface, derived from iface name.
#
# Already on 160MHz:
#   STRICT_STICKY=1  -> must match preferred exactly; anything else triggers a move back.
#   fallback=""      -> must stay within [block_lo-block_hi]; outside triggers a move back.
#   otherwise        -> any 160MHz is acceptable; no action.
#
# Not on 160MHz (recovery):
#   Builds an ordered target list to attempt in sequence:
#     1. ${current_chan}/160  if in block and STRICT_STICKY=0 (CAC may already be done)
#     2. preferred            always included
#     3. fallback             if non-empty
#   Duplicate entries (e.g. current_chan/160 == preferred) are suppressed before building.
#   After CAC, if still not on 160MHz and fallback was not the last attempt, tries fallback.
# -----------------------------------------
process_radio() {
    local iface="$1" preferred="$2" block_lo="$3" block_hi="$4" fallback="$5"
    local lock_file="/tmp/${SCRIPT_NAME}_${iface}.last_action"

    # Check for bgdfs160 capability
    wl -i "$iface" cap | grep -q "bgdfs160" && _bgdfs="YES" || _bgdfs="NO"

    log 1 "[$iface] [RANGE=${block_lo}-${block_hi}] [PREFERRED=$preferred] [BGDFS=$_bgdfs]"

    # Cooldown check
    if [ -f "$lock_file" ]; then
        local elapsed=$(($(date +%s) - $(cat "$lock_file")))
        if [ "$elapsed" -lt "$COOLDOWN" ]; then
            log 1 "[$iface][SKIP] Cooldown: ${elapsed}s / ${COOLDOWN}s."
            return
        fi
    fi

    # Radio up check
    if [ "$(wl -i "$iface" isup 2>/dev/null)" != "1" ]; then
        log 1 "[$iface][SKIP] Radio is DOWN."
        return
    fi

    # 160MHz client capability check
    if ! is_160_active_or_capable "$iface"; then
        log 1 "[$iface][SKIP] No 160MHz-capable clients associated."
        return
    fi

    # Read current radio state
    local current_spec current_chan current_width
    current_spec=$(wl -i "$iface" chanspec 2>/dev/null | awk '{print $1}')
    current_chan="${current_spec%%/*}"
    current_width="${current_spec#*/}"

    # Already on 160MHz: check if a move-back is needed
    if [ "$current_width" = "160" ]; then
        local move_reason=""
        if [ "$STRICT_STICKY" = "1" ] && [ "$current_spec" != "$preferred" ]; then
            move_reason="not on exact preferred (STRICT_STICKY=1)"
        elif [ -z "$fallback" ] && \
             { [ "$current_chan" -lt "$block_lo" ] || [ "$current_chan" -gt "$block_hi" ]; }; then
            move_reason="outside assigned block [${block_lo}-${block_hi}]"
        fi

        if [ -n "$move_reason" ]; then
            log 1 "[$iface][WARN] On 160MHz [$current_spec]: $move_reason. Returning to [$preferred]"
            log_dfs_status "$iface" "PRE-MOVE"
            if try_dfs_ap_move "$iface" "$preferred"; then
                date +%s > "$lock_file"
                log 1 "[$iface] Move accepted. Confirming on next run."
            else
                log 1 "[$iface][WARN] Move rejected. Retrying next run."
            fi
        else
            log 1 "[$iface] On 160MHz [$current_spec] No action needed."
        fi
        return
    fi

    # Not on 160MHz: build ordered target list and attempt recovery
    log 1 "[$iface][WARN] On [${current_width}MHz][$current_spec] Attempting recovery."
    log_dfs_status "$iface" "PRE-MOVE"

    local targets="$preferred"
    if [ "$STRICT_STICKY" != "1" ] && \
       [ "$current_chan" -ge "$block_lo" ] && [ "$current_chan" -le "$block_hi" ] && \
       [ "${current_chan}/160" != "$preferred" ]; then
        targets="${current_chan}/160 $preferred"
    fi
    [ -n "$fallback" ] && targets="$targets $fallback"

    local target
    for target in $targets; do
        if try_dfs_ap_move "$iface" "$target"; then
            [ "$target" != "$preferred" ] && \
                log 1 "[$iface] Preferred [$preferred] rejected, falling back to [$target]."
            break
        fi
    done

    if [ "$MOVED" = "0" ]; then
        log 1 "[$iface][WARN] All move attempts rejected. Retrying next run."
        return
    fi

    date +%s > "$lock_file"
    wait_for_cac "$iface" || return

    # Verify post-CAC result
    local post_spec post_width
    post_spec=$(wl -i "$iface" chanspec 2>/dev/null | awk '{print $1}')
    post_width="${post_spec#*/}"

    if [ "$post_width" = "160" ]; then
        log 1 "[$iface] Recovery successful on [$post_spec]"
    else
        log 1 "[$iface][WARN] Recovery failed, still on [$post_spec]"
        if [ -n "$fallback" ] && [ "$target" != "$fallback" ]; then
            if try_dfs_ap_move "$iface" "$fallback"; then
                date +%s > "$lock_file"
                log 1 "[$iface] Fallback [$fallback] accepted. Confirming on next run."
            else
                log 1 "[$iface][WARN] Fallback [$fallback] also rejected. Retrying next run."
            fi
        else
            log 1 "[$iface][WARN] No further options. Retrying next run."
        fi
    fi
}

# -----------------------------------------
# 3. Mode runners
# -----------------------------------------
run_dualband() {
    local iface="$1" pref_chan block_lo block_hi fallback=""
    pref_chan="${PREFERRED%%/*}"
    if [ "$pref_chan" -ge 36 ] && [ "$pref_chan" -le 64 ]; then
        block_lo=36; block_hi=64
    else
        block_lo=100; block_hi=128
    fi
    if [ "$ENABLE_FALLBACK" != "0" ]; then
        [ "$PREFERRED" = "100/160" ] && fallback="36/160" || fallback="100/160"
    fi
    process_radio "$iface" "$PREFERRED" "$block_lo" "$block_hi" "$fallback"
}

run_triband() {
    process_radio "$IFACE1" "36/160"  36  64  ""
    sleep 10
    process_radio "$IFACE2" "100/160" 100 128 ""
}

# -----------------------------------------
# 4. NVRAM config override (dual-band only)
#    Reads wl1_chanspec from NVRAM (the GUI's channel setting).
#    "0"/empty = Auto: use config defaults.
#    Valid */160 chanspec: override PREFERRED, force ENABLE_FALLBACK=0, STRICT_STICKY=1.
#    Anything else: ignore, use config defaults.
# -----------------------------------------
nvram_override() {
    local nvram_cs
    nvram_cs=$(nvram get wl1_chanspec 2>/dev/null | tr -d ' ')
    if [ -z "$nvram_cs" ] || [ "$nvram_cs" = "0" ]; then
        log 1 "[NVRAM] wl1_chanspec=auto. Using defaults [PREFERRED=$PREFERRED]"
    elif [ "${nvram_cs#*/}" = "160" ] && [ -n "${nvram_cs%%/*}" ]; then
        PREFERRED="$nvram_cs"
        ENABLE_FALLBACK=0
        STRICT_STICKY=1
        log 1 "[NVRAM] wl1_chanspec=[$nvram_cs] Overriding: [PREFERRED=$PREFERRED, ENABLE_FALLBACK=0, STRICT_STICKY=1]"
    else
        log 1 "[NVRAM] wl1_chanspec=[$nvram_cs] Not 160MHz chanspec. Using config defaults [PREFERRED=$PREFERRED]"
    fi
}

# -----------------------------------------
# 5. Config menu
# -----------------------------------------

# Writes a new value for VAR back into the script file.
# Handles both quoted strings (VAR="val") and bare integers (VAR=0).
save_config() {
    local var="$1" val="$2"
    if grep -q "^${var}=\"" "$SCRIPT_PATH"; then
        sed -i "s|^\(${var}=\)\"[^\"]*\"|\1\"${val}\"|" "$SCRIPT_PATH"
    else
        sed -i "s|^\(${var}=\)[^ \t#]*|\1${val}|" "$SCRIPT_PATH"
    fi
}

# Prompts to edit a single config value, validates, then saves.
menu_edit() {
    local var="$1" desc="$2" current="$3" type="$4"
    local new_val
    printf '\n  %s\n  Current : %s\n  New value: ' "$desc" "${current:-(empty)}"
    read -r new_val

    case "$type" in
        bool)
            case "$new_val" in
                0|1) ;;
                *) printf '  Error: must be 0 or 1.\n'; sleep 1; return ;;
            esac ;;
        int)
            case "$new_val" in
                *[!0-9]*) printf '  Error: must be a positive integer.\n'; sleep 1; return ;;
            esac ;;
        chanspec)
            case "$new_val" in
                */160) ;;
                *) printf '  Error: must be a 160MHz chanspec (e.g. 36/160).\n'; sleep 1; return ;;
            esac ;;
        str)
            ;;
    esac

    eval "$var=\"\$new_val\""
    save_config "$var" "$new_val"
    printf '  Saved.\n'
    sleep 1
}

show_header() {
    local L1='\033[1;91m'
    local L2='\033[1;91m'
    local L3='\033[0;91m'
    local L4='\033[0;91m'
    local L5='\033[1;31m'
    local L6='\033[1;31m'
    local L7='\033[0;31m'
    local L8='\033[0;31m'
    local L9='\033[2;31m'
    local L10='\033[2;31m'
    local L11='\033[2;31m'
    local Y='\033[1;33m'
    local W='\033[0;37m'
    local R='\033[0m'

    printf '\033c'
    printf "${W} +-----------------------------------------------------------------+\n"
    printf "${W} |                   ${Y}keep 5GHz radio(s) on 160MHz${W}                  |\n"
    printf "${W} |       +- -- - ----------------------------------- - -- -+       |\n"
    printf "${L1}@@@  @@@ @@@ @@@  @@@ @@@@@@@   @@@@@@  @@@  @@@@@@@@ @@@  @@@ @@@@@@\n"
    printf "${L2}@@@  @@@ @@@ @@@@ @@@ @@@@@@@@ @@@@@@@  @@@ @@@@@@@@@ @@@  @@@ @@@@@@\n"
    printf "${L3}@@!  @@@ @@! @@!@!@@@ @@!  @@@ !@@      @@! !@@       @@!  @@@   @@!\n"
    printf "${L4}!@!  @!@ !@! !@!!@!@! !@!  @!@ !@!      !@! !@!       !@!  @!@   !@!\n"
    printf "${L5}@!@!@!@! !!@ @!@ !!@! @!@  !@! !!@@!!   !!@ !@! @!@!@ @!@!@!@!   @!!\n"
    printf "${L6}!!!@!!!! !!! !@!  !!! !@!  !!!  !!@!!!  !!! !!! !!@!! !!!@!!!!   !!!\n"
    printf "${L7}!!:  !!! !!: !!:  !!! !!${L1}@@@${L7}!:!${L1}@@@@@@${L7}!!${L1}@@@@@@${L7}:!!   !!: !!:  !!!   !!:\n"
    printf "${L8}:!:  !:! :!: :!:  !:! :${L2}@@@@${L8} :${L2}@@@@@@@ @@@@@@@@${L8}!:   !:: :!:  !:!   :!:\n"
    printf "${L9}::   ::: ${W}|${L9}::  ::   :: ${L3}@@@!! !@@   ${L9}:  ${L3}@@!  @@@${L9}::: :::: ::   :::    ::\n"
    printf "${L10} :   : : : : ::.   :  ::${L4}!@! !@! ${L10}: :  ${L4}!@!  @!@${L10}:: :: :   :   : :    :${W}|\n"
    printf "${W} |       |              ${L5}!@! @!!@!!!! !@!  !!!${W}           ${Y}by ${W}|       |\n"
    printf "${W} |       +- -- - -------${L6}!!: !:!  !:! !!:  !!!${W}------- - -- -+       |\n"
    printf "${W} | ${Y}[HINDSIGHT160 v1.0]${L7}  :!: :!:  !:! :!:  !:!    ${Y}[soul4kills & AI]${W} |\n"
    printf "${W} +----.-----------------${L8}::: :::: ::: ::::: ::${W}------------------.---+\n"
    printf "${L11}                         ${L9}::  :: : :   : : ::${R}\n"
}

show_menu() {
    local C='\033[1;36m'
    local W='\033[0;37m'

    local choice
    while true; do
        show_header
        printf " +-- Interface Settings (Empty = Auto-Detect Mode) ----------------+\n"
        printf "\n"
        printf "${C}  [1]  IFACE1            : %s\n" "${IFACE1:-(auto)}"
        printf "  [2]  IFACE2            : %s\n" "${IFACE2:-(auto)}"
        printf "${W}        Configure IFACE1 for dual-band, both for tri-band.\n"
        printf "\n"
        printf " +-- Dual-band Settings (Disabled if [GUI/NVRAM] not on "Auto") ---+\n"
        printf "\n"
        printf "${C}  [3]  PREFERRED         : %s\n" "$PREFERRED"
        printf "${W}        Target 160MHz chanspec (e.g. 100/160 or 36/160).\n"
        printf "\n"
        printf "${C}  [4]  ENABLE_FALLBACK   : %s\n" "$ENABLE_FALLBACK"
        printf "${W}        0=stay in preferred channel range only\n"
        printf "        1=fallback to alternate 160MHz range if preferred fails.\n"
        printf "\n"
        printf " +-- Global: Strict_Sticky (Jumps to preferred channel) -----------+\n"
        printf "\n"
        printf "${C}  [5]  STRICT_STICKY     : %s\n" "$STRICT_STICKY"
        printf "${W}        0=if not in preferred channel range. (e.g. 100-128)\n"
        printf "        1=if not on preferred channel. (e.g. 100/160)\n"
        printf "\n"
        printf " +-- Global: Client Gate (Skip client-capability check) -----------+\n"
        printf "\n"
        printf "${C}  [6]  REQUIRE_160_CLIENT: %s\n" "$REQUIRE_160_CLIENT"
        printf "${W}        0=always attempt recovery, even with no 160MHz clients.\n"
        printf "        1=only attempt recovery if a 160MHz-capable client is seen.\n"
        printf "\n"
        printf " +-- Timing -------------------------------------------------------+\n"
        printf "\n"
        printf "${C}  [7]  COOLDOWN          : %ss\n" "$COOLDOWN"
        printf "  [8]  CAC_POLL          : %ss\n" "$CAC_POLL"
        printf "  [9]  CAC_TIMEOUT       : %ss\n" "$CAC_TIMEOUT"
        printf "\n"
        printf "${W} +-- Logging & Maintenance ----------------------------------------+\n"
        printf "\n"
        printf "${C}  [10] MANAGE_CRON       : %s\n" "$MANAGE_CRON"
        printf "  [11] VERBOSE           : %s\n" "$VERBOSE"
        printf "${W}        0=silent  1=basic logging  2=verbose (DFS status blocks).\n"
        printf "\n"
        printf "${C}  [12] LOG_ROTATE_RAM    : %s\n" "$LOG_ROTATE_RAM"
        printf "  [13] LOG_LINES         : %s\n" "$LOG_LINES"
        printf "\n"
        printf "  [a]  About / Help\n"
        printf "  [i]  Install\n"
        printf "  [u]  Uninstall\n"
        printf "  [e]  Exit\n"
        printf "\n"
        printf "${W}  Select option: "
        read -r choice
        case "$choice" in
            1)  menu_edit "IFACE1"             "IFACE1  -  First 5GHz interface (empty = auto-detect)"    "$IFACE1"             "str"      ;;
            2)  menu_edit "IFACE2"             "IFACE2  -  Second 5GHz interface (empty = auto/dual)"     "$IFACE2"             "str"      ;;
            3)  menu_edit "PREFERRED"          "PREFERRED  -  Target chanspec (e.g. 100/160 or 36/160)"   "$PREFERRED"          "chanspec" ;;
            4)  menu_edit "ENABLE_FALLBACK"    "ENABLE_FALLBACK  -  Try other 160MHz block (0/1)"         "$ENABLE_FALLBACK"    "bool"     ;;
            5)  menu_edit "STRICT_STICKY"      "STRICT_STICKY  -  Require exact chanspec match (0/1)"     "$STRICT_STICKY"      "bool"     ;;
            6)  menu_edit "REQUIRE_160_CLIENT" "REQUIRE_160_CLIENT  -  Require 160MHz client to act (0/1)" "$REQUIRE_160_CLIENT" "bool"     ;;
            7)  menu_edit "COOLDOWN"           "COOLDOWN  -  Min seconds between recovery attempts"       "$COOLDOWN"           "int"      ;;
            8)  menu_edit "CAC_POLL"           "CAC_POLL  -  Seconds between CAC status polls"            "$CAC_POLL"           "int"      ;;
            9)  menu_edit "CAC_TIMEOUT"        "CAC_TIMEOUT  -  Max seconds to wait for CAC"              "$CAC_TIMEOUT"        "int"      ;;
            10) menu_edit "MANAGE_CRON"        "MANAGE_CRON  -  Auto-manage cron and init-start (0/1)"    "$MANAGE_CRON"        "bool"     ;;
            11) menu_edit "VERBOSE"            "VERBOSE  -  Log level (0=silent, 1=basic, 2=verbose)"     "$VERBOSE"            "int"      ;;
            12) menu_edit "LOG_ROTATE_RAM"     "LOG_ROTATE_RAM  -  Rotate log in RAM, no temp file (0/1)" "$LOG_ROTATE_RAM"     "bool"     ;;
            13) menu_edit "LOG_LINES"          "LOG_LINES  -  Number of log lines to retain"              "$LOG_LINES"          "int"      ;;
            a) show_about ;;
            i) $SCRIPT_PATH install ;;
            u) $SCRIPT_PATH uninstall ;;
            e|E) break ;;
        esac
    done
}

show_about() {

    show_header
    printf ' +-- About: HINDSIGHT160 v1.0 -------------------------------------+\n'
    printf '\n'
    printf '  Keeps your 5GHz radio(s) on 160MHz by monitoring the current\n'
    printf '  channel width and using BGDFS to move back whenever a radar\n'
    printf '  event knocks you off 160MHz.\n'
    printf '\n'
    printf '  Runs via cron every 30 minutes.\n'
    printf '\n'
    printf ' +-- ! 160mhz Region Limited Bonding Channels ! -------------------+\n'
    printf '\n'
    printf '  If you live in a region with limited 160mhz bonding channels\n'
    printf '  its better to set a fixed channel in your [GUI]. This script\n'
    printf '  will maintain that fixed 160mhz channel.\n'
    printf '\n'
    printf ' +-- Interface Settings -------------------------------------------+\n'
    printf '\n'
    printf '  IFACE1 / IFACE2\n'
    printf '    Leave both empty to let the script auto-detect your 5GHz\n'
    printf '    radio(s) from NVRAM (wl_ifnames).\n'
    printf '\n'
    printf '    Dual-band:  Set IFACE1 only (e.g. eth6).\n'
    printf '    Tri-band:   Set IFACE1 and IFACE2 (e.g. eth6 & eth7).\n'
    printf '    When both are set, tri-band mode is assumed and IFACE1 is\n'
    printf '    locked to the 36-64 block, IFACE2 to the 100-128 block.\n'
    printf '\n'
    printf ' +-- Dual-band Settings -------------------------------------------+\n'
    printf '\n'
    printf '  PREFERRED\n'
    printf '    The 160MHz chanspec you want to stay on, e.g. 100/160 or\n'
    printf '    36/160. This is the first target tried during recovery.\n'
    printf '\n'
    printf '    If the [GUI/NVRAM] channel is a fixed 160MHz channel\n'
    printf '    (not Auto), [GUI/NVRAM] value overrides PREFERRED\n'
    printf '    and also forces STRICT_STICKY=1 and ENABLE_FALLBACK=0.\n'
    printf '\n'
    printf '  ENABLE_FALLBACK\n'
    printf '    0 = Stay strictly within the channel block that contains\n'
    printf '        PREFERRED (36-64 OR 100-128). Never cross blocks.\n'
    printf '    1 = If recovery in the preferred block fails completely,\n'
    printf '        also try the other 160MHz block.\n'
    printf '\n'
    printf '    e.g. PREFERRED=100/160 -> fallback tries 36/160.\n'
    printf '\n'
    printf ' +-- Global Settings ----------------------------------------------+\n'
    printf '\n'
    printf '  STRICT_STICKY\n'
    printf '    Controls how strictly the script enforces the target channel\n'
    printf '    when you are already on 160MHz.\n'
    printf '\n'
    printf '    0 = Relaxed. Any 160MHz channel within the assigned block\n'
    printf '        (e.g. 100-128) is acceptable.\n'
    printf '    1 = Strict. Must be on the exact PREFERRED chanspec (e.g.\n'
    printf '        100/160). Any drift within the block triggers a move back.\n'
    printf '\n'
    printf '        Enforced when [GUI/NVRAM] set to fixed channel.\n'
    printf '\n'
    printf '  REQUIRE_160_CLIENT\n'
    printf '    0 = Bypass the client-capability gate entirely. The script\n'
    printf '        will attempt recovery/move-back logic every run\n'
    printf '        regardless of whether any associated client advertises\n'
    printf '        SGI160. Useful if you want 160MHz maintained purely for\n'
    printf '        link headroom, future clients, or if your client\n'
    printf '        detection is unreliable.\n'
    printf '    1 = Default. Only attempt recovery/move-back when at least\n'
    printf '        one associated client advertises SGI160 in its VHT caps.\n'
    printf '\n'
    printf ' +-- Timing -------------------------------------------------------+\n'
    printf '\n'
    printf '  COOLDOWN\n'
    printf '    Minimum seconds that must pass before the script will attempt.\n'
    printf '    Default: 60s.\n'
    printf '\n'
    printf '  CAC_POLL\n'
    printf '    How often (in seconds) the script checks whether CAC\n'
    printf '    (Channel Availability Check) has finished after a DFS move\n'
    printf '    is accepted. Needs to be greater than 60s.\n'
    printf '    Default: 60s.\n'
    printf '\n'
    printf '  CAC_TIMEOUT\n'
    printf '    Maximum seconds to wait for CAC to complete before giving up.\n'
    printf '    Standard DFS channels take ~60s;\n'
    printf '    weather radar channels (120/124/128) can take up to 600s.\n'
    printf '    Default: 660s (600s + one poll buffer).\n'
    printf '\n'
    printf ' +-- Logging & Maintenance ----------------------------------------+\n'
    printf '\n'
    printf '  MANAGE_CRON\n'
    printf '    1 = Script automatically adds itself to cron and to init-start\n'
    printf '         so it survives reboots.\n'
    printf '    0 = Script automatically removes its cron and init-start\n'
    printf '        entries on the next exec run.\n'
    printf '\n'
    printf '  VERBOSE\n'
    printf '    0 = Silent. Nothing is written to the log file.\n'
    printf '    1 = Basic. Logs key actions, warnings, and state changes.\n'
    printf '    2 = Verbose. Also logs full DFS status blocks (dfs_ap_move\n'
    printf '        output) at each poll interval. Useful for diagnosing\n'
    printf '        why a CAC is taking long or failing.\n'
    printf '\n'
    printf '  LOG_ROTATE_RAM\n'
    printf '    1 = Log rotation happens entirely in RAM.\n'
    printf '    0 = Uses a .tmp file during rotation, then replaces the log.\n'
    printf '        Slightly safer if power is lost mid-write.\n'
    printf '\n'
    printf '  LOG_LINES\n'
    printf '    How many lines to keep in the log file after each rotation.\n'
    printf '\n'
    printf ' +-----------------------------------------------------------------+\n'
    printf '\n'
    printf '  Press Any Key to return to the menu...'
    read -n 1 -r -s
}

# -----------------------------------------
# 6. Dispatch
# -----------------------------------------
case "$1" in
    exec)
        reg_action="remove"
        [ "$MANAGE_CRON" = "1" ] && reg_action="add"
        manage_cron_job "$reg_action"
        manage_init_start "$reg_action"

        if [ -n "$IFACE1" ] && [ -n "$IFACE2" ]; then
            log 1 "[INFO] Tri-band mode. IFACE1=[$IFACE1], IFACE2=[$IFACE2]"
            run_triband

        elif [ -n "$IFACE1" ]; then
            log 1 "[INFO] Dual-band mode. IFACE1=[$IFACE1]"
            nvram_override
            run_dualband "$IFACE1"

        else
            _count=0
            for _if in $(nvram get wl_ifnames 2>/dev/null); do
                wl -i "$_if" band 2>/dev/null | grep -q "^a$" || continue
                _count=$((_count + 1))
                [ "$_count" -eq 1 ] && IFACE1="$_if"
                [ "$_count" -eq 2 ] && IFACE2="$_if"
            done

            case "$_count" in
                0) log 1 "[WARN] No 5GHz interfaces found. Exiting."; exit 1 ;;
                1) log 1 "[INFO] Auto-detected dual-band. IFACE1=[$IFACE1]"
                   nvram_override; run_dualband "$IFACE1" ;;
                *) log 1 "[INFO] Auto-detected tri-band. IFACE1=[$IFACE1], IFACE2=[$IFACE2]"
                   run_triband ;;
            esac
        fi
        echo "$(date): $SCRIPT_NAME > Executed"
        finish
        ;;
    install)
        manage_cron_job add
        manage_init_start add
        echo "$SCRIPT_NAME cron job & init-start entries added"
        finish
        ;;
    uninstall)
        manage_cron_job remove
        manage_init_start remove

        if [ -f "$SCRIPT_PATH" ]; then
            printf "Do you want to delete the script ($SCRIPT_PATH)? [y/N] "
            read -r confirm_script
            case "$confirm_script" in
                [Yy]*)
                    rm "$SCRIPT_PATH"
                    echo "Script file removed."
                    ;;
                *)
                    echo "Skipping script removal."
                    ;;
            esac
        fi

        if [ -f "$LOG_FILE" ]; then
            printf "Do you want to delete the log file ($LOG_FILE)? [y/N] "
            read -r confirm_log
            case "$confirm_log" in
                [Yy]*)
                    rm -f "$LOG_FILE"
                    echo "Log file removed."
                    ;;
                *)
                    echo "Skipping log removal."
                    ;;
            esac
        fi

        echo "$SCRIPT_NAME cron job & init-start entries removed"
        exit 0
        ;;
    menu)
        show_menu
        ;;
    *)
        if [ "$ENABLE_MENU" -eq 1 ]; then
            show_menu
        else
            $SCRIPT_PATH exec
        fi
        finish
        ;;
esac
