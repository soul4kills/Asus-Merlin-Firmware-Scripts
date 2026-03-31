# `fix_160A.sh` – Keep 5 GHz WiFi on 160 MHz (Asuswrt‑Merlin)

## Disclaimer

This script **does not** bypass or alter any regulatory‑compliant DFS (Dynamic Frequency Selection) or CAC (Channel Availability Check) behavior.  
It only calls the existing `wl` command and leverages the **same built‑in DFS/CAC mechanisms** that Broadcom and ASUS provide with the router firmware. Using it means you accept that:

- If you believe this script is doing something illegal, that is effectively a claim about **Broadcom/ASUS’s own implementation and regulatory compliance**, not about this script specifically, because it only calls their existing `wl` command and uses the built‑in DFS/CAC behavior.
- Any concerns about regulatory compliance should be directed to **ASUS** or Broadcom; this script is simply a wrapper around functionality that is already present in the firmware.

## Overview

`fix_160A.sh` is a shell script designed for **dual‑band Asuswrt‑Merlin routers** that support **WiFi‑6 160‑MHz channels**.  
It automatically attempts to keep the 5 GHz radio on a 160 MHz channel after a DFS hit causes downgrade to 80 MHz or a non‑DFS channel.

- **Target devices**: Dual‑band AC/AX routers (e.g., RT‑AX82U, RT‑AX86U, RT‑AX88U) running Asuswrt‑Merlin.
- **Function**: Runs via cron every 30 minutes (`1,31 * * * *`) and performs a controlled `dfs_ap_move` to recover 160 MHz operation.
- **Tri‑band notes**: Tri‑band owners can run **two copies** of the script (e.g., `sticky_160.sh` and `sticky_160_2.sh`), offset the cron jobs by 1–2 minutes, and set `IFACE` manually for each radio.

---

## Configuration variables

Set these at the top of the script to tune behavior:

```sh
SCRIPT_NAME="fix_160A"      # Script name must match filename without .sh
IFACE=""                    # 5GHz interface; leave empty for auto‑detect or set e.g. "eth6"
COOLDOWN=60                 # Minimum seconds between recovery attempts
CAC_WAIT=61                 # Wait time for CAC to finish (slightly above 61s)
PREFERRED="100/160"         # Preferred 160MHz chanspec (may be overridden by NVRAM)
DISABLE_FALLBACK=0          # 1: never switch to opposite 160MHz block once PREFERRED is chosen
STRICT_STICKY=0             # 0: jump to PREFERRED only if current channel is outside block
                            # 1: jump to PREFERRED if not on exact chanspec, even within block
MANAGE_CRON=1               # Set to 1/0 to add/remove cron and init-start entries
VERBOSE=2                   # 0=silent, 1=basic logs, 2=verbose (includes DFS status)
LOG_ROTATE_RAM=1            # 1=RAM‑only log rotation, 0=use temp file on disk
LOG_LINES=200
```

Key behaviors:

- `DISABLE_FALLBACK=1` disables cross‑block fallback; the script will only ever attempt the `PREFERRED` 160‑MHz block.
- `STRICT_STICKY=1` forces the radio back to the exact `PREFERRED` `chanspec` even if it’s already on 160 MHz in the same block.
- `LOG_ROTATE_RAM=1` keeps logs in memory‑backed storage (no disk writes), while `0` uses a temporary file rotation on `/jffs`.

---

## NVRAM‑driven behavior

The script reads `wl1_chanspec` from NVRAM to respect the GUI settings:

- If `wl1_chanspec=0` (Auto), the script uses `PREFERRED`, `DISABLE_FALLBACK`, and `STRICT_STICKY` as configured.
- If `wl1_chanspec` is a valid `*/160` spec (e.g., `100/160`):
  - `PREFERRED` is overridden to match the GUI‑selected channel.
  - `DISABLE_FALLBACK=1` and `STRICT_STICKY=1` are enforced so the script always targets that exact channel.

This means:  
- If you **lock the GUI** to a specific 160‑MHz channel (e.g., `100/160`), the script will never try the opposite block and will aggressively try to stay on that channel.
- If you set the GUI to **Auto**, the script behaves in its default “fallback‑enabled” mode.

---

## Cron, init‑start, and locking

The script can manage itself:

- When `MANAGE_CRON=1`:
  - Adds a cron job: `1,31 * * * * /jffs/scripts/fix_160A.sh`.
  - Creates/updates `/jffs/scripts/init-start` so the cron job is re‑installed on each boot.
- Uses `$LOCK_FILE` (`/tmp/fix_160A.last_action`) to enforce a cooldown window (`$COOLDOWN` seconds) so consecutive runs don’t immediately re‑trigger a DFS move.

Timeouts are tuned around the router’s background DFS‑CAC mechanism; `CAC_WAIT=61` ensures the script waits long enough for the CAC to complete before logging the result.

---

## How it works (step‑by‑step)

1. **Interface detection**  
   - If `IFACE` is empty, the script auto‑detects the first 5 GHz interface reported by `sta_phy_ifnames` that is in the 5 GHz range (channels 36–165).
   - Logs `Auto‑detected 5GHz interface [$IFACE]`.

2. **Cooldown & radio check**  
   - If the last move was within `$COOLDOWN` seconds, exit early.
   - If the radio is down (`wl ... isup` ≠ 1), exit with a log entry.

3. **Current state inspection**  
   - Reads `wl -i "$IFACE" chanspec` to get current channel and width.
   - If already on 160 MHz, behavior depends on settings:
     - `STRICT_STICKY=1`: must be on exact `PREFERRED` `chanspec`; if not, attempt `dfs_ap_move` to `PREFERRED`.
     - `DISABLE_FALLBACK=1`: must be in the preferred block range (e.g., 100–128); if not, attempt move back to `PREFERRED`.
     - Otherwise, exit with `[__END] Already on 160MHz`.

4. **Recovery logic (when not on 160 MHz)**  
   - If `DISABLE_FALLBACK=1`:
     - Only attempt `PRIMARY=PREFERRED`.
   - If `DISABLE_FALLBACK=0`:
     - Current in 36–64 block → `PRIMARY=36/160`, `FALLBACK=100/160`.
     - Current in 100–128 block → `PRIMARY=100/160`, `FALLBACK=36/160`.
     - Outside both blocks → `PRIMARY=PREFERRED`, `FALLBACK` opposite block.
   - Tries `dfs_ap_move PRIMARY`; if rejected and `DISABLE_FALLBACK=0`, tries `FALLBACK`.

5. **Post‑CAC verification**  
   - After `dfs_ap_move` is accepted, the script:
     - Waits `$CAC_WAIT` seconds for background CAC.
     - Reads `chanspec` again and logs:
       - `[OK] Recovery successful` if width is `160`.
       - `[NOTICE] Recovery failed` if still <160 MHz.
   - If disabled, no fallback is attempted; if enabled, it may retry the fallback on the next run.

6. **Logging and rotation**  
   - Logs are written to `/jffs/scripts/fix_160A.log`.
   - When `LOG_ROTATE_RAM=1`, `tail -n $LOG_LINES` keeps the log capped in memory; otherwise a temp‑file rotation is used.

---

## Example operation flow

Typical AUTO‑mode scenario (GUI set to Auto):

- Radio is on `100/80` after a DFS hit.
- Script:
  - Detects current width = `80`.
  - Sets `PRIMARY=100/160` and `FALLBACK=36/160`.
  - Tries `dfs_ap_move 100/160`.
  - If that fails (NOP/CAC), tries `36/160`.
- Radio moves to `100/160` or `36/160` and remains there until another DFS hit.
- On the next run, if already on 160 MHz and within the same block, no action is taken (unless `STRICT_STICKY=1` and channel is not exactly `PREFERRED`).

If `DISABLE_FALLBACK=0` and the preferred block is still blocked, the script may succeed on the opposite block, achieving:
- `100/160` → `36/160` (or vice‑versa) as needed to keep maximum possible bandwidth.

---

## Quick install

Run this on the router shell (via SSH) to install and register the script:

```sh
curl -L "https://raw.githubusercontent.com/soul4kills/hindsight160/refs/heads/main/fix_160A.sh" -o /jffs/scripts/fix_160A.sh && \
chmod a+x /jffs/scripts/fix_160A.sh && \
cru a fix_160A "1,31 * * * * /jffs/scripts/fix_160A.sh"
```

This:

- Downloads the script to `/jffs/scripts/fix_160A.sh`.
- Makes it executable.
- Sets a cron job to run every 30 minutes at 1 and 31 minutes past the hour.

---

## Step‑by‑step install

1. Download:

   ```sh
   curl -L "https://raw.githubusercontent.com/soul4kills/hindsight160/refs/heads/main/fix_160A.sh" -o /jffs/scripts/fix_160A.sh
   ```

2. Make executable:

   ```sh
   chmod a+x /jffs/scripts/fix_160A.sh
   ```

3. Add cron job:

   ```sh
   cru a fix_160A "1,31 * * * * /jffs/scripts/fix_160A.sh"
   ```

4. Ensure it survives reboots (if `MANAGE_CRON=1`):

   The script will auto‑create/update `/jffs/scripts/init-start` so the cron job is re‑installed on boot.

---

## Managing the script

### Remove the cron job

```sh
cru d fix_160A
```

Re‑enable later:

```sh
cru a fix_160A "1,31 * * * * /jffs/scripts/fix_160A.sh"
```

### Disable self‑registration (manual control)

Set:

```sh
MANAGE_CRON=0
```

Then run the script once and it will:

- Remove the cron job
- Remove cron registration from `/jffs/scripts/init-start`.

You can then manage cron and init‑start entries yourself.

---

## Logging and troubleshooting

- Logs are written to `/jffs/scripts/fix_160A.log`.
- Useful `VERBOSE` levels:
  - `0`: Silent.
  - `1`: Basic info (actions, DFS status summary).
  - `2`: Verbose (full `wl ... dfs_ap_move` status blocks).
- To inspect current DFS status blocks:

  ```sh
  wl -i eth6 dfs_ap_move
  ```

  (replace `eth6` with your actual 5 GHz interface).
