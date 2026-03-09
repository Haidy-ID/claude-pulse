#!/bin/bash
# claude-pulse installer
# Usage: curl -sS https://raw.githubusercontent.com/lunndev/claude-pulse/main/install.sh | bash

set -e

REPO_URL="https://raw.githubusercontent.com/lunndev/claude-pulse/main/claude-pulse.sh"
INSTALL_DIR="$HOME/.claude"
SCRIPT_NAME="claude-pulse.sh"
SETTINGS_FILE="$INSTALL_DIR/settings.json"

# Colors
GREEN="\033[38;2;52;211;153m"
AMBER="\033[38;2;251;191;36m"
RED="\033[38;2;248;113;113m"
DIM="\033[38;2;107;114;128m"
WHITE="\033[38;2;255;255;255m"
BOLD="\033[1m"
R="\033[0m"

info()  { printf "${WHITE}${BOLD}●${R} %s\n" "$1"; }
ok()    { printf "${GREEN}${BOLD}✓${R} %s\n" "$1"; }
warn()  { printf "${AMBER}${BOLD}!${R} %s\n" "$1"; }
fail()  { printf "${RED}${BOLD}✗${R} %s\n" "$1"; exit 1; }

echo ""
printf "${WHITE}${BOLD}claude-pulse${R} ${DIM}— Status line for Claude Code${R}\n"
echo ""

# Check deps
command -v curl >/dev/null 2>&1 || fail "curl is required but not installed"
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"
ok "Dependencies OK (curl, jq)"

# Check Claude Code dir
[ -d "$INSTALL_DIR" ] || fail "$INSTALL_DIR not found — is Claude Code installed?"
ok "Claude Code directory found"

# Download script
info "Downloading claude-pulse.sh..."
curl -sS "$REPO_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
ok "Script installed to $INSTALL_DIR/$SCRIPT_NAME"

# Configure settings.json
if [ -f "$SETTINGS_FILE" ]; then
    # Check if statusline is already configured
    current=$(jq -r '.statusline // ""' "$SETTINGS_FILE" 2>/dev/null)
    if [ -n "$current" ] && [ "$current" != "null" ]; then
        warn "statusline already configured in settings.json"
        printf "  ${DIM}Current: %s${R}\n" "$current"
        printf "  ${WHITE}Replace with claude-pulse? [y/N] ${R}"
        read -r reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            info "Skipped settings update. To enable manually, add to $SETTINGS_FILE:"
            printf "  ${DIM}\"statusline\": \"bash ~/.claude/claude-pulse.sh\"${R}\n"
            echo ""
            exit 0
        fi
    fi
    # Update settings
    tmp="${SETTINGS_FILE}.tmp.$$"
    jq '.statusline = "bash ~/.claude/claude-pulse.sh"' "$SETTINGS_FILE" > "$tmp" && mv -f "$tmp" "$SETTINGS_FILE"
else
    # Create settings
    printf '{\n  "statusline": "bash ~/.claude/claude-pulse.sh"\n}\n' > "$SETTINGS_FILE"
fi
ok "Settings configured"

echo ""
printf "${GREEN}${BOLD}Done!${R} Restart Claude Code to see the pulse.\n"
printf "${DIM}Layout: ● Opus │ 60k·200k 30%% │ 4h12 2%% ░░░░░░░░ │ 4j 27%% Ven.${R}\n"
echo ""
