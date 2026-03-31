# `fix_160A.sh` – Keep 5 GHz WiFi on 160 MHz (Asuswrt‑Merlin)

## Disclaimer

This script **does not** bypass or alter any regulatory‑compliant DFS (Dynamic Frequency Selection) or CAC (Channel Availability Check) behavior.  
It only calls the existing `wl` command and leverages the **same built‑in DFS/CAC mechanisms** that Broadcom and ASUS provide with the router firmware. Using it means you accept that:

- If you believe this script is doing something illegal, that is effectively a claim about **Broadcom/ASUS's own implementation and regulatory compliance**, not about this script specifically, because it only calls their existing `wl` command and uses the built‑in DFS/CAC behavior.
- Any concerns about regulatory compliance should be directed to **ASUS** or Broadcom; this script is simply a wrapper around functionality that is already present in the firmware.

---

## Overview

`fix_160A.sh` is a shell script designed for **dual‑band Asuswrt‑Merlin routers** that support **WiFi‑6 160‑MHz channels**.  
It automatically attempts to keep the 5 GHz radio on a 160 MHz channel after a DFS hit causes a downgrade to 80 MHz or a non‑DFS channel.

ASUS never implemented an automatic 160 MHz recovery mechanism in their firmware. When a DFS radar event forces the radio off a 160 MHz channel, it stays on 80 MHz until manually reconfigured. This script fills that gap by running periodically and issuing a controlled `dfs_ap_move` to recover 160 MHz operation using the router's own built‑in background DFS CAC mechanism.  

<i><b>The main highlight of this script is that it does the recovery with minimal disconnects and interruption to clients. The usual method before was to restart the wireless radio to regain a 160mhz connection.</b></i>


- **Target devices**: Dual‑band WiFi 5/WiFi 6 routers running Asuswrt‑Merlin.
- **Function**: Runs via cron every 30 minutes (`1,31 * * * *`) and performs a controlled `dfs_ap_move` to recover 160 MHz operation.
- **Tri‑band notes**: See `hindsight160.sh` for a unified script that handles both dual‑band and tri‑band routers automatically.

---

## Configuration variables

```sh
IFACE=""                    # 5GHz interface; leave empty for auto‑detect or set e.g. "eth6"
COOLDOWN=60                 # Minimum seconds between recovery attempts
CAC_POLL=60                 # Seconds between each CAC status poll
CAC_TIMEOUT=660             # Maximum seconds to wait for CAC before giving up
                            # 60s = standard DFS channels
                            # 600s = weather radar channels (120/124/128)
                            # 660s default covers all regions with one poll interval buffer
PREFERRED="100/160"         # Preferred 160MHz chanspec (may be overridden by NVRAM)
DISABLE_FALLBACK=0          # 1: never switch to opposite 160MHz block once PREFERRED is chosen
STRICT_STICKY=0             # 0: jump to PREFERRED only if current channel is outside block
                            # 1: jump to PREFERRED if not on exact chanspec, even within block
                            # Note: automatically set to 1 when NVRAM wl1_chanspec overrides PREFERRED
MANAGE_CRON=1               # 1/0 to add/remove cron and init-start entries
VERBOSE=0                   # 0=silent, 1=basic logs, 2=verbose (includes DFS status blocks)
LOG_ROTATE_RAM=1            # 1=RAM‑only log rotation, 0=use temp file on disk
LOG_LINES=100
```

Key behaviors:

- `DISABLE_FALLBACK=1` disables cross‑block fallback. The script will only ever attempt the `PREFERRED` 160 MHz block.
- `STRICT_STICKY=1` forces the radio back to the exact `PREFERRED` chanspec even if it is already on 160 MHz within the same block.
- `CAC_POLL` and `CAC_TIMEOUT` replace the old fixed `CAC_WAIT` sleep. The script now polls the driver for completion rather than sleeping a fixed duration, accommodating both standard 60‑second CAC regions and 10‑minute weather radar channel regions automatically.

---

## NVRAM‑driven behavior

The script reads `wl1_chanspec` from NVRAM to respect the router GUI settings:

- If `wl1_chanspec=0` (Auto), the script uses `PREFERRED`, `DISABLE_FALLBACK`, and `STRICT_STICKY` as configured.
- If `wl1_chanspec` is a valid `*/160` chanspec (e.g., `100/160`):
  - `PREFERRED` is overridden to match the GUI‑selected channel.
  - `DISABLE_FALLBACK=1` and `STRICT_STICKY=1` are enforced so the script always targets that exact channel.

This means:
- If you **lock the GUI** to a specific 160 MHz channel, the script will never try the opposite block and will aggressively stay on that exact channel.
- If you set the GUI to **Auto**, the script behaves in its default fallback‑enabled mode.

---

## Cron, init‑start, and locking

When `MANAGE_CRON=1` the script manages itself:

- Adds a cron job: `1,31 * * * * /jffs/scripts/fix_160A.sh`
- Creates or updates `/jffs/scripts/init-start` so the cron job is re‑installed on each reboot.
- Uses a lock file at `/tmp/fix_160A.last_action` to enforce the `COOLDOWN` window between recovery attempts.

---

## How it works (step‑by‑step)

1. **NVRAM override**
   Reads `wl1_chanspec` from NVRAM. If a valid 160 MHz chanspec is set in the GUI, it overrides `PREFERRED`, `DISABLE_FALLBACK`, and `STRICT_STICKY`.

2. **Interface detection**
   If `IFACE` is empty, auto‑detects the first 5 GHz interface from `wl_ifnames` in the 5 GHz channel range (36–165). Warns if multiple 5 GHz interfaces are found.

3. **Cooldown check**
   If the last recovery attempt was within `COOLDOWN` seconds, exits early.

4. **Radio up check**
   If the radio is down (`wl isup` ≠ 1), exits without action.

5. **Current state inspection**
   Reads `wl chanspec` to determine current channel and width.
   - If already on 160 MHz:
     - `STRICT_STICKY=1`: must be on exact `PREFERRED` chanspec — if not, attempt `dfs_ap_move` to `PREFERRED`.
     - `DISABLE_FALLBACK=1`: must be within the preferred block range — if not, attempt move back to `PREFERRED`.
     - Otherwise: already fine, exit with no action.

6. **Recovery logic (when not on 160 MHz)**
   - `DISABLE_FALLBACK=1`: only attempt `PREFERRED`.
   - `DISABLE_FALLBACK=0`:
     - Current channel in 36–64 → `PRIMARY=36/160`, `FALLBACK=100/160`
     - Current channel in 100–128 → `PRIMARY=100/160`, `FALLBACK=36/160`
     - Outside both blocks → `PRIMARY=PREFERRED`, `FALLBACK` = opposite block
   - Tries `dfs_ap_move PRIMARY`. If rejected and fallback is enabled, tries `FALLBACK`.

7. **CAC polling**
   Once a move is accepted, stamps the lock file and polls `dfs_ap_move` every `CAC_POLL` seconds watching for `move status=-1` which indicates CAC has completed. An initial 5‑second sleep allows the driver to transition state before the first poll. Gives up after `CAC_TIMEOUT` seconds and holds until the next cron run.

8. **Post‑CAC verification**
   Reads `chanspec` again after CAC completes:
   - `[OK] Recovery successful` if on 160 MHz.
   - `[NOTICE] Recovery failed` if still below 160 MHz — if fallback is enabled and not yet tried, attempts fallback chanspec.

9. **Log rotation**
   Keeps the log capped at `LOG_LINES` lines. `LOG_ROTATE_RAM=1` does this in memory; `LOG_ROTATE_RAM=0` uses a temp file on disk.

---

## Example operation flow

Radio is on `100/80` after a DFS hit, GUI set to Auto:

- Script detects width = `80`
- Sets `PRIMARY=100/160`, `FALLBACK=36/160`
- Tries `dfs_ap_move 100/160` — accepted
- Polls every 61 seconds watching for `move status=-1`
- CAC completes after ~61 seconds
- Reads chanspec — now `100/160`
- Logs `[OK] Recovery successful`

---

## Quick install

```sh
curl -L "https://raw.githubusercontent.com/soul4kills/hindsight160/refs/heads/main/fix_160A/fix_160A.sh" -o /jffs/scripts/fix_160A.sh && \
chmod 755 /jffs/scripts/fix_160A.sh && \
cru a fix_160A "1,31 * * * * /jffs/scripts/fix_160A.sh"
```

---

## Step‑by‑step install

1. Download:
   ```sh
   curl -L "https://raw.githubusercontent.com/soul4kills/hindsight160/refs/heads/main/fix_160A/fix_160A.sh" -o /jffs/scripts/fix_160A.sh
   ```

2. Make executable:
   ```sh
   chmod 755 /jffs/scripts/fix_160A.sh
   ```

3. Add cron job:
   ```sh
   cru a fix_160A "1,31 * * * * /jffs/scripts/fix_160A.sh"
   ```

4. The script will auto‑create/update `/jffs/scripts/init-start` on first run if `MANAGE_CRON=1`.

---

## Managing the script

### Remove the cron job
```sh
cru d fix_160A
```

### Disable self‑registration
Set `MANAGE_CRON=0` and run the script once. It will remove the cron job and its entry from `init-start`.

---

## Logging and troubleshooting

- Logs are written to `/jffs/scripts/fix_160A.log`
- `VERBOSE` levels:
  - `0`: Silent
  - `1`: Basic info — actions, CAC poll results, recovery outcome
  - `2`: Verbose — full `dfs_ap_move` status blocks at each poll interval

To inspect current DFS status manually:
```sh
wl -i eth6 dfs_ap_move
```
Replace `eth6` with your actual 5 GHz interface name.

To check what interface your router uses:
```sh
nvram get wl_ifnames
```
