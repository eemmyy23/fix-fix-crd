# Chrome Remote Desktop — Shared Session Setup

Configures Chrome Remote Desktop (CRD) on Ubuntu to show your **existing desktop**
instead of creating a separate virtual display. Local and remote see the exact same screen.

**Tested on:** Ubuntu 24.04 · GDM3 · X11

---

## The Problem

By default, CRD creates its own virtual X display (e.g. `:20`) with a dummy video driver.
When you connect remotely you get an isolated desktop — not what is shown on the physical screen.

## The Fix (what this does)

Three targeted changes:

| # | What | Where |
|---|------|--------|
| 1 | Lock GDM to X11 (prevent Wayland fallback) | `/etc/gdm3/custom.conf` |
| 2 | Service ordering + auth env vars | systemd drop-in override |
| 3 | Patch CRD Python script to skip virtual display | `/opt/google/chrome-remote-desktop/chrome-remote-desktop` |

### Patch detail

CRD's `XDesktop` class always launches its own Xorg with a dummy driver.
Two methods are patched:

- **`_launch_server`** — instead of starting Xorg, sets `DISPLAY=:0` and points
  `XAUTHORITY` at GDM's auth file. Starts a `sleep infinity` as a dummy
  process so CRD's monitor loop has a "server" to watch.

- **`launch_desktop_session`** — instead of launching a new GNOME session,
  starts another `sleep infinity` so the monitor loop has a "session" to watch.
  The real session is already running via GDM.

---

## Quick Install (fresh Ubuntu)

### Prerequisites

1. Install Chrome Remote Desktop `.deb` from Google:
   ```
   https://remotedesktop.google.com/access
   ```
   Click **Set up via SSH** → download the `.deb` → install it:
   ```bash
   sudo dpkg -i chrome-remote-desktop_current_amd64.deb
   ```

2. Authorize the host in your browser (follow the Google setup flow).
   **Stop before clicking the final "Start" button** — run this script first.

3. Make sure you are **logged in to your desktop** (not SSH-only).

### Run the installer

```bash
cd "fix fix-crd"
chmod +x install.sh
sudo ./install.sh
```

That's it. The machine should appear in the CRD app within ~30 seconds.

---

## Files

```
fix fix-crd/
├── install.sh                    # One-shot installer — run this on a fresh system
├── crd_patch_launch_server.py    # Patches XDesktop._launch_server
├── crd_patch_desktop_session.py  # Patches XDesktop.launch_desktop_session
└── README.md                     # This file
```

---

## What happens on system restart?

| Scenario | Result |
|----------|--------|
| Normal boot (GDM starts first) | CRD starts after GDM (enforced by `After=gdm.service`) and attaches to `:0` |
| CRD starts before GDM | Unlikely due to ordering, but CRD would fail and systemd would not auto-restart it (no `Restart=` policy) |
| Unclean shutdown | No stale lock files to worry about — GDM manages `:0` and recreates its socket cleanly |
| CRD package update | dpkg hook at `/etc/apt/apt.conf.d/99-fix-crd` re-runs both patch scripts automatically |

---

## Local vs Remote display

Because both use the same `:0` display managed by GDM:

- Remote sees **exactly** what is on the physical screen
- Mouse/keyboard input from remote affects the local session (and vice versa)
- If local user is at the machine, both can control it simultaneously

---

## Risks

| Risk | Mitigation |
|------|-----------|
| CRD update overwrites Python script | dpkg hook re-applies patches automatically |
| GDM changes XAUTHORITY path after update | Run `echo $XAUTHORITY` and update override.conf if path changed |
| Wayland enabled by a system update | GDM config is persistent; Wayland stays disabled |
| UID changes (unlikely) | XAUTHORITY path uses UID — re-run installer if user is recreated |

---

## Manual verification

```bash
# Service status
systemctl status chrome-remote-desktop@$USER

# Network — should show connections to Google (142.250.x.x / 216.239.x.x)
ss -tnp | grep chrome-remote

# Process tree — should show sleep processes as dummy server/session
pstree -p $(pgrep -f "chrome-remote-desktop --child")

# Confirm display auth works
DISPLAY=:0 XAUTHORITY=/run/user/$(id -u)/gdm/Xauthority xdpyinfo | head -3

# Live logs
journalctl -u chrome-remote-desktop@$USER -f
```

---

## Uninstall / Revert

```bash
# Restore original CRD script
sudo cp /opt/google/chrome-remote-desktop/chrome-remote-desktop.orig \
        /opt/google/chrome-remote-desktop/chrome-remote-desktop

# Remove override and hook
sudo rm /etc/systemd/system/chrome-remote-desktop@$USER.service.d/override.conf
sudo rm /etc/apt/apt.conf.d/99-fix-crd

# Re-enable Wayland (optional)
sudo sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' /etc/gdm3/custom.conf

sudo systemctl daemon-reload
sudo systemctl restart chrome-remote-desktop@$USER
```
