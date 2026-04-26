#!/bin/bash
# codex-pulse - graphical sidecar status line for Codex CLI sessions.

set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
STATE_DB="${CODEX_PULSE_STATE_DB:-$CODEX_HOME/state_5.sqlite}"
CONFIG_FILE="${CODEX_PULSE_CONFIG:-$CODEX_HOME/config.toml}"
PULSE_STATE_FILE="${CODEX_PULSE_STATE_FILE:-$CODEX_HOME/codex-pulse-state.json}"
TAIL_LINES="${CODEX_PULSE_TAIL_LINES:-2000}"
BAR_WIDTH="${CODEX_PULSE_BAR_WIDTH:-8}"
INTERVAL="${CODEX_PULSE_INTERVAL:-2}"
PULSE_CWD="${CODEX_PULSE_CWD:-$(pwd -P 2>/dev/null || pwd)}"
SESSION_PATH="${CODEX_PULSE_SESSION:-}"
PLAIN=0
MODE="render"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --watch)
            MODE="watch"
            shift
            if [ "${1:-}" != "" ] && [[ "${1:-}" =~ ^[0-9]+$ ]]; then
                INTERVAL="$1"
                shift
            fi
            ;;
        --plain|--tmux|--no-color)
            PLAIN=1
            shift
            ;;
        --cwd)
            PULSE_CWD="${2:-}"
            shift 2
            ;;
        --session)
            SESSION_PATH="${2:-}"
            shift 2
            ;;
        -h|--help)
            cat <<'EOF'
codex-pulse

Usage:
  ./codex-pulse.sh                 Print one graphical status line
  ./codex-pulse.sh --watch [sec]   Redraw in place every N seconds
  ./codex-pulse.sh --plain         Disable ANSI color, keep bars
  ./codex-pulse.sh --tmux          Alias for --plain
  ./codex-pulse.sh --check         Diagnose local Codex data sources

Environment:
  CODEX_HOME                Default: ~/.codex
  CODEX_PULSE_CWD           Prefer the latest thread for this cwd
  CODEX_PULSE_SESSION       Read a specific rollout JSONL file
  CODEX_PULSE_SERVICE_TIER  Override detected service tier
  CODEX_PULSE_REASONING_EFFORT Override detected thinking mode
  CODEX_PULSE_PERMISSION_MODE Override detected permission mode
  CODEX_PULSE_BAR_WIDTH     Default: 8
  CODEX_PULSE_TAIL_LINES    Default: 2000
EOF
            exit 0
            ;;
        *)
            printf "codex-pulse: unknown option: %s\n" "$1" >&2
            exit 2
            ;;
    esac
done

if [ "${NO_COLOR:-}" != "" ] || [ "${CODEX_PULSE_NO_COLOR:-}" != "" ]; then
    PLAIN=1
fi

if ! [[ "$BAR_WIDTH" =~ ^[0-9]+$ ]] || [ "$BAR_WIDTH" -lt 1 ]; then
    BAR_WIDTH=8
fi
if ! [[ "$TAIL_LINES" =~ ^[0-9]+$ ]] || [ "$TAIL_LINES" -lt 1 ]; then
    TAIL_LINES=2000
fi
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
    INTERVAL=2
fi

IS_MAC=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MAC=true

if [ -z "${CODEX_PULSE_LANG:-}" ]; then
    case "${LC_TIME:-${LANG:-en}}" in
        fr*) CODEX_PULSE_LANG="fr" ;;
        *) CODEX_PULSE_LANG="en" ;;
    esac
fi

if [ "$PLAIN" -eq 0 ] && { [ -t 1 ] || [ "${CODEX_PULSE_FORCE_COLOR:-}" != "" ]; }; then
    R=$'\033[0m'
    B=$'\033[1m'
    c_white=$'\033[38;2;255;255;255m'
    c_warn=$'\033[38;2;251;191;36m'
    c_bad=$'\033[38;2;248;113;113m'
    c_crit=$'\033[38;2;220;60;60m'
    c_sep=$'\033[38;2;75;85;99m'
    c_dim=$'\033[38;2;107;114;128m'
else
    R=""
    B=""
    c_white=""
    c_warn=""
    c_bad=""
    c_crit=""
    c_sep=""
    c_dim=""
fi

SEP=" ${c_sep}│${R} "

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

config_value() {
    local key="$1"
    [ -r "$CONFIG_FILE" ] || return 1

    awk -v key="$key" '
        /^[[:space:]]*\[/ {
            top_level = 0
        }

        /^[[:space:]]*$/ || /^[[:space:]]*#/ {
            next
        }

        top_level || NR == 1 {
            if ($0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
                sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "")
                gsub(/^[[:space:]]*"|"[[:space:]]*$/, "")
                print
                found = 1
                exit
            }
        }

        {
            top_level = ($0 !~ /^[[:space:]]*\[/)
        }
    ' "$CONFIG_FILE"
}

require_number() {
    case "${1:-}" in
        ''|null|*[!0-9.-]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

round_percent() {
    local value="${1:-}"
    if ! require_number "$value"; then
        printf ""
        return
    fi
    awk -v p="$value" 'BEGIN { printf "%.0f", p }'
}

parse_utilization() {
    local value="${1:-0}"
    value="${value//[[:space:]]/}"
    if ! require_number "$value"; then
        value=0
    fi
    value=${value%%.*}
    if [ "$value" -gt 100 ] 2>/dev/null; then
        value=100
    fi
    if [ "$value" -lt 0 ] 2>/dev/null; then
        value=0
    fi
    printf "%d" "$value"
}

calc_percent() {
    local used="${1:-}"
    local total="${2:-}"
    if ! require_number "$used" || ! require_number "$total"; then
        printf ""
        return
    fi
    awk -v used="$used" -v total="$total" '
        BEGIN {
            if (total <= 0) {
                exit
            }
            p = used * 100 / total
            if (p > 0 && p < 1) {
                printf "%.1f", p
            } else {
                printf "%.0f", p
            }
        }
    '
}

color_for_percent() {
    local pct="${1:-}"
    if ! require_number "$pct"; then
        printf "%s" "$c_dim"
        return
    fi
    awk -v p="$pct" 'BEGIN { exit !(p >= 80) }' && {
        printf "%s" "$c_bad"
        return
    }
    awk -v p="$pct" 'BEGIN { exit !(p >= 50) }' && {
        printf "%s" "$c_warn"
        return
    }
    printf "%s" "$c_white"
}

primary_color_for_percent() {
    local pct="${1:-}"
    local now
    if ! require_number "$pct"; then
        printf "%s" "$c_dim"
        return
    fi
    awk -v p="$pct" 'BEGIN { exit !(p >= 80) }' && {
        now=$(date +%s)
        if [ $((now % 2)) -eq 0 ]; then
            printf "%s" "$c_bad"
        else
            printf "%s" "$c_crit"
        fi
        return
    }
    awk -v p="$pct" 'BEGIN { exit !(p >= 50) }' && {
        printf "%s" "$c_warn"
        return
    }
    printf "%s" "$c_white"
}

format_tokens() {
    local value="${1:-}"
    if ! require_number "$value"; then
        printf "--"
        return
    fi
    awk -v n="$value" '
        BEGIN {
            if (n >= 1000000000) {
                printf "%.1fB", n / 1000000000
            } else if (n >= 10000000) {
                printf "%.0fM", n / 1000000
            } else if (n >= 1000000) {
                printf "%.1fM", n / 1000000
            } else if (n >= 10000) {
                printf "%.0fk", n / 1000
            } else if (n >= 1000) {
                printf "%.1fk", n / 1000
            } else {
                printf "%.0f", n
            }
        }
    '
}

format_window_label() {
    local reset="${1:-}"
    local window="${2:-}"
    local now delta days hours minutes day_suffix

    day_suffix="d"
    [ "$CODEX_PULSE_LANG" = "fr" ] && day_suffix="j"

    if require_number "$reset"; then
        reset="${reset%.*}"
        now=$(date +%s)
        delta=$((reset - now))
        if [ "$delta" -le 0 ]; then
            printf "now"
            return
        fi

        days=$((delta / 86400))
        hours=$(((delta % 86400) / 3600))
        minutes=$(((delta % 3600) / 60))

        if [ "$days" -gt 0 ]; then
            printf "%d%s" "$days" "$day_suffix"
        elif [ "$hours" -gt 0 ]; then
            printf "%dh%02d" "$hours" "$minutes"
        else
            printf "%dm" "$minutes"
        fi
        return
    fi

    if require_number "$window"; then
        window="${window%.*}"
        if [ "$window" -ge 1440 ]; then
            printf "%d%s" $((window / 1440)) "$day_suffix"
        elif [ "$window" -ge 60 ]; then
            printf "%dh" $((window / 60))
        else
            printf "%dm" "$window"
        fi
        return
    fi

    printf "--"
}

epoch_fmt() {
    local epoch="$1"
    local fmt="$2"
    if $IS_MAC; then
        date -j -f "%s" "$epoch" +"$fmt" 2>/dev/null
    else
        date -d "@$epoch" +"$fmt" 2>/dev/null
    fi
}

day_name() {
    local epoch="$1"
    local dow
    dow=$(epoch_fmt "$epoch" "%u")
    if [ "$CODEX_PULSE_LANG" = "fr" ]; then
        case "$dow" in
            1) printf "Lun." ;;
            2) printf "Mar." ;;
            3) printf "Mer." ;;
            4) printf "Jeu." ;;
            5) printf "Ven." ;;
            6) printf "Sam." ;;
            7) printf "Dim." ;;
            *) printf "?" ;;
        esac
    else
        case "$dow" in
            1) printf "Mon" ;;
            2) printf "Tue" ;;
            3) printf "Wed" ;;
            4) printf "Thu" ;;
            5) printf "Fri" ;;
            6) printf "Sat" ;;
            7) printf "Sun" ;;
            *) printf "?" ;;
        esac
    fi
}

weekly_reset_suffix() {
    local reset="${1:-}"
    local now delta reset_day

    require_number "$reset" || return 0
    reset="${reset%.*}"
    now=$(date +%s)
    delta=$((reset - now))
    reset_day=$(day_name "$reset")
    [ "$reset_day" != "" ] || return 0

    if [ "$delta" -gt 0 ] && [ "$delta" -lt 172800 ]; then
        printf " %s %s" "$reset_day" "$(epoch_fmt "$reset" "%Hh%M")"
    else
        printf " %s" "$reset_day"
    fi
}

bar() {
    local pct="${1:-}"
    local width="$BAR_WIDTH"
    local pct_int filled empty color i

    pct_int=$(round_percent "$pct")
    if [ "$pct_int" = "" ]; then
        pct_int=0
    fi
    if [ "$pct_int" -lt 0 ]; then
        pct_int=0
    fi
    if [ "$pct_int" -gt 100 ]; then
        pct_int=100
    fi

    filled=$((pct_int * width / 100))
    empty=$((width - filled))
    color=$(primary_color_for_percent "$pct")

    printf "%s" "$color"
    i=0
    while [ "$i" -lt "$filled" ]; do
        printf "█"
        i=$((i + 1))
    done
    printf "%s" "$c_dim"
    i=0
    while [ "$i" -lt "$empty" ]; do
        printf "░"
        i=$((i + 1))
    done
    printf "%s" "$R"
}

find_latest_thread() {
    local cwd_sql row query

    if [ "$SESSION_PATH" != "" ]; then
        MODEL="${CODEX_PULSE_MODEL:-Codex}"
        REASONING_EFFORT="${CODEX_PULSE_REASONING_EFFORT:-$(config_value model_reasoning_effort)}"
        APPROVAL_MODE="${CODEX_PULSE_APPROVAL_MODE:-}"
        SANDBOX_POLICY="${CODEX_PULSE_SANDBOX_POLICY:-}"
        DB_TOKENS=""
        ROLLOUT_PATH="$SESSION_PATH"
        return 0
    fi

    [ -f "$STATE_DB" ] || return 1
    command -v sqlite3 >/dev/null 2>&1 || return 1

    cwd_sql=$(sql_escape "$PULSE_CWD")
    query="select coalesce(model,''), coalesce(reasoning_effort,''), coalesce(tokens_used,0), rollout_path, coalesce(approval_mode,''), coalesce(sandbox_policy,'') from threads where archived = 0 and cwd = '$cwd_sql' order by coalesce(updated_at_ms, updated_at * 1000) desc, id desc limit 1;"
    row=$(sqlite3 -noheader -separator $'\t' "$STATE_DB" "$query" 2>/dev/null | head -n 1)

    if [ "$row" = "" ]; then
        query="select coalesce(model,''), coalesce(reasoning_effort,''), coalesce(tokens_used,0), rollout_path, coalesce(approval_mode,''), coalesce(sandbox_policy,'') from threads where archived = 0 order by coalesce(updated_at_ms, updated_at * 1000) desc, id desc limit 1;"
        row=$(sqlite3 -noheader -separator $'\t' "$STATE_DB" "$query" 2>/dev/null | head -n 1)
    fi

    [ "$row" != "" ] || return 1
    IFS=$'\t' read -r MODEL REASONING_EFFORT DB_TOKENS ROLLOUT_PATH APPROVAL_MODE SANDBOX_POLICY <<< "$row"
    [ "$MODEL" != "" ] || MODEL="Codex"
    [ "$REASONING_EFFORT" != "" ] || REASONING_EFFORT="$(config_value model_reasoning_effort)"
    [ "$ROLLOUT_PATH" != "" ] || return 1
}

latest_payload() {
    [ -r "$ROLLOUT_PATH" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    tail -n "$TAIL_LINES" "$ROLLOUT_PATH" 2>/dev/null \
        | jq -rc 'select(.type == "event_msg" and .payload.type == "token_count") | .payload' 2>/dev/null \
        | tail -n 1
}

latest_turn_context() {
    [ -r "$ROLLOUT_PATH" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    tail -n "$TAIL_LINES" "$ROLLOUT_PATH" 2>/dev/null \
        | jq -rc 'select(.type == "turn_context") | .payload' 2>/dev/null \
        | tail -n 1
}

jq_value() {
    local json="$1"
    local expr="$2"
    printf "%s" "$json" | jq -r "$expr // empty" 2>/dev/null
}

permission_mode_label() {
    local turn_context="$1"
    local collaboration_mode approval_mode sandbox_type label

    if [ "${CODEX_PULSE_PERMISSION_MODE:-}" != "" ]; then
        printf "%s" "$CODEX_PULSE_PERMISSION_MODE"
        return
    fi

    collaboration_mode=$(jq_value "$turn_context" '.collaboration_mode.mode')
    approval_mode=$(jq_value "$turn_context" '.approval_policy')
    sandbox_type=$(jq_value "$turn_context" '.sandbox_policy.type')

    [ "$approval_mode" != "" ] || approval_mode="${APPROVAL_MODE:-}"
    if [ "$sandbox_type" = "" ] && [ "${SANDBOX_POLICY:-}" != "" ] && command -v jq >/dev/null 2>&1; then
        sandbox_type=$(printf "%s" "$SANDBOX_POLICY" | jq -r '.type // empty' 2>/dev/null)
    fi

    case "$collaboration_mode" in
        plan)
            label="Plan"
            ;;
        *)
            case "$sandbox_type:$approval_mode" in
                danger-full-access:*|*:never)
                    label="Bypass"
                    ;;
                *:on-request|*:on-failure|*:always|*:untrusted)
                    label="Ask"
                    ;;
                *)
                    label=""
                    ;;
            esac
            ;;
    esac

    printf "%s" "$label"
}

mode_segment() {
    local service_tier reasoning permission turn_context label=""

    service_tier="${CODEX_PULSE_SERVICE_TIER:-$(config_value service_tier)}"
    reasoning="${CODEX_PULSE_REASONING_EFFORT:-${REASONING_EFFORT:-$(config_value model_reasoning_effort)}}"
    turn_context=$(latest_turn_context || true)
    permission=$(permission_mode_label "$turn_context")

    case "$service_tier" in
        fast)
            label="Fast"
            ;;
        flex)
            label="Flex"
            ;;
        default|standard|"")
            label=""
            ;;
        *)
            label="$service_tier"
            ;;
    esac

    if [ "$reasoning" != "" ]; then
        if [ "$label" != "" ]; then
            label="$label · Think $reasoning"
        else
            label="Think $reasoning"
        fi
    fi

    if [ "$permission" != "" ]; then
        if [ "$label" != "" ]; then
            label="$label · $permission"
        else
            label="$permission"
        fi
    fi

    if [ "$label" != "" ]; then
        printf " %s·%s %s%s" "$c_sep" "$R" "$c_dim" "$label"
    fi
}

context_segment() {
    local payload="$1"
    local last_tokens context_window pct color tokens_label window_label

    last_tokens=$(jq_value "$payload" '.info.last_token_usage.total_tokens')
    context_window=$(jq_value "$payload" '.info.model_context_window')
    pct=$(calc_percent "$last_tokens" "$context_window")

    tokens_label=$(format_tokens "$last_tokens")
    window_label=$(format_tokens "$context_window")
    color=$(color_for_percent "$pct")

    if [ "$pct" = "" ]; then
        printf "%s--/-- %s--%%%s" "$c_dim" "$B" "$R"
    else
        printf "%s%s/%s %s%s%%%s" "$c_dim" "$tokens_label" "$window_label" "$color" "$B$pct" "$R"
    fi
}

persist_primary_state() {
    local pct="$1"
    local tmp
    tmp="${PULSE_STATE_FILE}.tmp.$$"
    (printf '{"primary":%d}\n' "$pct" > "$tmp" && mv -f "$tmp" "$PULSE_STATE_FILE") 2>/dev/null || true
}

dampen_primary_percent() {
    local pct="$1"
    local prev

    prev=0
    if [ -f "$PULSE_STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
        prev=$(jq -r '.primary // 0' "$PULSE_STATE_FILE" 2>/dev/null)
        prev=$(parse_utilization "$prev")
    fi

    if [ "$prev" -gt 0 ] 2>/dev/null && [ $((pct - prev)) -gt 30 ] 2>/dev/null; then
        pct="$prev"
    fi

    persist_primary_state "$pct"
    printf "%d" "$pct"
}

primary_rate_segment() {
    local payload="$1"
    local pct reset window label color

    pct=$(parse_utilization "$(jq_value "$payload" '.rate_limits.primary.used_percent')")
    pct=$(dampen_primary_percent "$pct")
    reset=$(jq_value "$payload" '.rate_limits.primary.resets_at')
    window=$(jq_value "$payload" '.rate_limits.primary.window_minutes')
    label=$(format_window_label "$reset" "$window")
    color=$(primary_color_for_percent "$pct")

    printf "%s%s %s%s%%%s %s" "$c_dim" "$label" "$color" "$B$pct" "$R" "$(bar "$pct")"
}

weekly_rate_segment() {
    local payload="$1"
    local pct reset window label color suffix

    pct=$(parse_utilization "$(jq_value "$payload" '.rate_limits.secondary.used_percent')")
    reset=$(jq_value "$payload" '.rate_limits.secondary.resets_at')
    window=$(jq_value "$payload" '.rate_limits.secondary.window_minutes')
    label=$(format_window_label "$reset" "$window")
    color=$(color_for_percent "$pct")
    suffix=$(weekly_reset_suffix "$reset")

    printf "%s%s %s%s%%%s%s%s%s" "$c_dim" "$label" "$color" "$B$pct" "$R" "$c_dim" "$suffix" "$R"
}

render_line() {
    local payload model

    if ! find_latest_thread; then
        printf "%s● %sCodex%s%s%sno session%s" "$c_white" "$B" "$R" "$SEP" "$c_dim" "$R"
        return
    fi

    model="$MODEL"
    payload=$(latest_payload || true)

    if [ "$payload" = "" ]; then
        printf "%s● %s%s%s%s%sno token event%s" "$c_white" "$B" "$model" "$R" "$SEP" "$c_dim" "$R"
        return
    fi

    printf "%s● %s%s%s" "$c_white" "$B" "$model" "$R"
    mode_segment
    printf "%s" "$SEP"
    context_segment "$payload"
    printf "%s" "$SEP"
    primary_rate_segment "$payload"
    printf "%s" "$SEP"
    weekly_rate_segment "$payload"
}

check_status() {
    local version login payload

    version="codex unavailable"
    login="login unknown"
    if command -v codex >/dev/null 2>&1; then
        version=$(codex --version 2>&1 | grep -v '^WARNING:' | tail -n 1)
        login=$(codex login status 2>&1 | grep -v '^WARNING:' | tail -n 1)
    fi

    printf "%s● %sCodex Pulse%s%s%s%s%s\n" "$c_white" "$B" "$R" "$SEP" "$c_dim" "$version" "$R"
    printf "%sCodex home:%s %s\n" "$c_dim" "$R" "$CODEX_HOME"
    printf "%sLogin:%s %s\n" "$c_dim" "$R" "$login"

    if command -v jq >/dev/null 2>&1; then
        printf "%sjq:%s ok\n" "$c_dim" "$R"
    else
        printf "%sjq:%s missing\n" "$c_dim" "$R"
    fi

    if command -v sqlite3 >/dev/null 2>&1; then
        printf "%ssqlite3:%s ok\n" "$c_dim" "$R"
    else
        printf "%ssqlite3:%s missing\n" "$c_dim" "$R"
    fi

    if find_latest_thread; then
        printf "%sSession:%s %s\n" "$c_dim" "$R" "$ROLLOUT_PATH"
        payload=$(latest_payload || true)
        if [ "$payload" != "" ]; then
            printf "%sData:%s token_count ready\n" "$c_dim" "$R"
            render_line
            printf "\n"
        else
            printf "%sData:%s no token_count event found in the last %s lines\n" "$c_dim" "$R" "$TAIL_LINES"
        fi
    else
        printf "%sSession:%s none found\n" "$c_dim" "$R"
    fi
}

watch_loop() {
    trap 'printf "\n"; exit 0' INT TERM
    while true; do
        printf "\r\033[2K"
        render_line
        sleep "$INTERVAL"
    done
}

case "$MODE" in
    check)
        check_status
        ;;
    watch)
        watch_loop
        ;;
    *)
        render_line
        printf "\n"
        ;;
esac
