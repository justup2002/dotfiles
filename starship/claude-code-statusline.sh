#!/usr/bin/env sh
set -eu

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
    printf '%s\n' "$json" |
        grep -oE '"'"$key"'"[[:space:]]*:[[:space:]]*-?[0-9]+([.][0-9]+)?' |
        head -n 1 |
        sed -E 's/.*:[[:space:]]*//'
}

format_tokens() {
    awk -v n="${1:-0}" 'BEGIN {
        n += 0
        if (n >= 1000) {
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

CLAUDE_CODE_MODEL_EFFORT="$model_effort"
CLAUDE_CODE_CONTEXT_USAGE="$(format_gauge "$used_percentage") $(format_tokens "$context_used")/$(format_tokens "$context_size") $(format_percentage "$used_percentage")"
CLAUDE_CODE_TOKEN_USAGE="$(format_tokens "$total_input") $(format_tokens "$total_output")"

export CLAUDE_CODE_MODEL_EFFORT CLAUDE_CODE_CONTEXT_USAGE CLAUDE_CODE_TOKEN_USAGE

if [ -n "$five_hour_pct" ] && [ -n "$five_hour_reset" ]; then
    CLAUDE_CODE_FIVE_HOUR_LIMIT="$(format_gauge "$five_hour_pct") $(format_percentage "$five_hour_pct") · $(format_remaining "$five_hour_reset")"
    export CLAUDE_CODE_FIVE_HOUR_LIMIT
fi

if [ -n "$seven_day_pct" ] && [ -n "$seven_day_reset" ]; then
    CLAUDE_CODE_SEVEN_DAY_LIMIT="$(format_gauge "$seven_day_pct") $(format_percentage "$seven_day_pct") · $(format_remaining "$seven_day_reset")"
    export CLAUDE_CODE_SEVEN_DAY_LIMIT
fi

starship_json=$(
    printf '%s' "$json" |
        sed -E 's/"current_usage"[[:space:]]*:[[:space:]]*null/"current_usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}/g'
)

printf '%s' "$starship_json" | starship statusline claude-code
