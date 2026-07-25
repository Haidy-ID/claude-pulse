#!/bin/bash
# claude-pulse-lastdone — Stop hook feeding the "Last done" line of claude-pulse
# https://github.com/Haidy-ID/claude-pulse
#
# Reads the Stop hook JSON on stdin, distills a one-sentence summary of what
# Claude just finished, and stores it per session. claude-pulse.sh renders it.
#
# Storage: ~/.claude/pulse-lastdone/<session_id>
# Never blocks: always exits 0, whatever happens.

input=$(cat)
[ -z "$input" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

STATE_DIR="${CLAUDE_PULSE_LASTDONE_DIR:-$HOME/.claude/pulse-lastdone}"
MAX_LEN="${CLAUDE_PULSE_LASTDONE_MAXLEN:-220}"
MIN_LEN="${CLAUDE_PULSE_LASTDONE_MINLEN:-55}"
KEEP_FILES=60

session_id=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)
message=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)

# No session to key on, or nothing said: leave the previous value alone.
[ -z "$session_id" ] || [ "$session_id" = "null" ] && exit 0
[ -z "$message" ] || [ "$message" = "null" ] && exit 0

# Guard against path traversal via a hostile session_id.
case "$session_id" in
    *[!a-zA-Z0-9._-]*) exit 0 ;;
esac

# === DISTILL ===
# Walk the final assistant message and keep the first line that reads like a
# statement of what was done: no code fences, headings, bullets, tables,
# quotes or questions. Markdown decoration is stripped before the test.
summary=$(printf '%s\n' "$message" | awk -v maxlen="$MAX_LEN" -v minlen="$MIN_LEN" '
    function clean(s) {
        gsub(/!\[[^]]*\]\([^)]*\)/, "", s)            # images
        gsub(/\[([^]]*)\]\([^)]*\)/, "\\1", s)        # links -> label
        gsub(/<[^>]*>/, "", s)                        # stray html
        gsub(/\*\*|__|~~|`/, "", s)                   # bold / strike / code marks
        gsub(/\*/, "", s)                             # italic marks
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        gsub(/[[:space:]]+/, " ", s)
        return s
    }
    # Leading sentences, up to minlen characters. Sentence end = . ! ? followed
    # by a space or the line end, which leaves version numbers such as 2.1.220
    # intact. One punchy opener ("Shipped.") says nothing on its own, so keep
    # taking sentences until there is enough substance to be worth a row.
    # A question ends the run: everything before it is still worth showing.
    function lead(s, minlen,   acc, part) {
        acc = ""
        while (s != "") {
            if (match(s, /[.!?]( |$)/)) {
                part = substr(s, 1, RSTART)
                s = substr(s, RSTART + 1)
            } else {
                part = s
                s = ""
            }
            if (part ~ /\?$/) break
            acc = (acc == "" ? part : acc " " part)
            sub(/^ +/, "", s)
            if (length(acc) >= minlen) break
        }
        return acc
    }
    function is_bullet(s) {
        if (s ~ /^([-*+]|[0-9]+[.)])[[:space:]]/) return 1
        return index(s, "\342\200\242") == 1          # UTF-8 bullet
    }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
        line = clean($0)
        if (line == "")        next   # blank
        if (line ~ /^#/)       next   # heading
        if (is_bullet(line))   next   # list item
        if (line ~ /^[>|]/)    next   # quote / table
        if (line ~ /^-{3,}$/)  next   # rule
        line = lead(line, minlen)
        if (line == "")        next   # the line was nothing but a question
        if (length(line) < 12) next   # too thin to mean anything
        if (length(line) > maxlen) line = substr(line, 1, maxlen - 1) "…"
        print line
        exit
    }
')

# Nothing quotable this turn (pure question, pure code, pure list):
# keep whatever was there rather than blanking the line.
[ -z "$summary" ] && exit 0

# Sentence case + trailing period, mirroring pi-tasks' withPeriod(sentenceCase()).
summary=$(printf '%s' "$summary" | awk '
    {
        # Only touch an ASCII initial; an accented one is left as typed.
        if ($0 ~ /^[a-z]/) $0 = toupper(substr($0, 1, 1)) substr($0, 2)
        if ($0 !~ /[.!?…]$/) $0 = $0 "."
        print
    }
')

# === PERSIST (atomic) ===
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
tmp="$STATE_DIR/.$session_id.tmp.$$"
printf '%s\n' "$summary" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_DIR/$session_id" 2>/dev/null
rm -f "$tmp" 2>/dev/null

# === PRUNE ===
# Keep the newest KEEP_FILES entries so the directory cannot grow without bound.
ls -1t "$STATE_DIR" 2>/dev/null | tail -n +$((KEEP_FILES + 1)) | while read -r stale; do
    [ -n "$stale" ] && rm -f "$STATE_DIR/$stale" 2>/dev/null
done

exit 0
