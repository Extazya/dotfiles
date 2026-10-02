# dotfiles

Dépôt git de configuration portable. Permet de réinstaller l'environnement
complet sur n'importe quelle machine avec `./install.sh`.

## Ce qui est tracké

```
dotfiles/
├── install.sh                  script d'installation (copie, pas symlinks)
├── .gitignore
├── vim/
│   └── .vimrc
├── zsh/
│   └── .zshrc
└── claude/
    ├── settings.json           config Claude Code (thème, permissions, statusline)
    └── statusline-command.sh   script de la barre custom (voir ci-dessous)
```

## Ce qui est exclu du git (.gitignore)

Fichiers sensibles ou trop volatils :
- `claude/.credentials.json`
- `claude/history.jsonl`, `claude/sessions/`, `claude/projects/`, `claude/cache/`, `claude/backups/`

## install.sh

Installe l'environnement complet sur une machine Debian/Ubuntu (testé sur un
conteneur `debian:trixie` vierge). Relançable sans risque : chaque étape saute
ce qui est déjà en place.

```sh
./install.sh                     # tout
./install.sh --dry-run           # afficher sans rien modifier
./install.sh --only zsh,claude   # seulement certaines étapes
```

Étapes, dans l'ordre :
1. `packages` : apt (via sudo, ou direct en root) — zsh vim git curl jq ripgrep
   fzf build-essential fontconfig ca-certificates ; seulement les manquants
2. `zsh` : clone oh-my-zsh, powerlevel10k, zsh-autosuggestions,
   zsh-syntax-highlighting (pas le script officiel d'oh-my-zsh, qui écrase
   `.zshrc`) + `zsh/.zshrc` → `~/.zshrc`. `~/.p10k.zsh` n'est pas dans le dépôt :
   l'assistant p10k se lance au premier zsh d'une nouvelle machine
3. `vim` : `vim/.vimrc` → `~/.vimrc`, vim-plug, PlugInstall
4. `gh` : dernière release GitHub CLI → `~/.local/bin/gh` (amd64/arm64)
5. `claude` : installeur officiel Claude Code si absent, statusline, et
   `claude/settings.json` **fusionné** dans `~/.claude/settings.json`
   (`jq -s '.[0] * .[1]'`) : le dépôt l'emporte sur les clés communes, les
   tableaux (permissions) sont remplacés, et les clés propres à la machine
   (ex. `autoMode` propre à un projet, volontairement hors dépôt) sont conservées
6. `fonts` : MesloLGS NF → `~/.local/share/fonts` (sauf si déjà dans `fc-list`)
7. `shell` : `chsh` vers zsh (mot de passe demandé ; avertit sans échouer)
8. `git` : demande nom/email si aucune identité globale — jamais dans le dépôt,
   elle dépend de la machine

Toute cible existante qui diffère est d'abord sauvegardée en `<cible>.bak`.

## Statusline Claude Code (statusline-command.sh)

Script sh (POSIX, pas bash) appelé par Claude Code à chaque refresh de la barre
(à chaque événement de session + toutes les 30 s via `refreshInterval`, pour que
les décomptes de reset avancent même au repos). Reçoit du JSON sur stdin
(via `statusLine.type = "command"`). Claude Code n'a pas de barre équivalente
intégrée : sans ce script, les quotas ne sont visibles que via `/usage`.

**Affiche 2 lignes :**

```
Context: 42% (~58000 tokens left) | Session: 12m | ~/projets/demo -> main
Quota: 18% (4h00m reset) | Weekly: 7% (2j14h reset) | Opus 5.5 · high
```

**Ce qu'il fait :**
Depuis Claude Code 2.x, le harness expose **les vraies valeurs de quota** dans
l'input JSON (mêmes données que `/usage`). Le script ne fait plus aucune
estimation — il lit directement :
- `context_window.used_percentage` / `context_window_size` / `total_input_tokens` → ligne 1
  (pas `current_usage` : c'est un objet, `null` avant le 1er appel et après `/compact`)
- `cost.total_duration_ms` → durée de session
- `workspace.current_dir` (repli `cwd`, puis `$PWD`) → dossier + branche git ;
  `$PWD` seul ne suit pas les `cd` de Claude dans la session
- `rate_limits.five_hour.{used_percentage, resets_at}` → quota glissant 5h
- `rate_limits.seven_day.{used_percentage, resets_at}` → quota hebdo
  (`resets_at` = epoch Unix en secondes ; reset affiché en durée humaine)
- `model.display_name` + `effort.level` → fin de ligne 2 (omis si absents)

Tout est extrait en **un seul appel jq** (tsv), avec défauts si un champ manque.
Si `rate_limits` est absent (ex. plan API sans limites), la ligne 2 affiche
`Quota: indisponible` au lieu de planter. Code couleur : vert < 60 %, orange
60–79 %, rouge ≥ 80 % (contexte et quotas, en gras). Libellés, séparateurs et
infos secondaires en gris ; durées (session, temps avant reset) et modèle en
bleu clair, dossier en cyan, branche
git et effort en magenta. Couleurs ANSI de base uniquement, pour suivre le
thème du terminal. Branche git affichée si le dossier courant est dans un repo.
Schéma complet de l'input : https://code.claude.com/docs/en/statusline

**Aucun fichier d'état** : plus de `usage_tracker.json`, `usage_config.json` ni
`session_start` (l'ancienne version cumulait des deltas de tokens estimés ; les
valeurs étant maintenant fournies par le harness, ce mécanisme — et ses bugs de
corruption du tracker — a été supprimé).

**Tester :**
```sh
echo '{"workspace":{"current_dir":"'"$HOME"'/dotfiles"},"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"context_window":{"used_percentage":20,"context_window_size":200000,"total_input_tokens":40000},"cost":{"total_duration_ms":720000},"rate_limits":{"five_hour":{"used_percentage":18,"resets_at":'"$(( $(date -u +%s)+14400 ))"'},"seven_day":{"used_percentage":7,"resets_at":'"$(( $(date -u +%s)+216000 ))"'}}}' \
  | sh ~/.claude/statusline-command.sh
```

## settings.json (Claude Code)

- Thème dark, modèle `opus`, effort `high` (aussi forcé pour `claude-opus-5-5` via `modelSettings`)
- Statusline : `command` → `sh ~/.claude/statusline-command.sh`, `refreshInterval: 30`
- Permissions : allow `Bash(*)`, `Read(*)`, `Edit(*)`, `Write(*)` — deny destructifs
  (rm -rf/-fr, force push y compris `-f` et option en fin de commande, reset --hard,
  dd, mkfs, et leurs variantes `sudo`). Le deny l'emporte sur les allow de
  `settings.local.json` (qui autorise par exemple `sudo dd *`).
- Hors dépôt : `autoMode` (contexte propre à un projet ou un client) reste uniquement
  dans `~/.claude/settings.json` local — préservé grâce à la fusion de `install.sh`.

## vim (.vimrc)

Plugins via vim-plug : NERDTree, fzf + fzf.vim, commentary, surround, gruvbox.
- `<C-n>` → NERDTree toggle
- `<C-p>` → `:Files` (fzf)
- `<C-f>` → `:Rg` (ripgrep dans fzf)
- Tabs : 4 espaces (noexpandtab), numéros relatifs, gruvbox dark

## zsh (.zshrc)

oh-my-zsh + Powerlevel10k. Plugins : git, zsh-autosuggestions, zsh-syntax-highlighting, fzf.
`~/.local/bin` dans le PATH.
