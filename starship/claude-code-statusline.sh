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

# Fable 5 usage is metered against its own weekly bucket, but the payload's
# rate_limits only ever carries five_hour/seven_day (checked against the
# 2.1.233 payload builder). The bucket is only served by GET /api/oauth/usage,
# as a limits[] entry of the form
#   {"kind":"weekly_scoped",...,"percent":34,"resets_at":"2026-08-19T22:00:00+00:00",
#    "scope":{"model":{"display_name":"Fable"},...},...}
# so fetch it ourselves — cached on disk, and only when Fable is the active
# model (the bar is hidden otherwise, so non-Fable renders never pay for it).
refresh_usage_cache() {
    creds="$HOME/.claude/.credentials.json"
    [ -r "$creds" ] || return 1
    token=$(
        grep -oE '"accessToken"[[:space:]]*:[[:space:]]*"[^"]*"' "$creds" |
            head -n 1 |
            sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
    )
    [ -n "$token" ] || return 1
    (
        umask 077
        mkdir -p "$(dirname "$usage_cache")" || exit 1
        # Claude Code can kill a render mid-fetch, orphaning its tmp file.
        find "$(dirname "$usage_cache")" -name "$(basename "$usage_cache").tmp.*" \
            -mmin +10 -delete 2>/dev/null || true
        tmp="$usage_cache.tmp.$$"
        # -K - feeds the Authorization header via stdin so the token never
        # appears in the process list. On failure the old cache is kept.
        if printf 'header = "Authorization: Bearer %s"\n' "$token" |
            curl -sf -m 4 -K - \
                -H 'anthropic-beta: oauth-2025-04-20' \
                https://api.anthropic.com/api/oauth/usage >"$tmp" 2>/dev/null; then
            mv -f "$tmp" "$usage_cache"
        else
            rm -f "$tmp"
            exit 1
        fi
    )
}

model_id=$(json_string id) # first "id" in the payload is model.id
fable_pct=
fable_reset=
case "$model_id $model" in
*[Ff]able*)
    usage_cache=${CLAUDE_CODE_USAGE_CACHE:-}
    if [ -n "$usage_cache" ]; then
        : # explicit override (tests/fixtures): use the file as-is, never refresh
    else
        usage_cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline/oauth-usage.json"
        # A minute-old reading is fine for a usage gauge. Refresh in the
        # background so renders never wait on the network once a cache
        # exists; only the very first render blocks (at most 4s).
        if [ ! -f "$usage_cache" ]; then
            refresh_usage_cache || true
        elif ! find "$usage_cache" -mmin -1 2>/dev/null | grep -q . &&
            ! find "$(dirname "$usage_cache")" \
                -name "$(basename "$usage_cache").tmp.*" -mmin -1 2>/dev/null |
                grep -q .; then
            # Stale cache and no recent .tmp (i.e. no fetch already in
            # flight from another render): refresh in the background.
            refresh_usage_cache >/dev/null 2>&1 &
        fi
    fi
    if [ -r "$usage_cache" ]; then
        # Split limits[] entries onto their own lines so the percent below
        # can't be read from a neighbouring (e.g. Opus/Sonnet-scoped) entry.
        fable_entry=$(
            tr -d '\n' <"$usage_cache" |
                sed 's/{"kind"/\n{"kind"/g' |
                grep '"weekly_scoped"' |
                grep -i '"display_name"[[:space:]]*:[[:space:]]*"fable' |
                head -n 1
        )
        fable_pct=$(extract_number "$fable_entry" percent)
        fable_reset_iso=$(
            printf '%s\n' "$fable_entry" |
                grep -oE '"resets_at"[[:space:]]*:[[:space:]]*"[^"]*"' |
                head -n 1 |
                sed -E 's/.*:[[:space:]]*"(.*)"$/\1/'
        )
        if [ -n "$fable_reset_iso" ]; then
            fable_reset=$(date -d "$fable_reset_iso" +%s 2>/dev/null || true)
        fi
    fi
    ;;
esac

if [ -n "$fable_pct" ]; then
    CLAUDE_CODE_FABLE_LIMIT="$(format_gauge "$fable_pct") $(format_percentage "$fable_pct")"
    if [ -n "$fable_reset" ]; then
        CLAUDE_CODE_FABLE_LIMIT="$CLAUDE_CODE_FABLE_LIMIT · $(format_remaining "$fable_reset")"
    fi
    export CLAUDE_CODE_FABLE_LIMIT
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
