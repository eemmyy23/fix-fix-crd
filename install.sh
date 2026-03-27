#!/bin/bash
# Chrome Remote Desktop - Shared Session Setup
# Tested on: Ubuntu 24.04 + GDM3 + X11
# What this does: makes CRD show your existing desktop (shared session)
#                 instead of creating a separate virtual display.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# Run AFTER: logging in to your desktop session (not from SSH headless)
# Run BEFORE: authorizing CRD in the browser

set -e

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info() { echo -e "     $*"; }

# ── Detect environment ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="${SUDO_USER:-$USER}"
USER_ID="$(id -u "$CURRENT_USER")"
XAUTH_PATH="/run/user/${USER_ID}/gdm/Xauthority"
CRD_SCRIPT="/opt/google/chrome-remote-desktop/chrome-remote-desktop"
OVERRIDE_DIR="/etc/systemd/system/chrome-remote-desktop@${CURRENT_USER}.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
HOOK_FILE="/etc/apt/apt.conf.d/99-fix-crd"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Chrome Remote Desktop — Shared Session Installer"
echo "═══════════════════════════════════════════════════════"
echo "  User : $CURRENT_USER (UID $USER_ID)"
echo "  Auth : $XAUTH_PATH"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Preflight checks ───────────────────────────────────────────────────────────
echo "[ Preflight checks ]"

[[ "$EUID" -ne 0 ]] && fail "Run with sudo: sudo ./install.sh"

# Must be run as a real user via sudo, not directly as root
[[ -z "$SUDO_USER" ]] && warn "SUDO_USER not set — assuming user is: $CURRENT_USER"

# Check display server
SESSION_TYPE=$(loginctl show-session \
    "$(loginctl | awk "/$CURRENT_USER/{print \$1}" | head -1)" \
    -p Type 2>/dev/null | cut -d= -f2 || echo "unknown")

if [[ "$SESSION_TYPE" != "x11" ]]; then
    warn "Display server is '$SESSION_TYPE', not x11."
    warn "This setup requires X11. You may need to disable Wayland first (see README)."
    read -rp "     Continue anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
else
    ok "Display server: X11"
fi

# Check GDM
if systemctl is-active --quiet gdm; then
    ok "Display manager: GDM running"
else
    warn "GDM does not appear to be active — this setup is tuned for GDM3"
fi

# Check CRD is installed
if [[ ! -f "$CRD_SCRIPT" ]]; then
    fail "Chrome Remote Desktop not found at $CRD_SCRIPT — install it first."
fi
ok "CRD script found"

# Check XAUTHORITY file exists
if [[ ! -f "$XAUTH_PATH" ]]; then
    fail "XAUTHORITY not found at $XAUTH_PATH — are you logged in to the desktop?"
fi
ok "XAUTHORITY found: $XAUTH_PATH"

echo ""
echo "[ Step 1 — Lock X11 in GDM ]"

GDM_CONF="/etc/gdm3/custom.conf"
if grep -q "^WaylandEnable=false" "$GDM_CONF" 2>/dev/null; then
    ok "Wayland already disabled in GDM"
else
    # Uncomment if commented, or append to [daemon] section
    if grep -q "^#WaylandEnable=false" "$GDM_CONF" 2>/dev/null; then
        sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' "$GDM_CONF"
    else
        # Add under [daemon] section
        sed -i '/^\[daemon\]/a WaylandEnable=false' "$GDM_CONF"
    fi
    ok "Wayland disabled in GDM"
fi

echo ""
echo "[ Step 2 — Systemd service override ]"

mkdir -p "$OVERRIDE_DIR"
cat > "$OVERRIDE_FILE" << EOF
[Unit]
After=gdm.service display-manager.service
Requires=display-manager.service

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=${XAUTH_PATH}
EOF
ok "Override written: $OVERRIDE_FILE"

echo ""
echo "[ Step 3 — Patch CRD Python script ]"

# Backup original if not already backed up
if [[ ! -f "${CRD_SCRIPT}.orig" ]]; then
    cp "$CRD_SCRIPT" "${CRD_SCRIPT}.orig"
    ok "Backup saved: ${CRD_SCRIPT}.orig"
else
    ok "Backup already exists: ${CRD_SCRIPT}.orig"
fi

python3 "$SCRIPT_DIR/crd_patch_launch_server.py"
python3 "$SCRIPT_DIR/crd_patch_desktop_session.py"

echo ""
echo "[ Step 4 — dpkg hook (survives CRD updates) ]"

cat > "$HOOK_FILE" << EOF
DPkg::Post-Invoke {"python3 '${SCRIPT_DIR}/crd_patch_launch_server.py' || true; python3 '${SCRIPT_DIR}/crd_patch_desktop_session.py' || true;";};
EOF
ok "dpkg hook written: $HOOK_FILE"

echo ""
echo "[ Step 5 — Reload and restart service ]"

systemctl daemon-reload
systemctl enable "chrome-remote-desktop@${CURRENT_USER}"
systemctl restart "chrome-remote-desktop@${CURRENT_USER}"

sleep 2

STATUS=$(systemctl is-active "chrome-remote-desktop@${CURRENT_USER}")
if [[ "$STATUS" == "active" ]]; then
    ok "Service is running"
else
    fail "Service failed to start — run: journalctl -u chrome-remote-desktop@${CURRENT_USER} -n 30"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "  ${GREEN}Done!${NC} Open Chrome Remote Desktop in your browser."
echo "  The machine should now appear online and show"
echo "  your current desktop when you connect."
echo ""
echo "  If the machine is not visible, wait ~30s and refresh."
echo "  Logs: journalctl -u chrome-remote-desktop@${CURRENT_USER} -f"
echo "═══════════════════════════════════════════════════════"
echo ""
