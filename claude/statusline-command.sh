#!/bin/sh
# Statusline Claude Code — lit les VRAIES valeurs exposées par le harness
# (mêmes données que /usage). Depuis Claude Code 2.x l'input JSON contient
# .rate_limits.{five_hour,seven_day}.{used_percentage,resets_at} : plus besoin
# d'estimer la conso via le delta de contexte. Aucun fichier d'état requis.

input=$(cat)
# entrée blanche (jq -e accepte le vide sans rien produire) ou invalide -> {}
case "$input" in *[![:space:]]*) ;; *) input='{}' ;; esac
echo "$input" | jq -e . >/dev/null 2>&1 || input='{}'

now=$(date -u +%s)

# ── extraction en un seul appel jq (tsv) ───────────────────────────────────
# Champs absents -> défaut ; -1 = pas de donnée de quota (plan sans limites).
# Chaînes vides -> "-" : la tabulation est un blanc IFS, deux tabs consécutifs
# fusionneraient et décaleraient les champs suivants.
IFS='	' read -r ctx_pct ctx_size ctx_used dur_ms \
    h5_pct h5_reset wk_pct wk_reset cwd model effort <<EOF
$(echo "$input" | jq -r '
  [ (.context_window.used_percentage      // 0),
    (.context_window.context_window_size  // 0),
    (.context_window.total_input_tokens   // ((.context_window.used_percentage // 0) * (.context_window.context_window_size // 0) / 100)),
    (.cost.total_duration_ms              // 0),
    (.rate_limits.five_hour.used_percentage // -1),
    (.rate_limits.five_hour.resets_at       // 0),
    (.rate_limits.seven_day.used_percentage // -1),
    (.rate_limits.seven_day.resets_at       // 0),
    (.workspace.current_dir // .cwd       // "-"),
    (.model.display_name                  // "-"),
    (.effort.level                        // "-")
  ] | map(. // 0 | (if type=="number" then (.*1|round) elif .=="" then "-" else . end)) | @tsv')
EOF
# défauts si l'extraction a échoué (jamais d'arithmétique sur du vide)
: "${ctx_pct:=0}" "${ctx_size:=0}" "${ctx_used:=0}" "${dur_ms:=0}"
: "${h5_pct:=-1}" "${h5_reset:=0}" "${wk_pct:=-1}" "${wk_reset:=0}"
: "${cwd:=-}" "${model:=-}" "${effort:=-}"

# Le script est lancé depuis le dossier de démarrage de la session : $PWD ne
# suit pas les cd de Claude, d'où le cwd fourni par le harness.
[ "$cwd" = - ] && cwd=$PWD
git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$cwd" in
    "$HOME"|"$HOME"/*) short_pwd="~${cwd#"$HOME"}" ;;
    *)                 short_pwd=$cwd ;;
esac

# ── helpers ────────────────────────────────────────────────────────────────
# Couleurs ANSI de base (16 couleurs + variantes claires 9x) : elles suivent
# le thème du terminal.
esc=$(printf '\033')
RED="$esc[31m"; ORANGE="$esc[33m"; GREEN="$esc[32m"; BLUE="$esc[94m"
MAGENTA="$esc[35m"; CYAN="$esc[36m"; GREY="$esc[90m"; BOLD="$esc[1m"
RESET="$esc[0m"
SEP="$GREY | $RESET"

color_pct() {
    if   [ "$1" -ge 80 ]; then printf '%s' "$RED"
    elif [ "$1" -ge 60 ]; then printf '%s' "$ORANGE"
    else                       printf '%s' "$GREEN"
    fi
}

label() { printf '%s%s:%s ' "$GREY" "$1" "$RESET"; }

format_duration() {
    s=$1
    [ "$s" -le 0 ] && printf "bientôt" && return
    h=$((s / 3600)); m=$(( (s % 3600) / 60 ))
    [ "$h" -gt 24 ] && printf "%dj%02dh" "$((h/24))" "$((h%24))" && return
    [ "$h" -gt 0  ] && printf "%dh%02dm" "$h" "$m" && return
    printf "%dm" "$m"
}

# Affiche un segment de quota "Label: X% (reset Y)" si la donnée existe.
quota_segment() {
    lbl=$1; pct=$2; reset_at=$3
    [ "$pct" -lt 0 ] && return          # pas de donnée -> on n'affiche rien
    [ "$pct" -gt 100 ] && pct=100
    label "$lbl"
    printf "%s%s%d%%%s" "$BOLD" "$(color_pct "$pct")" "$pct" "$RESET"
    if [ "$reset_at" -gt "$now" ]; then
        printf " %s(%s%s%s reset)%s" "$GREY" "$BLUE" "$(format_duration $((reset_at - now)))" "$GREY" "$RESET"
    fi
}

# ── ligne 1 : contexte + session + cwd/git ─────────────────────────────────
ctx_left=$((ctx_size - ctx_used)); [ "$ctx_left" -lt 0 ] && ctx_left=0
ctx_color=$(color_pct "$ctx_pct")
label "Context"
printf "%s%s%d%%%s %s(~%d tokens left)%s" \
    "$BOLD" "$ctx_color" "$ctx_pct" "$RESET" "$GREY" "$ctx_left" "$RESET"
if [ "$dur_ms" -gt 0 ]; then
    printf '%s' "$SEP"; label "Session"
    printf "%s%s%s" "$BLUE" "$(format_duration $((dur_ms / 1000)))" "$RESET"
fi
printf "%s%s%s%s" "$SEP" "$CYAN" "$short_pwd" "$RESET"
[ -n "$git_branch" ] && printf " %s->%s %s%s%s" "$GREY" "$RESET" "$MAGENTA" "$git_branch" "$RESET"
printf '\n'

# ── ligne 2 : quotas réels (5h glissant + hebdo) + modèle/effort ───────────
if [ "$h5_pct" -ge 0 ] || [ "$wk_pct" -ge 0 ]; then
    quota_segment "Quota" "$h5_pct" "$h5_reset"
    seg2=$(quota_segment "Weekly" "$wk_pct" "$wk_reset")
    [ -n "$seg2" ] && { [ "$h5_pct" -ge 0 ] && printf '%s' "$SEP"; printf '%s' "$seg2"; }
else
    printf "%sQuota: indisponible%s" "$ORANGE" "$RESET"
fi
if [ "$model" != - ]; then
    printf "%s%s%s%s%s" "$SEP" "$BOLD" "$BLUE" "$model" "$RESET"
    [ "$effort" != - ] && printf " %s·%s %s%s%s" "$GREY" "$RESET" "$MAGENTA" "$effort" "$RESET"
fi
