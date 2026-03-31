# `hindsight160.sh` – Keep 5 GHz WiFi on 160 MHz (Asuswrt‑Merlin)

## Disclaimer

This script **does not** bypass or alter any regulatory‑compliant DFS (Dynamic Frequency Selection) or CAC (Channel Availability Check) behavior.  
It only calls the existing `wl` command and leverages the **same built‑in DFS/CAC mechanisms** that Broadcom and ASUS provide with the router firmware. Using it means you accept that:

- If you believe this script is doing something illegal, that is effectively a claim about **Broadcom/ASUS's own implementation and regulatory compliance**, not about this script specifically, because it only calls their existing `wl` command and uses the built‑in DFS/CAC behavior.
- Any concerns about regulatory compliance should be directed to **ASUS** or Broadcom; this script is simply a wrapper around functionality that is already present in the firmware.

---

## Overview

`hindsight160.sh` is a shell script for **dual‑band and tri‑band Asuswrt‑Merlin routers** that support **WiFi‑6 160‑MHz channels**.  
It automatically attempts to keep the 5 GHz radio or radios on 160 MHz after a DFS hit causes a downgrade to 80 MHz or a non‑DFS channel.

ASUS never implemented an automatic 160 MHz recovery mechanism in their firmware — hence the name. When a DFS radar event forces the radio off a 160 MHz channel, it stays on 80 MHz until manually reconfigured. This script fills that gap by running periodically and issuing a controlled `dfs_ap_move` to recover 160 MHz operation using the router's own built‑in background DFS CAC mechanism.

<i><b>The main highlight of this script is that it does the recovery with minimal disconnects and interruption to clients. The usual method before was to restart the wireless radio to regain a 160mhz connection.</b></i>

- **Target devices**: Dual‑band and tri‑band WiFi 5/WiFi 6 routers running Asuswrt‑Merlin.
- **Function**: Runs via cron every 30 minutes (`1,31 * * * *`).
- **Mode selection**: Automatically detects whether the router is dual‑band or tri‑band. Can also be forced manually via `IFACE1`/`IFACE2`.

---

## Dual‑band vs tri‑band mode

| | Dual-band | Tri-band |
|---|---|---|
| Radios managed | 1 | 2 |
| Block assignment | Derived from `PREFERRED` | IFACE1 fixed to 36–64, IFACE2 fixed to 100–128 |
| Fallback | Optional cross‑block fallback | None — blocks are separated by design |
| NVRAM override | Yes (`wl1_chanspec`) | No |

---

## Mode selection

Mode is determined in this order:

1. `IFACE1` and `IFACE2` both set → **tri‑band mode**
2. Only `IFACE1` set → **dual‑band mode**
3. Both empty → **auto‑detect** — scans `wl_ifnames` for 5 GHz interfaces:
   - 1 found → dual‑band mode
   - 2 found → tri‑band mode

---

## Configuration variables

```sh
IFACE1=""               # First 5GHz interface. Leave empty for auto-detection.
                        # If only IFACE1 is set, dual-band mode is assumed.
                        # If both IFACE1 and IFACE2 are set, tri-band mode is assumed.
IFACE2=""               # Second 5GHz interface for tri-band mode only.

# Dual-band options (ignored in tri-band mode)
PREFERRED="100/160"     # Preferred 160MHz chanspec (may be overridden by NVRAM)
DISABLE_FALLBACK=1      # 1: never switch to opposite 160MHz block once PREFERRED is chosen

# Shared options
COOLDOWN=60             # Minimum seconds between recovery attempts (per radio in tri-band)
CAC_POLL=60             # Seconds between each CAC status poll
CAC_TIMEOUT=660         # Maximum seconds to wait for CAC before giving up
                        # 60s = standard DFS channels
                        # 600s = weather radar channels (120/124/128)
                        # 660s default covers all regions with one poll interval buffer
STRICT_STICKY=0         # 0: any 160MHz channel within assigned block is acceptable
                        # 1: must be on exact preferred chanspec; any deviation triggers a move
                        # Note: automatically set to 1 when NVRAM wl1_chanspec overrides PREFERRED (dual-band only)
MANAGE_CRON=1           # 1/0 to add/remove cron and init-start entries
VERBOSE=2               # 0=silent, 1=basic logs, 2=verbose (includes DFS status blocks)
LOG_ROTATE_RAM=1        # 1=RAM‑only log rotation, 0=use temp file on disk
LOG_LINES=200
```

---

## Dual‑band behavior

### PREFERRED and block ranges

`PREFERRED` sets the target 160 MHz chanspec. The block range is derived automatically:

- `PREFERRED` channel 36–64 → block range 36–64, opposite block 100–128
- `PREFERRED` channel 100–128 → block range 100–128, opposite block 36–64

### DISABLE_FALLBACK

- `1`: Script only ever attempts `PREFERRED`. No cross‑block fallback.
- `0`: If the preferred block is unavailable, the script tries the opposite 160 MHz block.

### STRICT_STICKY

- `0`: Any 160 MHz channel within the preferred block is acceptable. No action taken.
- `1`: Must be on the exact `PREFERRED` chanspec. Any deviation triggers a move back.

### Recovery target when not on 160 MHz

- `STRICT_STICKY=1` → always move to `PREFERRED`
- Within preferred block → upgrade in place on current channel (e.g. `52/160`)
- Outside preferred block → move to `PREFERRED`

### NVRAM override

Reads `wl1_chanspec` from NVRAM to respect the router GUI settings:

- `wl1_chanspec=0` (Auto) → uses script config defaults
- Valid `*/160` chanspec → overrides `PREFERRED`, forces `DISABLE_FALLBACK=1` and `STRICT_STICKY=1`

---

## Tri‑band behavior

Each radio has a fixed block assignment — no NVRAM override, no fallback:

| Interface | Block | Preferred chanspec |
|-----------|-------|--------------------|
| IFACE1 | 36–64 | `36/160` |
| IFACE2 | 100–128 | `100/160` |

This prevents overlap between the two radios. Each radio is processed independently with its own lock file and cooldown.

### STRICT_STICKY in tri‑band

- `0`: Any 160 MHz channel within the assigned block is acceptable.
- `1`: Must be on the exact preferred chanspec (`36/160` or `100/160`). Any deviation triggers a move back.

### Recovery target when not on 160 MHz (tri‑band)

- `STRICT_STICKY=1` → always move to preferred (`36/160` or `100/160`)
- Within assigned block → upgrade in place on current channel (e.g. `52/160`)
- Outside assigned block → move to preferred

---

## How it works (step‑by‑step)

1. **Self‑registration**
   If `MANAGE_CRON=1`, adds cron job and `init-start` entry. If `0`, removes them.

2. **Mode selection**
   Determines dual‑band or tri‑band mode from `IFACE1`/`IFACE2` config or auto‑detection.

3. **NVRAM override** *(dual‑band only)*
   Reads `wl1_chanspec`. If a valid 160 MHz chanspec is set in the GUI, overrides `PREFERRED`, `DISABLE_FALLBACK`, and `STRICT_STICKY`.

4. **For each radio** (`process_radio` runs once for dual‑band, twice for tri‑band):

   a. **Cooldown check** — skip if last attempt was within `COOLDOWN` seconds  
   b. **Radio up check** — skip if radio is down  
   c. **Read current chanspec**  
   d. **Already on 160 MHz?**
      - `STRICT_STICKY=1` + wrong exact channel → move to preferred
      - Outside assigned block → move to preferred
      - Fine where it is → no action  
   e. **Not on 160 MHz** → determine recovery target → attempt `dfs_ap_move`
      - Rejected (+ fallback available in dual‑band) → try fallback
      - All rejected → hold until next cron run
      - Accepted → stamp lock file → poll for CAC completion → verify result

5. **Log rotation**
   Caps log at `LOG_LINES` lines on exit.

---

## Quick install

```sh
curl -L "https://raw.githubusercontent.com/soul4kills/hindsight160/refs/heads/main/hindsight160/hindsight160.sh" -o /jffs/scripts/hindsight160.sh && \
chmod 755 /jffs/scripts/hindsight160.sh && \
cru a hindsight160 "1,31 * * * * /jffs/scripts/hindsight160.sh"
```

---

## Step‑by‑step install

1. Download:
   ```sh
   curl -L "https://raw.githubusercontent.com/soul4kills/hindsight160/refs/heads/main/hindsight160/hindsight160.sh" -o /jffs/scripts/hindsight160.sh
   ```

2. Make executable:
   ```sh
   chmod 755 /jffs/scripts/hindsight160.sh
   ```

3. Add cron job:
   ```sh
   cru a hindsight160 "1,31 * * * * /jffs/scripts/hindsight160.sh"
   ```

4. The script will auto‑create/update `/jffs/scripts/init-start` on first run if `MANAGE_CRON=1`.

---

## Managing the script

### Remove the cron job
```sh
cru d hindsight160
```

### Disable self‑registration
Set `MANAGE_CRON=0` and run the script once. It will remove the cron job and its entry from `init-start`.

---

## Logging and troubleshooting

- Logs are written to `/jffs/scripts/hindsight160.log`
- `VERBOSE` levels:
  - `0`: Silent
  - `1`: Basic info — mode, actions, CAC poll results, recovery outcome
  - `2`: Verbose — full `dfs_ap_move` status blocks at each poll interval

To inspect current DFS status manually:
```sh
wl -i eth6 dfs_ap_move
```
Replace `eth6` with your actual 5 GHz interface name.

To check what interfaces your router uses:
```sh
nvram get wl_ifnames
```

To check what channel the GUI has configured:
```sh
nvram get wl1_chanspec
```
