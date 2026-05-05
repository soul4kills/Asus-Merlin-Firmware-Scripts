<img width="1220" height="1282" alt="Screenshot 2026-05-03 075250" src="https://github.com/user-attachments/assets/e6824917-ffde-47b8-98e7-ae154f38af67" />
  
# Whitelist Window – Internet Block with Whitelist (AsusWRT‑Merlin)

This addon adds a Whitelist Window page to the AsusWRT‑Merlin web UI that lets you:
- Schedule a time window when all devices are blocked from internet access.
- Whitelist specific MACs, IP addresses, and interfaces so they remain exempt.
- Prevents clients from bypassing internet access blocks by mac address randomization
- Added a block persistence if reboot the router is a method of bypass to be concerned about

It is designed for AsusWRT‑Merlin firmware and uses the JFFS partition and SSH.   
Originally released here.  
https://www.snbforums.com/threads/kids-bypassing-parental-controls-time-scheduling-via-band-switching-mac-randomization-on-aimesh.97136/post-991676

---

## 1. Enable JFFS and SSH

Before installing, you must enable:

- **JFFS partition** (for `/jffs` storage).
- **SSH access** (to install and manage the addon).

### 1.1 Access your router’s web UI

Open in your browser:

```text
http://192.168.1.1
```

or the IP address of your ASUS router.

### 1.2 Enable SSH (if not already enabled)

1. Go to **System** → **Administration** (or **System Settings** → **Administration**).
2. In the **SSH** section:
   - Set **SSH Service** to **LAN Only** (or **LAN/WAN**, depending on your preference).
   - Optionally set or confirm the SSH port (default `22`).
3. Click **Apply**.

### 1.3 Enable JFFS partition

1. Still under **Administration** or in a **System** tab, look for **System** → **Administration**.
2. In the **System** section:
   - Check **Enable JFFS custom scripts and configs** (or **Format JFFS** / **Enable JFFS**).
   - Optionally click **Format JFFS** to initialize the partition.
3. Click **Apply**.

The router may reboot or continue; after that, the `/jffs` overlay filesystem will be available.

---

## 2. Install Whitelist Window addon

Connect to your router via SSH (e.g., using `ssh admin@192.168.1.1`), then run this one-liner:

```sh
mkdir -p /jffs/addons/wl_window && \
cd /jffs/addons/wl_window && \
curl -sL "https://raw.githubusercontent.com/soul4kills/Asus-Merlin-Scripts/refs/heads/main/wl_window/WL_Window.asp" -o WL_Window.asp && \
curl -sL "https://raw.githubusercontent.com/soul4kills/Asus-Merlin-Scripts/refs/heads/main/wl_window/wl_window.sh" -o wl_window.sh && \
curl -sL "https://raw.githubusercontent.com/soul4kills/Asus-Merlin-Scripts/refs/heads/main/wl_window/wl_window_install.sh" -o wl_window_install.sh && \
curl -sL "https://raw.githubusercontent.com/soul4kills/Asus-Merlin-Scripts/refs/heads/main/wl_window/wlwindow_service.sh" -o wlwindow_service.sh && \
sh wl_window.sh install
```

This:

- Creates the addon directory `/jffs/addons/wl_window`.  
- Downloads all required files into that directory.  
- Runs `wl_window.sh install` to:
  - Mount the `WL_Window.asp` into the web UI.  
  - Register cron jobs.  
  - Hook into `services-start` and `service-event`.

After installation, you can access the page at:

```text
http://192.168.1.1/ParentalControl.asp
```

or wherever Merlin maps your addon page (typically under **Tools**).

---

## 3. Usage

- Adjust **Block Schedule** (start / end time).
- Add or remove **MACs, IPs, or interfaces** in the whitelist.
- Use **Activate Block** / **Deactivate Block** for immediate control.
- View current status with in command line with `./wl_window.sh status`

---

## 4. Removal

To uninstall the addon, run:

```sh
sh /jffs/addons/wl_window/wl_window.sh uninstall
```

This will:
- Remove the cron jobs.  
- Remove the web UI entries.  
- Clean up service‑scripts links.

---

## 5. Notes

- This addon assumes:
  - You are running **AsusWRT‑Merlin** firmware.  
  - JFFS and SSH are enabled.
- If you change the router’s theme or web UI structure, the addon page may need re‑mapping.
- Always backup your router configuration before enabling new scripts and cron‑based firewall rules.
