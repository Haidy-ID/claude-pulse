#!/bin/bash
# claude-pulse installer
# Usage: curl -sS https://raw.githubusercontent.com/Haidy-ID/claude-pulse/main/install.sh | bash

set -e

RAW_BASE="https://raw.githubusercontent.com/Haidy-ID/claude-pulse/main"
INSTALL_DIR="$HOME/.claude"
SCRIPT_NAME="claude-pulse.sh"
HOOK_NAME="claude-pulse-lastdone.sh"
SETTINGS_FILE="$INSTALL_DIR/settings.json"
STATUSLINE_CMD="bash ~/.claude/$SCRIPT_NAME"
HOOK_CMD="bash ~/.claude/$HOOK_NAME"

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

# Download scripts
info "Downloading $SCRIPT_NAME..."
curl -sS "$RAW_BASE/$SCRIPT_NAME" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
ok "Status line installed to $INSTALL_DIR/$SCRIPT_NAME"

info "Downloading $HOOK_NAME..."
curl -sS "$RAW_BASE/$HOOK_NAME" -o "$INSTALL_DIR/$HOOK_NAME"
chmod +x "$INSTALL_DIR/$HOOK_NAME"
ok "Last done hook installed to $INSTALL_DIR/$HOOK_NAME"

# Configure settings.json
[ -f "$SETTINGS_FILE" ] || printf '{}\n' > "$SETTINGS_FILE"

jq empty "$SETTINGS_FILE" 2>/dev/null || fail "$SETTINGS_FILE is not valid JSON — fix it first"

# statusLine is an object, not a string. Ask before displacing another one.
current=$(jq -r '.statusLine.command // .statusLine // ""' "$SETTINGS_FILE" 2>/dev/null)
set_statusline=1
if [ -n "$current" ] && [ "$current" != "null" ] && [ "$current" != "$STATUSLINE_CMD" ]; then
    warn "A status line is already configured"
    printf "  ${DIM}Current: %s${R}\n" "$current"
    printf "  ${WHITE}Replace with claude-pulse? [y/N] ${R}"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]] || set_statusline=0
fi

tmp="${SETTINGS_FILE}.tmp.$$"
jq --arg sl "$STATUSLINE_CMD" --arg hk "$HOOK_CMD" --argjson setsl "$set_statusline" '
    # Status line
    (if $setsl == 1 then .statusLine = {type: "command", command: $sl} else . end)
    # Stop hook: append, never displace hooks that are already there
    | (if ([.hooks.Stop[]?.hooks[]?.command] | index($hk)) then .
       else .hooks.Stop = ((.hooks.Stop // []) + [{
                matcher: "",
                hooks: [{type: "command", command: $hk, timeout: 5}]
            }])
       end)
' "$SETTINGS_FILE" > "$tmp"

# Back up only when something is actually about to change. Re-running the
# installer to pick up an update is a no-op, and a no-op should not leave
# another timestamped copy of settings.json behind forever.
if cmp -s "$tmp" "$SETTINGS_FILE"; then
    rm -f "$tmp"
    info "Settings already up to date"
else
    backup="${SETTINGS_FILE}.bak-claude-pulse-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_FILE" "$backup"
    ok "Settings backed up to $backup"
    mv -f "$tmp" "$SETTINGS_FILE"
    [ "$set_statusline" -eq 1 ] && ok "Status line configured" || info "Status line left untouched"
    ok "Last done Stop hook registered"
fi

echo ""
printf "${GREEN}${BOLD}Done!${R} Restart Claude Code to see the pulse.\n"
printf "${DIM}● Opus │ 60k/200k 30%% │ 4h12 2%% ░░░░░░░░ │ 4d 27%% Fri${R}\n"
printf "${DIM}Last done: The status line now carries a second row.${R}\n"
echo ""
