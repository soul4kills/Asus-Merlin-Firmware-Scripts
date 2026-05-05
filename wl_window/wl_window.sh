#!/bin/sh

# =============================================================================
# wl_window.sh     Scheduled Internet Block with Whitelist
# Place at: /jffs/addons/wl_window/wl_window.sh
# =============================================================================

ADDON_DIR="/jffs/addons/wl_window"
SETTINGS="/jffs/addons/custom_settings.txt"

# --- BUILT-IN DEFAULTS -------------------------------------------------------
DEFAULT_START_HH=22
DEFAULT_START_MM=00
DEFAULT_END_HH=06
DEFAULT_END_MM=00
# Comma-separated cron day field: 0=Sun,1=Mon,...,6=Sat  "*" means every day
DEFAULT_DAYS="*"

DEFAULT_WHITELIST_MACS="
AA:BB:CC:DD:EE:FF
11:22:33:44:55:66
"
DEFAULT_WHITELIST_INTERFACES="
wl0.1
wl0.2
"
DEFAULT_WHITELIST_IPS="
192.168.1.50
192.168.1.100
"

# --- SETTINGS HELPERS --------------------------------------------------------

cfg_get() {
    [ -f "$SETTINGS" ] && grep "^$1 " "$SETTINGS" | grep -v "^#" | cut -d' ' -f2-
}

# cfg_set: write or update a key using grep -v + cp-over to preserve the file
# inode and avoid sed mangling backslashes in JSON values (e.g. \u0020).
cfg_set() {
    _k="$1"; _v="$2"
    touch "$SETTINGS"
    _tmp="${SETTINGS}.wlw.tmp"
    grep -v "^$_k " "$SETTINGS" > "$_tmp" 2>/dev/null
    printf '%s %s\n' "$_k" "$_v" >> "$_tmp"
    cp "$_tmp" "$SETTINGS"
    rm -f "$_tmp"
}

cfg_set_status() {
    _k="$1"; _v="$2"
    touch "$SETTINGS"
    sed -i '/# WLW_STATUS_START/,/# WLW_STATUS_END/d' "$SETTINGS"
    printf '# WLW_STATUS_START\n%s %s\n# WLW_STATUS_END\n' "$_k" "$_v" >> "$SETTINGS"
}

# --- LOAD SETTINGS -----------------------------------------------------------

load_settings() {
    _shh=$(cfg_get wlw_start_hh); START_HH=${_shh:-$DEFAULT_START_HH}
    _smm=$(cfg_get wlw_start_mm); START_MM=${_smm:-$DEFAULT_START_MM}
    _ehh=$(cfg_get wlw_end_hh);   END_HH=${_ehh:-$DEFAULT_END_HH}
    _emm=$(cfg_get wlw_end_mm);   END_MM=${_emm:-$DEFAULT_END_MM}

    # Days field: stored as a cron-compatible day-of-week string.
    # The webui saves it as a comma list of 0-6 integers, or "*" for every day.
    _days=$(cfg_get wlw_days); DAYS=${_days:-$DEFAULT_DAYS}

    _entries=$(cfg_get wlw_entries)

    if [ -n "$_entries" ]; then
        # Match both key orderings: {"type":"mac","value":"..."} and {"value":"...","type":"mac"}
        WHITELIST_MACS=$(echo "$_entries" \
            | grep -oE '"type":"mac"[^}]*"value":"[^"]*"|"value":"[^"]*"[^}]*"type":"mac"' \
            | grep -o '"value":"[^"]*"' \
            | sed 's/"value":"\([^"]*\)"/\1/')
        WHITELIST_IPS=$(echo "$_entries" \
            | grep -oE '"type":"ip"[^}]*"value":"[^"]*"|"value":"[^"]*"[^}]*"type":"ip"' \
            | grep -o '"value":"[^"]*"' \
            | sed 's/"value":"\([^"]*\)"/\1/')
        WHITELIST_INTERFACES=$(echo "$_entries" \
            | grep -oE '"type":"int"[^}]*"value":"[^"]*"|"value":"[^"]*"[^}]*"type":"int"' \
            | grep -o '"value":"[^"]*"' \
            | sed 's/"value":"\([^"]*\)"/\1/')
    else
        WHITELIST_MACS="$DEFAULT_WHITELIST_MACS"
        WHITELIST_IPS="$DEFAULT_WHITELIST_IPS"
        WHITELIST_INTERFACES="$DEFAULT_WHITELIST_INTERFACES"
    fi
}

load_settings

# --- CONSTANTS ---------------------------------------------------------------
CHAIN="WL_WINDOW"
JOB_START="whitelist_window_start"
JOB_STOP="whitelist_window_stop"
SCRIPT=$(readlink -f "$0")
SERVICES_START="/jffs/scripts/services-start"

# --- FIREWALL ----------------------------------------------------------------

persist_on() {
    cfg_set "wlw_persist" "1"
    logger "wl_window" "block persistence on"
}

persist_off() {
    cfg_set "wlw_persist" "0"
    logger "wl_window" "block persistence off"
}

# ---------------------------------------------------------------------------
# _build_cron_day_field DAYS
#
# Converts the stored DAYS value into a cron day-of-week field.
#
#   "*"          -> "*"          (every day)
#   "1,2,3,4,5"  -> "1,2,3,4,5" (Mon-Fri)
#   "0,6"        -> "0,6"        (weekends)
#
# Returns the field on stdout so callers can capture it.
# ---------------------------------------------------------------------------
_build_cron_day_field() {
    _d="${1:-*}"
    # Sanitise: keep only digits, commas, and asterisks
    _d=$(echo "$_d" | tr -cd '0-9,*')
    [ -z "$_d" ] && _d="*"
    echo "$_d"
}

# ---------------------------------------------------------------------------
# _crosses_midnight START_HH START_MM END_HH END_MM
#
# Returns 0 (true) if the block window spans midnight, 1 (false) otherwise.
# A window crosses midnight when the end time is earlier than the start time
# (e.g. start=22:00, end=06:00).  Equal times are treated as same-day.
# ---------------------------------------------------------------------------
_crosses_midnight() {
    _sh="$1"; _sm="$2"; _eh="$3"; _em="$4"
    _s=$(( (_sh * 60) + _sm ))
    _e=$(( (_eh * 60) + _em ))
    [ "$_e" -lt "$_s" ]
}

# ---------------------------------------------------------------------------
# _next_day_field DAY_FIELD
#
# Given a cron day-of-week field, returns the field shifted forward by one day.
# Used to schedule the stop job on the correct calendar day when the block
# window crosses midnight (e.g. start Mon 22:00, stop Tue 06:00).
#
#   "*"          -> "*"    (every day stays every day)
#   "1,2,3,4,5"  -> "2,3,4,5,6"  (Tue-Sat)
#   "0,6"        -> "0,1"         (Sun,Mon -- 6 wraps to 0)
# ---------------------------------------------------------------------------
_next_day_field() {
    _d="${1:-*}"
    [ "$_d" = "*" ] && { echo "*"; return; }

    _result=""
    # Split on commas and advance each day number by 1, wrapping 6->0
    IFS=","
    for _day in $_d; do
        _next=$(( (_day + 1) % 7 ))
        if [ -z "$_result" ]; then
            _result="$_next"
        else
            _result="${_result},${_next}"
        fi
    done
    unset IFS

    # De-duplicate (e.g. "0,1,2,3,4,5,6" -> "0,1,2,3,4,5,6", all 7 days -> "*")
    # Count unique values; if all 7 days present, collapse to "*"
    _count=$(echo "$_result" | tr ',' '\n' | sort -u | wc -l)
    if [ "$_count" -ge 7 ]; then
        echo "*"
    else
        echo "$_result" | tr ',' '\n' | sort -un | tr '\n' ',' | sed 's/,$//'
    fi
}

install_cron() {
    _day_field=$(_build_cron_day_field "$DAYS")

    # Determine the correct day field for the stop job.
    # When the window crosses midnight the stop fires on the *next* calendar
    # day relative to the start (e.g. start Mon 22:00 -> stop Tue 06:00).
    if _crosses_midnight "$START_HH" "$START_MM" "$END_HH" "$END_MM"; then
        _stop_day_field=$(_next_day_field "$_day_field")
        _midnight_note=" (crosses midnight)"
    else
        _stop_day_field="$_day_field"
        _midnight_note=""
    fi

    cru a "$JOB_START" "$START_MM $START_HH * * $_day_field $SCRIPT start"
    cru a "$JOB_STOP"  "$END_MM $END_HH * * $_stop_day_field $SCRIPT stop"
    cfg_set "wlw_cron_active" "1"
    logger "wl_window" "(wlw_cron_active=1)"
    logger "wl_window" "Cron jobs installed: start=${START_HH}:${START_MM} (${_day_field}) stop=${END_HH}:${END_MM} (${_stop_day_field})${_midnight_note}"
    echo "[+] Cron jobs added: start=${START_HH}:${START_MM} days=${_day_field}, stop=${END_HH}:${END_MM} days=${_stop_day_field}${_midnight_note}"
}

uninstall_cron() {
    cru d "$JOB_START" 2>/dev/null
    cru d "$JOB_STOP"  2>/dev/null
    cfg_set "wlw_cron_active" "0"
    logger "wl_window" "(wlw_cron_active=0)"
    logger "wl_window" "Cron jobs removed."
    echo "[-] Cron jobs removed."
}

apply_block() {
    iptables  -D FORWARD -j "$CHAIN" 2>/dev/null
    iptables  -F "$CHAIN" 2>/dev/null
    iptables  -X "$CHAIN" 2>/dev/null
    ip6tables -D FORWARD -j "$CHAIN" 2>/dev/null
    ip6tables -F "$CHAIN" 2>/dev/null
    ip6tables -X "$CHAIN" 2>/dev/null

    iptables  -N "$CHAIN" 2>/dev/null
    ip6tables -N "$CHAIN" 2>/dev/null

    iptables  -A "$CHAIN" -m state --state ESTABLISHED,RELATED -j RETURN
    ip6tables -A "$CHAIN" -m state --state ESTABLISHED,RELATED -j RETURN

    for iface in $WHITELIST_INTERFACES; do
        iptables  -A "$CHAIN" -i "$iface" -j RETURN
        ip6tables -A "$CHAIN" -i "$iface" -j RETURN
    done

    for ip in $WHITELIST_IPS; do
        case "$ip" in
            *.*)  iptables  -A "$CHAIN" -s "$ip" -j RETURN ;;
            *:*)  ip6tables -A "$CHAIN" -s "$ip" -j RETURN ;;
        esac
    done

    for mac in $WHITELIST_MACS; do
        iptables  -A "$CHAIN" -m mac --mac-source "$mac" -j RETURN
        ip6tables -A "$CHAIN" -m mac --mac-source "$mac" -j RETURN
    done

    iptables  -A "$CHAIN" -j REJECT --reject-with icmp-port-unreachable
    ip6tables -A "$CHAIN" -j REJECT --reject-with icmp6-adm-prohibited
    iptables  -I FORWARD 1 -j "$CHAIN"
    ip6tables -I FORWARD 1 -j "$CHAIN"
    conntrack -F 2>/dev/null

    logger "wl_window" "Block ACTIVE -- whitelisted devices/interfaces bypassed."
    echo "[+] Whitelist Active: All authorized devices/interfaces bypass the block."

    cfg_set "wlw_active" "1"
}

remove_block() {
    iptables  -D FORWARD -j "$CHAIN" 2>/dev/null
    iptables  -F "$CHAIN" 2>/dev/null
    iptables  -X "$CHAIN" 2>/dev/null
    ip6tables -D FORWARD -j "$CHAIN" 2>/dev/null
    ip6tables -F "$CHAIN" 2>/dev/null
    ip6tables -X "$CHAIN" 2>/dev/null
    conntrack -F 2>/dev/null

    logger "wl_window" "Block INACTIVE."
    echo "[-] Whitelist Disabled."

    cfg_set "wlw_active" "0"
}

# ---------------------------------------------------------------------------
# _days_label DAYS
# Returns a human-readable string for the day field, e.g. "Mon", "Fri", "Every day"
# Uses comma/boundary-safe sed patterns instead of \b (not supported in BusyBox sed).
# ---------------------------------------------------------------------------
_days_label() {
    _df="${1:-*}"
    case "$_df" in
        "*"|"0,1,2,3,4,5,6") echo "Every day" ;;
        "1,2,3,4,5")         echo "Mon-Fri"   ;;
        "0,1,2,3,4")         echo "Sun-Thu"   ;;
        "5,6")               echo "Fri-Sat"   ;;
        "0,6")               echo "Sat-Sun"   ;;
        *)
            # Map digit tokens to day names. Anchored at start/end of string
            # and around commas so single digits don't match inside multi-digit
            # numbers. \b is not available in BusyBox sed.
            _label=$(printf '%s' "$_df" \
                | sed \
                    -e 's/^0,/Sun,/' -e 's/,0,/,Sun,/g' -e 's/,0$/,Sun/' -e 's/^0$/Sun/' \
                    -e 's/^1,/Mon,/' -e 's/,1,/,Mon,/g' -e 's/,1$/,Mon/' -e 's/^1$/Mon/' \
                    -e 's/^2,/Tue,/' -e 's/,2,/,Tue,/g' -e 's/,2$/,Tue/' -e 's/^2$/Tue/' \
                    -e 's/^3,/Wed,/' -e 's/,3,/,Wed,/g' -e 's/,3$/,Wed/' -e 's/^3$/Wed/' \
                    -e 's/^4,/Thu,/' -e 's/,4,/,Thu,/g' -e 's/,4$/,Thu/' -e 's/^4$/Thu/' \
                    -e 's/^5,/Fri,/' -e 's/,5,/,Fri,/g' -e 's/,5$/,Fri/' -e 's/^5$/Fri/' \
                    -e 's/^6,/Sat,/' -e 's/,6,/,Sat,/g' -e 's/,6$/,Sat/' -e 's/^6$/Sat/')
            echo "$_label"
            ;;
    esac
}

show_status() {
    _day_field=$(_build_cron_day_field "$DAYS")
    _day_label=$(_days_label "$_day_field")

    if _crosses_midnight "$START_HH" "$START_MM" "$END_HH" "$END_MM"; then
        _stop_day_field=$(_next_day_field "$_day_field")
        _stop_day_label=$(_days_label "$_stop_day_field")
        _sched_note=" [crosses midnight -- stop fires on ${_stop_day_label}]"
    else
        _sched_note=""
    fi

    echo "=== Whitelist Window - Dual-Stack Status ==="
    echo ""
    echo "Config  : $([ -f "$SETTINGS" ] && echo "$SETTINGS" || echo "built-in defaults")"
    echo "Schedule: ON at ${START_HH}:${START_MM}, OFF at ${END_HH}:${END_MM}, Days: ${_day_label} (cron: ${_day_field})${_sched_note}"
    echo ""
    if iptables -L FORWARD 2>/dev/null | grep -q "$CHAIN"; then
        echo "STATE: ACTIVE"
        echo ""
        echo "--- IPv4 Rules ($CHAIN) ---"
        iptables  -L "$CHAIN" -v -n
        echo ""
        echo "--- IPv6 Rules ($CHAIN) ---"
        ip6tables -L "$CHAIN" -v -n
    else
        echo "STATE: INACTIVE"
        echo ""
        echo "--- Whitelisted MACs ---"
        for m in $WHITELIST_MACS; do echo "  $m"; done
        echo ""
        echo "--- Whitelisted IPs ---"
        for i in $WHITELIST_IPS; do echo "  $i"; done
        echo ""
        echo "--- Whitelisted Interfaces ---"
        for n in $WHITELIST_INTERFACES; do echo "  $n"; done
    fi
}

# --- CRON / INSTALL ----------------------------------------------------------

install_script() {
    echo "[*] Installing Whitelist Window..."

    INSTALL_SCRIPT="$ADDON_DIR/wl_window_install.sh"
    if [ -f "$INSTALL_SCRIPT" ]; then
        sh "$INSTALL_SCRIPT" install
    else
        echo "[!] wl_window_install.sh not found -- skipping webui install."
    fi

    if [ -f "$SERVICES_START" ]; then
        grep -q "wl_window.sh install" "$SERVICES_START" || \
            echo "sh $SCRIPT install" >> "$SERVICES_START"
    else
        printf "#!/bin/sh\nsh %s install\n" "$SCRIPT" > "$SERVICES_START"
        chmod 755 "$SERVICES_START"
    fi

    _cron_active=$(cfg_get wlw_cron_active)

    if [ "$_cron_active" = "1" ]; then
        echo "[+] wlw_cron_active=1 -- installing cron schedule..."
        install_cron
    else
        echo "[*] Skipping cron installation."
    fi

    _persist_active=$(cfg_get wlw_persist)
    _wlw_active=$(cfg_get wlw_active)

    if [ "$_wlw_active" = "1" ] && [ "$_persist_active" = "1" ]; then
        echo "[+] wlw_persist=1 -- block persistence active..."
        apply_block
    else
        echo "[*] Block persistence inactive."
    fi

    chmod 755 /jffs/addons/wl_window/*.sh

    # Populate client/interface/resolve data for the webui on first install
    sh "/jffs/addons/wl_window/wlwindow_service.sh" restart wlwindow_refresh

    echo "[+] clients & interfaces list populated."
    echo "[+] Whitelist Window fully installed."
}

uninstall_script() {
    echo "[*] Uninstalling Whitelist Window..."

    remove_block

    cru d "$JOB_START" 2>/dev/null
    cru d "$JOB_STOP"  2>/dev/null
    echo "[-] Cron jobs removed."

    if [ -f "$SERVICES_START" ]; then
        sed -i "\|sh $SCRIPT install|d" "$SERVICES_START"
        sed -i "\|wl_window_install.sh install|d" "$SERVICES_START"
    fi

    INSTALL_SCRIPT="$ADDON_DIR/wl_window_install.sh"
    if [ -f "$INSTALL_SCRIPT" ]; then
        sh "$INSTALL_SCRIPT" uninstall
    else
        echo "[!] wl_window_install.sh not found -- skipping webui teardown."
    fi

    if [ -f "$SETTINGS" ]; then
        sed -i '/^wlw_/d' "$SETTINGS"
        sed -i '/# WLW_STATUS_START/,/# WLW_STATUS_END/d' "$SETTINGS"
        echo "[-] Settings removed from $SETTINGS."
    fi

    if [ -d "$ADDON_DIR" ]; then
        rm -rf "$ADDON_DIR"
        echo "[-] Addon directory removed: $ADDON_DIR"
    fi

    echo "[+] Whitelist Window fully uninstalled."
}

# --- MANAGE ------------------------------------------------------------------

manage_list() {
    ACTION=$1
    TYPE=$2
    VALUE=$3

    show_current() {
        echo ""
        echo "--- Current Whitelisted MACs ---"
        for item in $WHITELIST_MACS; do echo "  $item"; done
        echo ""
        echo "--- Current Whitelisted IPs ---"
        for item in $WHITELIST_IPS; do echo "  $item"; done
        echo ""
        echo "--- Current Whitelisted Interfaces ---"
        for item in $WHITELIST_INTERFACES; do echo "  $item"; done
        echo ""
        echo "(Source: $([ -f "$SETTINGS" ] && echo "$SETTINGS" || echo "built-in defaults"))"
    }

    if [ -z "$ACTION" ] || [ "$ACTION" = "list" ]; then
        echo "--- Whitelist Management ---"
        echo "Usage: $0 manage {add|del} {mac|ip|int} {value}"
        show_current
        return
    fi

    case "$TYPE" in
        mac|ip|int) ;;
        *) echo "[!] Unknown type: $TYPE (use mac, ip, or int)"; return 1 ;;
    esac

    VALUE=$(echo "$VALUE" | tr '[:upper:]' '[:lower:]')

    _entries=$(cfg_get wlw_entries)

    if [ "$ACTION" = "add" ]; then
        echo "$_entries" | grep -q "\"value\":\"$VALUE\"" && { echo "[!] $VALUE already whitelisted."; return; }
        # Handle absent key (empty string) and empty array [] as equivalent
        if [ -z "$_entries" ] || [ "$_entries" = "[]" ]; then
            new_entries="[{\"type\":\"$TYPE\",\"value\":\"$VALUE\"}]"
        else
            new_entries=$(echo "$_entries" | sed "s/\]\$/,{\"type\":\"$TYPE\",\"value\":\"$VALUE\"}]/")
        fi
        cfg_set "wlw_entries" "$new_entries"
        echo "[+] Added $VALUE ($TYPE)"
        logger "wl_window" "Added $VALUE ($TYPE) to wlw_entries"

    elif [ "$ACTION" = "del" ]; then
        echo "$_entries" | grep -q "\"value\":\"$VALUE\"" || { echo "[!] $VALUE not found."; return; }
        new_entries=$(echo "$_entries" | \
            sed "s/{\"type\":\"[^\"]*\",\"value\":\"$VALUE\"},\?//g" | \
            sed 's/,\]/]/' | \
            sed 's/\[,/[/')
        cfg_set "wlw_entries" "$new_entries"
        echo "[-] Removed $VALUE"
        logger "wl_window" "Removed $VALUE from wlw_entries"
    fi

    if iptables -L FORWARD 2>/dev/null | grep -q "$CHAIN"; then
        load_settings
        apply_block
    fi
}

# --- DISPATCH ----------------------------------------------------------------

case "$1" in
    start)           apply_block ;;
    stop)            remove_block ;;
    status)          show_status ;;
    install)         install_script ;;
    uninstall)       uninstall_script ;;
    manage)          manage_list "$2" "$3" "$4" ;;
    cron_enable)     install_cron ;;
    cron_disable)    uninstall_cron ;;
    persist_enable)  persist_on ;;
    persist_disable) persist_off ;;
    *)  echo "Usage: $0 {start|stop|status|install|uninstall|manage|cron_enable|cron_disable|persist_enable|persist_disable}" ;;
esac
exit 0
