#!/bin/bash
# Sets up the full dev environment on a Debian/Ubuntu machine.
# Safe to re-run: every step skips what is already in place.
#
#   ./install.sh                       run all steps
#   ./install.sh --dry-run             print what would be done
#   ./install.sh --only zsh,claude     run only some steps
#
# Steps: packages zsh vim gh claude sublime fonts shell git

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
ALL_STEPS="packages zsh vim gh claude sublime fonts shell git"
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

# Sets $sudo to "" (root) or "sudo"; fails if neither is available.
as_root() {
    if [ "$(id -u)" = 0 ]; then sudo=""
    elif has sudo; then sudo=sudo
    else return 1
    fi
}

# Merges the repo's JSON settings into an existing file instead of overwriting
# it, so keys only set locally survive. The repo wins on shared keys and arrays
# are replaced, unless a custom jq filter is given ($l = local, $r = repo).
# Trailing commas (allowed by Sublime) are stripped before parsing.
merge_json() {
    src=$1; dst=$2; filter=${3:-'$l * $r'}
    if [ ! -f "$dst" ]; then install_file "$src" "$dst"; return; fi
    if ! has jq; then warn "jq is required to merge $dst (run the packages step)"; return; fi
    strip='s/,([[:space:]]*[]}])/\1/g'
    if ! merged=$(jq -n --argjson l "$(sed -zE "$strip" "$dst")" \
                        --argjson r "$(sed -zE "$strip" "$src")" "$filter" 2>/dev/null); then
        warn "$dst is not plain JSON (comments?), left untouched: merge $src by hand"
        return
    fi
    if [ "$merged" = "$(sed -zE "$strip" "$dst" | jq .)" ]; then skip "$dst"; return; fi
    info "$dst merged (previous version: $dst.bak)"
    run cp "$dst" "$dst.bak"
    if [ "$DRY_RUN" = 0 ]; then printf '%s\n' "$merged" > "$dst"; fi
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
    if ! as_root; then
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
    step "vim: .vimrc, clangd config, vim-plug, plugins"
    install_file "$DOTFILES/vim/.vimrc" "$HOME/.vimrc"
    install_file "$DOTFILES/clangd/config.yaml" "$HOME/.config/clangd/config.yaml"
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

    # Machine-specific keys (project autoMode, etc.) are not in the repo
    merge_json "$DOTFILES/claude/settings.json" "$HOME/.claude/settings.json"
}

# ── sublime ────────────────────────────────────────────────────────────────
step_sublime() {
    step "Sublime Text: editor, settings, packages"
    if has subl; then
        skip "sublime-text"
    elif ! has apt-get || ! as_root; then
        warn "needs apt and root/sudo: see https://www.sublimetext.com/docs/linux_repositories.html"
    else
        info "official apt repository + sublime-text"
        run $sudo mkdir -p /etc/apt/keyrings
        run sh -c "curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg \
            | $sudo tee /etc/apt/keyrings/sublimehq-pub.asc >/dev/null"
        run sh -c "printf 'Types: deb\nURIs: https://download.sublimetext.com/\nSuites: apt/stable/\nSigned-By: /etc/apt/keyrings/sublimehq-pub.asc\n' \
            | $sudo tee /etc/apt/sources.list.d/sublime-text.sources >/dev/null"
        run $sudo apt-get update -q
        run $sudo apt-get install -y -q sublime-text
    fi

    # Sublime rewrites these files itself (zoom, packages installed from the
    # UI), hence merging. Package lists keep their order and only gain the
    # repo's missing entries, never shrink.
    user="$HOME/.config/sublime-text/Packages/User"
    merge_json "$DOTFILES/sublime/Preferences.sublime-settings" "$user/Preferences.sublime-settings" \
        '($l * $r) | .ignored_packages = ($l.ignored_packages // []) + ($r.ignored_packages - ($l.ignored_packages // []))'
    merge_json "$DOTFILES/sublime/LSP.sublime-settings" "$user/LSP.sublime-settings"
    # LSP ships its F12 (go to definition) binding commented out
    merge_json "$DOTFILES/sublime/Default (Linux).sublime-keymap" "$user/Default (Linux).sublime-keymap" \
        '$l + ($r - $l)'
    merge_json "$DOTFILES/sublime/Package Control.sublime-settings" "$user/Package Control.sublime-settings" \
        '($l * $r) | .installed_packages = ($l.installed_packages // []) + ($r.installed_packages - ($l.installed_packages // []))'

    # Package Control installs every package listed in installed_packages
    # that is missing, the next time Sublime starts.
    pc="$HOME/.config/sublime-text/Installed Packages/Package Control.sublime-package"
    if [ -f "$pc" ]; then
        skip "Package Control"
    else
        info "Package Control"
        run curl -fsSLo "$pc" --create-dirs \
            https://github.com/wbond/package_control/releases/latest/download/Package.Control.sublime-package
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
