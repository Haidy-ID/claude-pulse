#!/bin/bash
# claude-pulse — Status line for Claude Code
# https://github.com/lunndev/claude-pulse
#
# Layout: ● Model │ used·total XX% │ Xh XX% [████░░░░] │ Xj XX% Day

input=$(cat)

if [ -z "$input" ]; then
    printf "Loading..."
    exit 0
fi

# === TRUE COLOR PALETTE (24-bit RGB) ===
R="\033[0m"
B="\033[1m"

c_model="\033[38;2;255;255;255m"   # white
c_warn="\033[38;2;251;191;36m"     # amber
c_bad="\033[38;2;248;113;113m"     # coral
c_crit="\033[38;2;220;60;60m"      # deep red (pulse)
c_sep="\033[38;2;75;85;99m"        # cool gray
c_dim="\033[38;2;107;114;128m"     # muted gray
c_white="\033[38;2;255;255;255m"

SEP=" ${c_sep}│${R} "

now_s=$(date +%s)

# === HELPERS ===
safe_int() {
    local val="${1:-0}"
    val="${val//[[:space:]]/}"
    case "$val" in
        ''|null|NULL) echo 0 ;;
        *[!0-9.-]*) echo 0 ;;
        *) printf "%.0f" "$val" 2>/dev/null || echo 0 ;;
    esac
}

gauge_color() {
    local pct=$1
    if [ "$pct" -lt 50 ] 2>/dev/null; then echo "$c_white"
    elif [ "$pct" -lt 80 ] 2>/dev/null; then echo "$c_warn"
    else echo "$c_bad"
    fi
}

fr_day() {
    local epoch=$1 dow
    if [[ "$OSTYPE" == "darwin"* ]]; then
        dow=$(date -j -f "%s" "$epoch" +%u 2>/dev/null)
    else
        dow=$(date -d "@$epoch" +%u 2>/dev/null)
    fi
    case "$dow" in
        1) echo "Lun." ;; 2) echo "Mar." ;; 3) echo "Mer." ;;
        4) echo "Jeu." ;; 5) echo "Ven." ;; 6) echo "Sam." ;; 7) echo "Dim." ;;
        *) echo "?" ;;
    esac
}

format_time() {
    local epoch=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -f "%s" "$epoch" +%Hh%M 2>/dev/null
    else
        date -d "@$epoch" +%Hh%M 2>/dev/null
    fi
}

parse_utilization() {
    local raw="$1"
    raw="${raw//[[:space:]]/}"
    [ -z "$raw" ] || [ "$raw" = "null" ] && raw=0
    awk "BEGIN {
        v = $raw + 0
        if (v > 100) printf \"100\"
        else if (v < 0) printf \"0\"
        else printf \"%d\", v
    }"
}

format_tokens() {
    local t=$1
    if [ "$t" -ge 1000000 ] 2>/dev/null; then
        awk "BEGIN {v=$t/1000000; if (v==int(v)) printf \"%dM\",v; else printf \"%.1fM\",v}"
    elif [ "$t" -ge 1000 ] 2>/dev/null; then
        awk "BEGIN {printf \"%dk\", $t/1000}"
    else
        printf "%d" "$t"
    fi
}

parse_epoch() {
    local raw="$1"
    [ -z "$raw" ] || [ "$raw" = "null" ] && return 1
    local clean=$(echo "$raw" | sed 's/\.[0-9]*//; s/+00:00$//; s/Z$//')
    if [[ "$OSTYPE" == "darwin"* ]]; then
        TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null
    else
        date -u -d "${clean}Z" +%s 2>/dev/null
    fi
}

# === PARSE JSON ===
json_data=$(echo "$input" | jq -r '
    [
        (.context_window.used_percentage // -1),
        (.context_window.remaining_percentage // -1),
        (.context_window.context_window_size // 200000),
        (.model.display_name // .model.id // "Unknown")
    ] | @tsv
' 2>/dev/null)

if [ -z "$json_data" ]; then
    printf "Status unavailable"
    exit 0
fi

IFS=$'\t' read -r ctx_pct_raw ctx_remaining_raw ctx_size_raw model_name <<< "$json_data"

ctx_pct=$(safe_int "$ctx_pct_raw")
[ "$ctx_pct" -lt 0 ] 2>/dev/null && ctx_pct=0
[ "$ctx_pct" -gt 100 ] 2>/dev/null && ctx_pct=100
ctx_size=$(safe_int "$ctx_size_raw")
[ "$ctx_size" -le 0 ] 2>/dev/null && ctx_size=200000

used_tokens=$((ctx_size * ctx_pct / 100))
ctx_display="$(format_tokens "$used_tokens")·$(format_tokens "$ctx_size")"
ctx_color=$(gauge_color "$ctx_pct")

# === MODEL NAME (compact) ===
[ -z "$model_name" ] || [ "$model_name" = "null" ] && model_name="?"
model_short="${model_name#Claude }"
model_short="${model_short%% *}"

# === STATE (spike damping) ===
STATE_FILE="$HOME/.claude/pulse-state.json"
prev_plan=0
if [ -f "$STATE_FILE" ]; then
    prev_plan=$(safe_int "$(jq -r '.pp' "$STATE_FILE" 2>/dev/null)")
fi

# === CLAUDE VERSION (cached 1h) ===
VERSION_CACHE="$HOME/.claude/version-cache.txt"
claude_version="unknown"
if [ -f "$VERSION_CACHE" ]; then
    if stat --version >/dev/null 2>&1; then
        vt=$(stat -c %Y "$VERSION_CACHE" 2>/dev/null)
    else
        vt=$(stat -f %m "$VERSION_CACHE" 2>/dev/null)
    fi
    vt=${vt:-0}
    [ $(( now_s - vt )) -lt 3600 ] && claude_version=$(cat "$VERSION_CACHE")
fi
if [ "$claude_version" = "unknown" ]; then
    if command -v timeout >/dev/null 2>&1; then
        claude_version=$(timeout 1 claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    else
        claude_version=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    [ -n "$claude_version" ] && echo "$claude_version" > "$VERSION_CACHE" || claude_version="unknown"
fi

# === PLAN USAGE (API) ===
CACHE_FILE="$HOME/.claude/usage-cache.json"
CACHE_TTL=60

get_real_usage() {
    local cache_age=9999
    if [ -f "$CACHE_FILE" ]; then
        local cache_time
        if stat --version >/dev/null 2>&1; then
            cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null)
        else
            cache_time=$(stat -f %m "$CACHE_FILE" 2>/dev/null)
        fi
        cache_time=${cache_time:-0}
        cache_age=$(( now_s - cache_time ))
    fi

    if [ "$cache_age" -lt "$CACHE_TTL" ] && [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
        return
    fi

    local creds_json=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        creds_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    else
        local creds_file="$HOME/.claude/.credentials.json"
        [ -f "$creds_file" ] && creds_json=$(cat "$creds_file")
    fi

    if [ -z "$creds_json" ]; then
        echo '{"five_hour":{"utilization":0,"resets_at":""},"seven_day":{"utilization":0,"resets_at":""}}'
        return
    fi

    local token
    token=$(echo "$creds_json" | jq -r '.claudeAiOauth.accessToken // ""' 2>/dev/null)
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo '{"five_hour":{"utilization":0,"resets_at":""},"seven_day":{"utilization":0,"resets_at":""}}'
        return
    fi

    local response
    response=$(curl -s --max-time 3 \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "User-Agent: claude-code/$claude_version" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

    if echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
        local tmp="${CACHE_FILE}.tmp.$$"
        echo "$response" > "$tmp" && mv -f "$tmp" "$CACHE_FILE"
        echo "$response"
    elif [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo '{"five_hour":{"utilization":0,"resets_at":""},"seven_day":{"utilization":0,"resets_at":""}}'
    fi
}

usage_data=$(get_real_usage)

# === 5h GAUGE ===
plan_pct=$(parse_utilization "$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' 2>/dev/null)")
[ -z "$plan_pct" ] && plan_pct=0
[ "$plan_pct" -lt 0 ] 2>/dev/null && plan_pct=0
[ "$plan_pct" -gt 100 ] 2>/dev/null && plan_pct=100

# Spike damping
if [ "$prev_plan" -gt 0 ] 2>/dev/null; then
    [ $((plan_pct - prev_plan)) -gt 30 ] 2>/dev/null && plan_pct=$prev_plan
fi

# 5h label (time remaining)
label_5h="5h"
reset_epoch=$(parse_epoch "$(echo "$usage_data" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)")
if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt 0 ] 2>/dev/null; then
    diff_secs=$((reset_epoch - now_s))
    if [ "$diff_secs" -gt 0 ]; then
        label_5h="$((diff_secs / 3600))h$(printf '%02d' $(( (diff_secs % 3600) / 60 )))"
    else
        label_5h="0h00"
    fi
fi

# 5h color
pulse_frame=$(( now_s % 2 ))
if [ "$plan_pct" -lt 50 ] 2>/dev/null; then plan_color="$c_white"
elif [ "$plan_pct" -lt 80 ] 2>/dev/null; then plan_color="$c_warn"
else
    if [ "$pulse_frame" -eq 0 ]; then plan_color="$c_bad"; else plan_color="$c_crit"; fi
fi

# === 7d GAUGE ===
week_pct=$(parse_utilization "$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' 2>/dev/null)")
[ -z "$week_pct" ] && week_pct=0
[ "$week_pct" -lt 0 ] 2>/dev/null && week_pct=0
[ "$week_pct" -gt 100 ] 2>/dev/null && week_pct=100
week_color=$(gauge_color "$week_pct")

# 7d label + reset day
label_7d="7j"
label_7d_reset=""
reset_epoch=$(parse_epoch "$(echo "$usage_data" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)")
if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt 0 ] 2>/dev/null; then
    diff_secs=$((reset_epoch - now_s))
    if [ "$diff_secs" -gt 0 ]; then
        label_7d="$((diff_secs / 86400))j"
    else
        label_7d="0j"
    fi
    reset_day=$(fr_day "$reset_epoch")
    if [ "$diff_secs" -lt 172800 ]; then
        label_7d_reset=" ${reset_day} $(format_time "$reset_epoch")"
    else
        label_7d_reset=" ${reset_day}"
    fi
fi

# === PERSIST STATE (atomic) ===
_tmp="${STATE_FILE}.tmp.$$"
printf '{"pp":%d}\n' "$plan_pct" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$STATE_FILE" 2>/dev/null

# === PROGRESS BAR ===
bar_length=8
filled=$((plan_pct * bar_length / 100))
[ "$filled" -gt "$bar_length" ] && filled=$bar_length
[ "$filled" -lt 0 ] 2>/dev/null && filled=0

progress_bar=""
for ((i=0; i<filled; i++)); do progress_bar+="${plan_color}█"; done
for ((i=filled; i<bar_length; i++)); do progress_bar+="${c_dim}░"; done
progress_bar+="${R}"

# === OUTPUT ===
printf "%b" "${c_model}● ${B}${model_short}${R}${SEP}${c_dim}${ctx_display} ${ctx_color}${B}${ctx_pct}%${R}${SEP}${c_dim}${label_5h} ${plan_color}${B}${plan_pct}%${R} ${progress_bar}${R}${SEP}${c_dim}${label_7d} ${week_color}${B}${week_pct}%${R}${label_7d_reset:+${c_dim}${label_7d_reset}}${R}"
