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

Originally released here on this forum.   
https://www.snbforums.com/threads/script-160mhz-channel-recovery-for-wifi-6-only-routers.96964/

***

## 📦 Features

- **Auto‑detects** 5 GHz radios from `wl_ifnames` if `IFACE1`/`IFACE2` are left empty.  
- **Dual‑band** mode: single 5 GHz radio with preferred 160 MHz block and optional fallback to the other 160 MHz block.  
- **Tri‑band** mode: two 5 GHz radios with fixed 160 MHz blocks:
  - `IFACE1`: 36–64 MHz block (e.g., `36/160`)  
  - `IFACE2`: 100–128 MHz block (e.g., `100/160`)  
- **BG‑DFS aware**: checks `bgdfs160` capability and only acts when there are 160 MHz‑capable clients.  
- **Cooldown & CAC**: avoids flapping by enforcing a cooldown between recovery attempts and polling CAC status up to a configurable timeout.  
- **Configurable behavior**:
  - `PREFERRED`, `ENABLE_FALLBACK`, and `STRICT_STICKY` knobs.  
  - `COOLDOWN`, `CAC_POLL`, and `CAC_TIMEOUT` timing.  
  - Logging level (`VERBOSE`) and log‑rotation behavior.  
- **Self‑installing**: `install`/`uninstall` subcommands create/remove `cru` cron jobs and an `init‑start` script.  
- **Interactive menu**: edit settings directly from the router console or SSH.

***

## Zero-configuration behavior

`hindsight160.sh` is designed to work **without any manual setup** on most Asuswrt-Merlin routers.

If you already configured your 5 GHz wireless settings in the **router GUI**, the script will read and respect those settings automatically:

- **Preferred 160 MHz channel** comes from the GUI/NVRAM when a fixed 160 MHz chanspec is set.
- **Fallback behavior** is derived from the script settings only when the router is not locked to a fixed 160 MHz chanspec.
- **Sticky mode** is automatically enforced when the GUI/NVRAM is set to a fixed 160 MHz channel.
- If both `IFACE1` and `IFACE2` are left empty, the script can auto-detect the 5 GHz interfaces.

In other words, you can usually install the script and let it follow your router’s existing wireless configuration. Manual editing is only needed if you want to force specific interfaces or override the defaults.

***

## ⚙️ Requirements

- **Router firmware**: Asuswrt‑Merlin or similar (supports `wl`, `nvram`, and `cru`).  
- **5 GHz radio(s)** capable of 160 MHz channel width and DFS.  
- Root‑level shell access (SSH).  

This script assumes your router exposes `wl_ifnames` and `wl -i $iface dfs_ap_move` for BG‑DFS moves.

***

## 🧩 Dual‑ vs. Tri‑Band Mode

| Mode        | IFACE1 | IFACE2 | Behavior                                                                 |
|------------|--------|--------|--------------------------------------------------------------------------|
| Dual‑band  | set    | unset  | Single 5 GHz radio; `PREFERRED` block + optional fallback.              |
| Tri‑band   | set    | set    | Two 5 GHz radios; fixed 36–64 and 100–128 blocks, no fallback.         |

If both `IFACE1` and `IFACE2` are **empty**, the script auto‑detects 5 GHz radios from `nvram get wl_ifnames`.

***

## ⚙️ Configuration Options

Most behavior is controlled by these variables at the top of the script:

| Variable            | Valid values                       | Meaning                                                                 |
|---------------------|------------------------------------|-------------------------------------------------------------------------|
| `IFACE1`            | interface name (e.g., `eth6`)      | First 5 GHz interface; auto‑detect if empty.                           |
| `IFACE2`            | interface name (e.g., `eth7`)      | Second 5 GHz radio (tri‑band only).                                    |
| `PREFERRED`         | e.g., `100/160` or `36/160`        | Target 160 MHz chanspec for dual‑band.                                 |
| `ENABLE_FALLBACK`   | `0` or `1`                         | Allow fallback to the other 160 MHz block if primary fails.            |
| `STRICT_STICKY`     | `0` or `1`                         | Enforce exact `PREFERRED` chanspec or any 160 MHz in the block.        |
| `COOLDOWN`          | seconds (e.g., `60`)               | Min delay between recovery attempts.                                   |
| `CAC_POLL`          | seconds (≥ `60`)                   | Interval between CAC status polls.                                     |
| `CAC_TIMEOUT`       | seconds (e.g., `660`)              | Max wait for CAC before giving up.                                     |
| `MANAGE_CRON`       | `0` or `1`                         | Auto‑manage `cru` cron and `init‑start` entries.                       |
| `VERBOSE`           | `0`, `1`, or `2`                   | Log level: `0` = silent, `2` = verbose DFS blocks.                     |
| `LOG_ROTATE_RAM`    | `0` or `1`                         | Rotate log in RAM vs using a temp file.                                |
| `LOG_LINES`         | positive integer                   | Number of log lines to keep after rotation.                            |

Fixed‑channel 160 MHz settings in the **router GUI / NVRAM** (`wl1_chanspec`) override `PREFERRED` and force `ENABLE_FALLBACK=0` and `STRICT_STICKY=1`.

***

## 📜 Usage

Store the script on your router (e.g., in `/jffs/scripts/`):

```sh
# Example location
/jffs/scripts/hindsight160.sh
```

### 1. Run directly

```sh
# Run script (same as `exec`, used by cron)
/jffs/scripts/hindsight160.sh

# Run script explicitly
/jffs/scripts/hindsight160.sh exec

# Open interactive config menu
/jffs/scripts/hindsight160.sh menu
```

### 2. Install (cron + init‑start)

```sh
/jffs/scripts/hindsight160.sh install
```

This:
- Adds a cron job via `cru a "hindsight160" "1,31 * * * * /jffs/scripts/hindsight160.sh exec"`.  
- Creates or updates `/jffs/scripts/init-start` so the cron job survives reboots.

### 3. Uninstall

```sh
/jffs/scripts/hindsight160.sh uninstall
```

Removes the cron job, `init‑start` entry, and optionally the script and log with prompts.

***

## 📋 Menu Usage

Run:

```sh
/jffs/scripts/hindsight160.sh menu
```

You can then configure:
- Interfaces (`IFACE1`, `IFACE2`)  
- `PREFERRED` 160 MHz chanspec  
- `ENABLE_FALLBACK` and `STRICT_STICKY` behavior  
- Timing (cooldown, CAC polling, timeout)  
- Logging (`VERBOSE`, `LOG_ROTATE_RAM`, `LOG_LINES`)  
- Auto‑install behavior (`MANAGE_CRON`)  

Changes are written back into the script file using `sed`, so the configuration is persistent.

***

## 📊 Logging & Diagnostics

- Log file: `/jffs/scripts/hindsight160.log` by default.  
- If `VERBOSE` ≥ `2`, full `wl -i $iface dfs_ap_move` output and DFS status blocks are logged for debugging CAC delays.  
- After each run, the log is rotated to retain the last `LOG_LINES` lines.

Use `VERBOSE=2` if you want to see why a CAC is taking long or failing (e.g., weather‑radar channels 120/124/128).

***

## 🛠️ Customization Hints

- **Region‑specific 160 MHz channels**: If your region has limited 160 MHz channels, set a fixed 160 MHz channel in the **router GUI**; the script will maintain that exact channel.  

- **RAM‑ vs disk‑based log rotation**:  
  - `LOG_ROTATE_RAM=1` keeps log trimming in RAM (faster, but lost on power loss).  
  - `LOG_ROTATE_RAM=0` uses a `.tmp` file for rotation (safer if power‑loss is a concern).  


## Quick install

```sh
curl -L "https://raw.githubusercontent.com/soul4kills/Asus-Merlin-Scripts/refs/heads/main/hindsight160/hindsight160.sh" -o /jffs/scripts/hindsight160.sh && \
chmod 755 /jffs/scripts/hindsight160.sh && \
cru a hindsight160 "1,31 * * * * /jffs/scripts/hindsight160.sh"
```

---

## Step‑by‑step install

1. Download:
   ```sh
   curl -L "https://raw.githubusercontent.com/soul4kills/Asus-Merlin-Scripts/refs/heads/main/hindsight160/hindsight160.sh" -o /jffs/scripts/hindsight160.sh
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
