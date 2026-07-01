#!/usr/bin/env sh
set -eu

# Use the starship.toml next to this script (it defines the claude-code
# profile) unless the caller already set one. Without this, starship would
# silently fall back to its built-in claude-code statusline whenever Claude
# Code is launched from a context that didn't export STARSHIP_CONFIG.
if [ -z "${STARSHIP_CONFIG:-}" ]; then
    STARSHIP_CONFIG="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/starship.toml"
    export STARSHIP_CONFIG
fi

input=$(cat)
json=$(printf '%s' "$input" | tr '\n' ' ')

# First occurrence wins. (A greedy sed over the whole payload would return the
# LAST match — e.g. the seven_day limit's used_percentage instead of the
# context window's.)
json_string() {
    key=$1
    printf '%s\n' "$json" |
        grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"' |
        head -n 1 |
        sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
}

json_number() {
    key=$1
    # null must also count as the first occurrence (returned as empty).
    # context_window.used_percentage is null before the first API call and
    # after /compact; skipping it would make the next numeric match win —
    # rate_limits.five_hour.used_percentage — and the context gauge would
    # show the 5-hour limit on every fresh session.
    val=$(
        printf '%s\n' "$json" |
            grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*(-?[0-9]+([.][0-9]+)?|null)' |
            head -n 1 |
            sed -E 's/.*:[[:space:]]*//'
    )
    [ "$val" = "null" ] || printf '%s' "$val"
}

format_tokens() {
    awk -v n="${1:-0}" 'BEGIN {
        n += 0
        if (n >= 1000000) {
            m = n / 1000000
            if (m == int(m)) {
                printf "%dM", m
            } else {
                printf "%.1fM", m
            }
        } else if (n >= 1000) {
            k = n / 1000
            if (k == int(k)) {
                printf "%dk", k
            } else {
                printf "%.1fk", k
            }
        } else {
            printf "%d", n
        }
    }'
}

format_percentage() {
    awk -v p="${1:-0}" 'BEGIN {
        p += 0
        if (p == int(p)) {
            printf "%d%%", p
        } else {
            printf "%.1f%%", p
        }
    }'
}

format_gauge() {
    awk -v p="${1:-0}" 'BEGIN {
        width = 10
        p += 0
        if (p < 0) p = 0
        if (p > 100) p = 100

        used = p * width / 100
        full = int(used)
        partial = (used > full && full < width) ? 1 : 0
        empty = width - full - partial

        for (i = 0; i < full; i++) printf "█"
        if (partial) printf "▒"
        for (i = 0; i < empty; i++) printf "░"
    }'
}

format_remaining() {
    awk -v resets="${1:-0}" -v now="$(date +%s)" 'BEGIN {
        secs = resets - now
        if (secs <= 0) { printf "now"; exit }
        days = int(secs / 86400)
        hours = int((secs % 86400) / 3600)
        mins = int((secs % 3600) / 60)
        if (days > 0)        printf "%dd %dh", days, hours
        else if (hours > 0)  printf "%dh %dm", hours, mins
        else                 printf "%dm", mins
    }'
}

model=$(json_string display_name)
effort=$(
    printf '%s\n' "$json" |
        sed -nE 's/.*"effort"[[:space:]]*:[[:space:]]*\{[^}]*"level"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' |
        head -n 1
)
used_percentage=$(json_number used_percentage)
context_size=$(json_number context_window_size)
current_input=$(json_number input_tokens)
cache_creation=$(json_number cache_creation_input_tokens)
cache_read=$(json_number cache_read_input_tokens)
total_input=$(json_number total_input_tokens)
total_output=$(json_number total_output_tokens)

current_input=${current_input:-0}
cache_creation=${cache_creation:-0}
cache_read=${cache_read:-0}
context_size=${context_size:-0}
total_input=${total_input:-0}
total_output=${total_output:-0}

context_used=$(
    awk -v input="$current_input" -v created="$cache_creation" -v read="$cache_read" \
        'BEGIN { printf "%.0f", input + created + read }'
)

# Since Claude Code 2.1.132, context_window.total_input_tokens is exactly
# input + cache_creation + cache_read of the most recent API response — a
# documented equivalent of the sum above when current_usage is missing.
if [ "$context_used" = "0" ] && [ "$total_input" != "0" ]; then
    context_used=$total_input
fi

if [ "$context_used" = "0" ] && [ -n "${used_percentage:-}" ] && [ "$context_size" != "0" ]; then
    context_used=$(
        awk -v percentage="$used_percentage" -v total="$context_size" \
            'BEGIN { printf "%.0f", total * percentage / 100 }'
    )
fi

if [ -z "${used_percentage:-}" ]; then
    used_percentage=$(
        awk -v used="$context_used" -v total="$context_size" \
            'BEGIN { if (total > 0) printf "%.1f", used * 100 / total; else print 0 }'
    )
fi

model_effort=$model
if [ -n "$effort" ]; then
    model_effort="$model ($effort)"
fi

extract_number() {
    obj=$1
    key=$2
    printf '%s\n' "$obj" |
        grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*-?[0-9]+([.][0-9]+)?' |
        head -n 1 |
        sed -E 's/.*:[[:space:]]*//'
}

five_hour_obj=$(printf '%s\n' "$json" | sed -nE 's/.*"five_hour"[[:space:]]*:[[:space:]]*\{([^}]*)\}.*/\1/p' | head -n 1)
seven_day_obj=$(printf '%s\n' "$json" | sed -nE 's/.*"seven_day"[[:space:]]*:[[:space:]]*\{([^}]*)\}.*/\1/p' | head -n 1)

five_hour_pct=$(extract_number "$five_hour_obj" used_percentage)
five_hour_reset=$(extract_number "$five_hour_obj" resets_at)
seven_day_pct=$(extract_number "$seven_day_obj" used_percentage)
seven_day_reset=$(extract_number "$seven_day_obj" resets_at)

# Session stats: cost (when known to be non-zero) plus lines added/removed.
# The old "token usage" pair (total_input/total_output) stopped meaning
# session totals in Claude Code 2.1.132 — those fields now mirror the
# current context window, which the context segment already shows.
total_cost=$(json_number total_cost_usd)
lines_added=$(json_number total_lines_added)
lines_removed=$(json_number total_lines_removed)
lines_added=${lines_added:-0}
lines_removed=${lines_removed:-0}

session_stats="+${lines_added}/-${lines_removed}"
cost_fmt=$(awk -v c="${total_cost:-0}" 'BEGIN { if (c >= 0.005) printf "$%.2f", c }')
if [ -n "$cost_fmt" ]; then
    session_stats="$cost_fmt · $session_stats"
fi

CLAUDE_CODE_MODEL_EFFORT="$model_effort"
CLAUDE_CODE_CONTEXT_USAGE="$(format_gauge "$used_percentage") $(format_tokens "$context_used")/$(format_tokens "$context_size") $(format_percentage "$used_percentage")"
CLAUDE_CODE_SESSION_STATS="$session_stats"

export CLAUDE_CODE_MODEL_EFFORT CLAUDE_CODE_CONTEXT_USAGE CLAUDE_CODE_SESSION_STATS

if [ -n "$five_hour_pct" ] && [ -n "$five_hour_reset" ]; then
    CLAUDE_CODE_FIVE_HOUR_LIMIT="$(format_gauge "$five_hour_pct") $(format_percentage "$five_hour_pct") · $(format_remaining "$five_hour_reset")"
    export CLAUDE_CODE_FIVE_HOUR_LIMIT
fi

if [ -n "$seven_day_pct" ] && [ -n "$seven_day_reset" ]; then
    CLAUDE_CODE_SEVEN_DAY_LIMIT="$(format_gauge "$seven_day_pct") $(format_percentage "$seven_day_pct") · $(format_remaining "$seven_day_reset")"
    export CLAUDE_CODE_SEVEN_DAY_LIMIT
fi

# Starship deserializes the payload strictly (null percentages fail with
# "invalid type: null, expected f32"), so zero out every nullable
# context_window field, not just current_usage.
starship_json=$(
    printf '%s' "$json" |
        sed -E '
            s/"current_usage"[[:space:]]*:[[:space:]]*null/"current_usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}/g
            s/"used_percentage"[[:space:]]*:[[:space:]]*null/"used_percentage":0/g
            s/"remaining_percentage"[[:space:]]*:[[:space:]]*null/"remaining_percentage":100/g
        '
)

# Without starship (fresh machine before bootstrap), degrade to plain text
# instead of dying under set -e and leaving the statusline blank.
if ! command -v starship >/dev/null 2>&1; then
    printf '%s | %s | %s' \
        "$CLAUDE_CODE_MODEL_EFFORT" "$CLAUDE_CODE_CONTEXT_USAGE" "$CLAUDE_CODE_SESSION_STATS"
    exit 0
fi

printf '%s' "$starship_json" | starship statusline claude-code
