#!/bin/bash
# Sets up the full dev environment on a Debian/Ubuntu machine.
# Safe to re-run: every step skips what is already in place.
#
#   ./install.sh                       run all steps
#   ./install.sh --dry-run             print what would be done
#   ./install.sh --only zsh,claude     run only some steps
#
# Steps: packages zsh vim gh claude fonts shell git

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
ALL_STEPS="packages zsh vim gh claude fonts shell git"
APT_PACKAGES="zsh vim git curl jq ripgrep fzf build-essential clangd bear fontconfig ca-certificates"

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
                case " $ALL_STEPS " in *" $s "*) ;; *) echo "!! unknown step: $s" >&2; exit 1 ;; esac
            done ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

# ── helpers ────────────────────────────────────────────────────────────────
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
skip() { printf '    \033[90m%s (already in place)\033[0m\n' "$1"; }
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

# Copies src -> dst; backs up dst to .bak if it exists and differs.
install_file() {
    src=$1; dst=$2
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        skip "$dst"; return
    fi
    run mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ]; then
        run cp "$dst" "$dst.bak"
        info "$dst updated (previous version: $dst.bak)"
    else
        info "$dst installed"
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
    step "System packages (apt)"
    if ! has apt-get; then
        warn "apt-get not found, install manually: $APT_PACKAGES"
        return
    fi
    missing=""
    for p in $APT_PACKAGES; do
        dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    if [ -z "$missing" ]; then skip "$APT_PACKAGES"; return; fi
    info "to install:$missing"
    if [ "$(id -u)" = 0 ]; then
        sudo=""
    elif has sudo; then
        sudo=sudo
    else
        warn "neither root nor sudo, run as root: apt-get install$missing"
        return
    fi
    run $sudo apt-get update -q
    # shellcheck disable=SC2086
    run $sudo apt-get install -y -q $missing
}

# ── zsh ────────────────────────────────────────────────────────────────────
step_zsh() {
    step "zsh: oh-my-zsh, powerlevel10k, plugins, .zshrc"
    # Plain clone instead of oh-my-zsh's official script, which overwrites
    # ~/.zshrc and execs a new shell when done.
    git_clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    custom="$HOME/.oh-my-zsh/custom"
    git_clone https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k"
    git_clone https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions"
    git_clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"
    install_file "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc"
    [ -f "$HOME/.p10k.zsh" ] || info "no ~/.p10k.zsh: the p10k wizard will run on first zsh start"
}

# ── vim ────────────────────────────────────────────────────────────────────
step_vim() {
    step "vim: .vimrc, vim-plug, plugins"
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
        *) warn "unsupported architecture $(uname -m), skipping gh"; return ;;
    esac
    if [ "$DRY_RUN" = 1 ]; then
        run "download latest cli/cli release (linux_$arch) to ~/.local/bin/gh"
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
    info "next: gh auth login"
}

# ── claude ─────────────────────────────────────────────────────────────────
step_claude() {
    step "Claude Code: binary, status line, settings"
    if has claude || [ -x "$HOME/.local/bin/claude" ]; then
        skip "claude"
    else
        info "official installer"
        run sh -c 'curl -fsSL https://claude.ai/install.sh | bash'
    fi

    install_file "$DOTFILES/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
    run chmod +x "$HOME/.claude/statusline-command.sh"

    # Merge instead of copy: machine-specific keys (project autoMode, etc.)
    # are not in the repo and must survive the install. The repo wins on
    # shared keys; arrays are replaced.
    settings="$HOME/.claude/settings.json"
    if [ ! -f "$settings" ]; then
        install_file "$DOTFILES/claude/settings.json" "$settings"
        return
    fi
    if ! has jq; then
        warn "jq is required to merge $settings (run the packages step)"
        return
    fi
    merged=$(jq -s '.[0] * .[1]' "$settings" "$DOTFILES/claude/settings.json")
    if [ "$merged" = "$(jq . "$settings")" ]; then
        skip "$settings"; return
    fi
    info "$settings merged (previous version: $settings.bak)"
    run cp "$settings" "$settings.bak"
    if [ "$DRY_RUN" = 0 ]; then
        printf '%s\n' "$merged" > "$settings"
    fi
}

# ── font ───────────────────────────────────────────────────────────────────
step_fonts() {
    step "MesloLGS NF font (powerlevel10k)"
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
        info "select 'MesloLGS NF' in your terminal preferences"
    fi
}

# ── login shell ────────────────────────────────────────────────────────────
step_shell() {
    step "Login shell"
    zsh_path=$(command -v zsh || true)
    if [ -z "$zsh_path" ]; then warn "zsh not found (run the packages step)"; return; fi
    current=$(getent passwd "$(id -un)" | cut -d: -f7)
    if [ "$current" = "$zsh_path" ]; then skip "zsh"; return; fi
    info "$current -> $zsh_path (password required)"
    run chsh -s "$zsh_path" || warn "chsh failed, run it manually: chsh -s $zsh_path"
}

# ── git ────────────────────────────────────────────────────────────────────
# Git identity depends on the machine (personal / work): never stored in the
# repo, only prompted for when missing.
step_git() {
    step "Git identity"
    if git config --global user.name >/dev/null && git config --global user.email >/dev/null; then
        skip "$(git config --global user.name) <$(git config --global user.email)>"
        return
    fi
    if [ "$DRY_RUN" = 1 ] || [ ! -t 0 ]; then
        info "no global identity: set it with git config --global user.name/user.email"
        return
    fi
    printf '    name: ';   read -r name
    printf '    email: '; read -r email
    if [ -n "$name" ];  then git config --global user.name "$name"; fi
    if [ -n "$email" ]; then git config --global user.email "$email"; fi
}

# ── main ───────────────────────────────────────────────────────────────────
printf '\033[1mInstalling dotfiles from %s\033[0m' "$DOTFILES"
[ "$DRY_RUN" = 1 ] && printf ' \033[33m(dry-run: nothing will be changed)\033[0m'
printf '\n'

for s in $ALL_STEPS; do
    if wants "$s"; then "step_$s"; fi
done

printf '\n\033[1;32m==> Done.\033[0m Restart your shell: exec zsh\n'
