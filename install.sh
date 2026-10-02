#!/bin/bash
# Installe l'environnement de travail complet sur une machine Debian/Ubuntu.
# Relançable sans risque : chaque étape saute ce qui est déjà en place.
#
#   ./install.sh                       tout installer
#   ./install.sh --dry-run             afficher ce qui serait fait
#   ./install.sh --only zsh,claude     seulement certaines étapes
#
# Étapes : packages zsh vim gh claude fonts shell git

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
ALL_STEPS="packages zsh vim gh claude fonts shell git"
APT_PACKAGES="zsh vim git curl jq ripgrep fzf build-essential fontconfig ca-certificates"

DRY_RUN=0
STEPS=$ALL_STEPS

usage() { sed -n '2,9s/^# \{0,1\}//p' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        --only)
            [ $# -ge 2 ] || { usage; exit 1; }
            STEPS=$(echo "$2" | tr ',' ' '); shift
            for s in $STEPS; do
                case " $ALL_STEPS " in *" $s "*) ;; *) echo "!! étape inconnue : $s" >&2; exit 1 ;; esac
            done ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

# ── helpers ────────────────────────────────────────────────────────────────
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
skip() { printf '    \033[90m%s (déjà en place)\033[0m\n' "$1"; }
warn() { printf '    \033[33m!! %s\033[0m\n' "$1" >&2; }

run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    \033[90m[dry-run] %s\033[0m\n' "$*"
    else
        "$@"
    fi
}

wants() { case " $STEPS " in *" $1 "*) return 0 ;; esac; return 1; }
has()   { command -v "$1" >/dev/null 2>&1; }

# Copie src -> dst ; sauvegarde dst en .bak s'il existe et diffère.
install_file() {
    src=$1; dst=$2
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        skip "$dst"; return
    fi
    run mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ]; then
        run cp "$dst" "$dst.bak"
        info "$dst mis à jour (ancienne version : $dst.bak)"
    else
        info "$dst installé"
    fi
    run cp "$src" "$dst"
}

git_clone() {
    url=$1; dst=$2
    if [ -d "$dst" ]; then skip "$dst"; return; fi
    info "clone $url"
    run git clone --depth 1 -q "$url" "$dst"
}

# ── packages ───────────────────────────────────────────────────────────────
step_packages() {
    step "Paquets système (apt)"
    if ! has apt-get; then
        warn "apt-get introuvable : installe à la main : $APT_PACKAGES"
        return
    fi
    missing=""
    for p in $APT_PACKAGES; do
        dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    if [ -z "$missing" ]; then skip "$APT_PACKAGES"; return; fi
    info "à installer :$missing"
    if [ "$(id -u)" = 0 ]; then
        sudo=""
    elif has sudo; then
        sudo=sudo
    else
        warn "ni root ni sudo : lance en root : apt-get install$missing"
        return
    fi
    run $sudo apt-get update -q
    # shellcheck disable=SC2086
    run $sudo apt-get install -y -q $missing
}

# ── zsh ────────────────────────────────────────────────────────────────────
step_zsh() {
    step "zsh : oh-my-zsh, powerlevel10k, plugins, .zshrc"
    # Clone direct plutôt que le script officiel d'oh-my-zsh : celui-ci
    # remplace ~/.zshrc et lance un nouveau shell en fin d'installation.
    git_clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    custom="$HOME/.oh-my-zsh/custom"
    git_clone https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k"
    git_clone https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions"
    git_clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"
    install_file "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc"
    [ -f "$HOME/.p10k.zsh" ] || info "pas de ~/.p10k.zsh : l'assistant p10k se lancera au premier zsh"
}

# ── vim ────────────────────────────────────────────────────────────────────
step_vim() {
    step "vim : .vimrc, vim-plug, plugins"
    install_file "$DOTFILES/vim/.vimrc" "$HOME/.vimrc"
    if [ -f "$HOME/.vim/autoload/plug.vim" ]; then
        skip "vim-plug"
    else
        info "vim-plug"
        run curl -fsSLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    fi
    info "PlugInstall"
    run sh -c 'vim -E -s -u "$HOME/.vimrc" +PlugInstall +qall >/dev/null 2>&1 || true'
}

# ── gh ─────────────────────────────────────────────────────────────────────
step_gh() {
    step "GitHub CLI (~/.local/bin/gh)"
    if has gh; then skip "gh $(gh --version | head -1 | awk '{print $3}')"; return; fi
    case "$(uname -m)" in
        x86_64)  arch=amd64 ;;
        aarch64) arch=arm64 ;;
        *) warn "architecture $(uname -m) non gérée, gh ignoré"; return ;;
    esac
    if [ "$DRY_RUN" = 1 ]; then
        run "télécharger la dernière release cli/cli (linux_$arch) dans ~/.local/bin/gh"
        return
    fi
    version=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r .tag_name)
    version=${version#v}
    info "gh $version"
    tmp=$(mktemp -d)
    curl -fsSL "https://github.com/cli/cli/releases/download/v$version/gh_${version}_linux_$arch.tar.gz" \
        | tar -xz -C "$tmp"
    mkdir -p "$HOME/.local/bin"
    cp "$tmp/gh_${version}_linux_$arch/bin/gh" "$HOME/.local/bin/gh"
    rm -r "$tmp"
    info "pense à : gh auth login"
}

# ── claude ─────────────────────────────────────────────────────────────────
step_claude() {
    step "Claude Code : binaire, statusline, settings"
    if has claude || [ -x "$HOME/.local/bin/claude" ]; then
        skip "claude"
    else
        info "installeur officiel"
        run sh -c 'curl -fsSL https://claude.ai/install.sh | bash'
    fi

    install_file "$DOTFILES/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
    run chmod +x "$HOME/.claude/statusline-command.sh"

    # Fusion plutôt que copie : les clés propres à la machine (autoMode d'une
    # projet, etc.) ne sont pas dans le dépôt et doivent survivre à l'install.
    # Le dépôt l'emporte sur les clés communes ; les tableaux sont remplacés.
    settings="$HOME/.claude/settings.json"
    if [ ! -f "$settings" ]; then
        install_file "$DOTFILES/claude/settings.json" "$settings"
        return
    fi
    if ! has jq; then
        warn "jq requis pour fusionner $settings (lance l'étape packages)"
        return
    fi
    merged=$(jq -s '.[0] * .[1]' "$settings" "$DOTFILES/claude/settings.json")
    if [ "$merged" = "$(jq . "$settings")" ]; then
        skip "$settings"; return
    fi
    info "$settings fusionné (ancienne version : $settings.bak)"
    run cp "$settings" "$settings.bak"
    if [ "$DRY_RUN" = 0 ]; then
        printf '%s\n' "$merged" > "$settings"
    fi
}

# ── police ─────────────────────────────────────────────────────────────────
step_fonts() {
    step "Police MesloLGS NF (powerlevel10k)"
    fonts="$HOME/.local/share/fonts"
    base=https://github.com/romkatv/powerlevel10k-media/raw/master
    if has fc-list && fc-list | grep -q "MesloLGS NF"; then
        skip "MesloLGS NF"; return
    fi
    changed=0
    for style in Regular Bold Italic "Bold Italic"; do
        f="MesloLGS NF $style.ttf"
        if [ -f "$fonts/$f" ]; then skip "$f"; continue; fi
        info "$f"
        run curl -fsSLo "$fonts/$f" --create-dirs "$base/$(echo "$f" | sed 's/ /%20/g')"
        changed=1
    done
    if [ "$changed" = 1 ]; then
        if has fc-cache; then run fc-cache -f "$fonts"; fi
        info "sélectionne « MesloLGS NF » dans les préférences du terminal"
    fi
}

# ── shell par défaut ───────────────────────────────────────────────────────
step_shell() {
    step "Shell par défaut"
    zsh_path=$(command -v zsh || true)
    if [ -z "$zsh_path" ]; then warn "zsh absent (lance l'étape packages)"; return; fi
    current=$(getent passwd "$(id -un)" | cut -d: -f7)
    if [ "$current" = "$zsh_path" ]; then skip "zsh"; return; fi
    info "$current -> $zsh_path (mot de passe demandé)"
    run chsh -s "$zsh_path" || warn "chsh a échoué : relance chsh -s $zsh_path à la main"
}

# ── git ────────────────────────────────────────────────────────────────────
# L'identité git dépend de la machine (perso / pro) : jamais dans le dépôt,
# seulement demandée si absente.
step_git() {
    step "Identité git"
    if git config --global user.name >/dev/null && git config --global user.email >/dev/null; then
        skip "$(git config --global user.name) <$(git config --global user.email)>"
        return
    fi
    if [ "$DRY_RUN" = 1 ] || [ ! -t 0 ]; then
        info "aucune identité globale : à définir avec git config --global user.name/user.email"
        return
    fi
    printf '    nom : ';   read -r name
    printf '    email : '; read -r email
    if [ -n "$name" ];  then git config --global user.name "$name"; fi
    if [ -n "$email" ]; then git config --global user.email "$email"; fi
}

# ── main ───────────────────────────────────────────────────────────────────
printf '\033[1mInstallation des dotfiles depuis %s\033[0m' "$DOTFILES"
[ "$DRY_RUN" = 1 ] && printf ' \033[33m(dry-run : rien ne sera modifié)\033[0m'
printf '\n'

for s in $ALL_STEPS; do
    if wants "$s"; then "step_$s"; fi
done

printf '\n\033[1;32m==> Terminé.\033[0m Relance ton shell : exec zsh\n'
