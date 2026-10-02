#!/bin/sh
# Feeds sample JSON inputs to the status line and checks its output.
# Usage: tests/statusline.sh   (from the repo root)

script="$(dirname "$0")/../claude/statusline-command.sh"
now=$(date -u +%s)
fails=0

# check <name> <json> <expected substring>...
check() {
    name=$1; json=$2; shift 2
    out=$(printf '%s' "$json" | sh "$script" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    ok=1
    for want in "$@"; do
        case "$out" in
            *"$want"*) ;;
            *) printf 'FAIL %s: missing "%s"\n--- output:\n%s\n' "$name" "$want" "$out"; ok=0 ;;
        esac
    done
    if [ "$ok" = 1 ]; then printf 'ok   %s\n' "$name"; else fails=$((fails + 1)); fi
}

check "full input" \
    '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"context_window":{"used_percentage":20,"context_window_size":200000,"total_input_tokens":40000},"cost":{"total_duration_ms":720000},"rate_limits":{"five_hour":{"used_percentage":18,"resets_at":'$((now + 14400))'},"seven_day":{"used_percentage":71,"resets_at":'$((now + 216000))'}}}' \
    "Context: 20% (~160000 tokens left)" "Session: 12m" "| /tmp" \
    "Quota: 18% (" "Weekly: 71% (2d" "| Opus 5.5 · high"

check "empty input" '' "Context: 0%" "Quota: unavailable"
check "invalid json" 'not json' "Context: 0%" "Quota: unavailable"
check "no rate limits" '{"cwd":"/tmp","context_window":{"used_percentage":5,"context_window_size":1000000}}' \
    "~950000 tokens left" "Quota: unavailable"
check "empty model name" '{"cwd":"/tmp","model":{"display_name":""}}' "| /tmp"
check "path with spaces" '{"workspace":{"current_dir":"/tmp/a b"},"model":{"display_name":"Sonnet"}}' \
    "| /tmp/a b" "| Sonnet"
check "over 100%" '{"rate_limits":{"five_hour":{"used_percentage":130,"resets_at":0}}}' "Quota: 100%"

[ "$fails" = 0 ] || { echo "$fails check(s) failed"; exit 1; }
