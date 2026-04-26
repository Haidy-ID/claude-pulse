#!/bin/bash
# codex-pulse installer

set -e

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/codex-pulse.sh"
TARGET_SCRIPT="$CODEX_HOME/codex-pulse.sh"
STATUS_LINE='status_line = ["model", "used-tokens", "context-used", "five-hour-limit", "weekly-limit", "fast-mode"]'
TERMINAL_TITLE='terminal_title = ["spinner", "project", "model"]'

GREEN="\033[38;2;52;211;153m"
AMBER="\033[38;2;251;191;36m"
RED="\033[38;2;248;113;113m"
DIM="\033[38;2;107;114;128m"
WHITE="\033[38;2;255;255;255m"
BOLD="\033[1m"
R="\033[0m"

info() { printf "${WHITE}${BOLD}●${R} %s\n" "$1"; }
ok() { printf "${GREEN}${BOLD}✓${R} %s\n" "$1"; }
warn() { printf "${AMBER}${BOLD}!${R} %s\n" "$1"; }
fail() { printf "${RED}${BOLD}x${R} %s\n" "$1"; exit 1; }

timestamp() {
    date +"%Y%m%d%H%M%S"
}

patch_config() {
    local tmp="$CONFIG_FILE.tmp.$$"
    awk -v status="$STATUS_LINE" -v title="$TERMINAL_TITLE" '
        BEGIN {
            in_tui = 0
            saw_tui = 0
            wrote_status = 0
            wrote_title = 0
            skip = ""
        }

        function emit_missing() {
            if (!wrote_status) {
                print status
                wrote_status = 1
            }
            if (!wrote_title) {
                print title
                wrote_title = 1
            }
        }

        function starts_array(value) {
            return value ~ /\[[[:space:]]*$/
        }

        {
            if (skip != "") {
                if ($0 ~ /\]/) {
                    skip = ""
                }
                next
            }

            if ($0 ~ /^\[[^]]+\][[:space:]]*$/) {
                if (in_tui) {
                    emit_missing()
                    in_tui = 0
                }
                if ($0 ~ /^\[tui\][[:space:]]*$/) {
                    saw_tui = 1
                    in_tui = 1
                }
                print
                next
            }

            if (in_tui && $0 ~ /^[[:space:]]*status_line[[:space:]]*=/) {
                if (!wrote_status) {
                    print status
                    wrote_status = 1
                }
                if (starts_array($0) && $0 !~ /\]/) {
                    skip = "status_line"
                }
                next
            }

            if (in_tui && $0 ~ /^[[:space:]]*terminal_title[[:space:]]*=/) {
                if (!wrote_title) {
                    print title
                    wrote_title = 1
                }
                if (starts_array($0) && $0 !~ /\]/) {
                    skip = "terminal_title"
                }
                next
            }

            print
        }

        END {
            if (in_tui) {
                emit_missing()
            } else if (!saw_tui) {
                print ""
                print "[tui]"
                print status
                print title
            }
        }
    ' "$CONFIG_FILE" > "$tmp"
    mv -f "$tmp" "$CONFIG_FILE"
}

echo ""
printf "${WHITE}${BOLD}codex-pulse${R} ${DIM}- Graphical Codex CLI pulse sidecar${R}\n"
echo ""

command -v codex >/dev/null 2>&1 || fail "codex CLI is required but not installed"
ok "Codex found ($(codex --version 2>/dev/null | tail -1))"

command -v jq >/dev/null 2>&1 || warn "jq is missing; the graphical sidecar needs it"
command -v sqlite3 >/dev/null 2>&1 || warn "sqlite3 is missing; the graphical sidecar needs it"
[ -f "$SOURCE_SCRIPT" ] || fail "cannot find $SOURCE_SCRIPT"

mkdir -p "$CODEX_HOME"

if [ -f "$CONFIG_FILE" ]; then
    backup="$CONFIG_FILE.bak.$(timestamp)"
    cp "$CONFIG_FILE" "$backup"
    ok "Backup written to $backup"
else
    printf "# Codex config\n" > "$CONFIG_FILE"
    ok "Created $CONFIG_FILE"
fi

info "Configuring native status line..."
patch_config
ok "Configured [tui].status_line"

info "Installing graphical sidecar..."
cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"
ok "Installed $TARGET_SCRIPT"

echo ""
printf "${GREEN}${BOLD}Done.${R} Restart Codex for the native fallback line.\n"
printf "${DIM}Graphical pulse:${R} %s --watch\n" "$TARGET_SCRIPT"
printf "${DIM}One-shot:${R} %s\n" "$TARGET_SCRIPT"
printf "${DIM}tmux status-right:${R} set -g status-right '#(%s --tmux)'\n" "$TARGET_SCRIPT"
echo ""
