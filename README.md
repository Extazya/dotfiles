# dotfiles

My portable development environment: **zsh** (oh-my-zsh + Powerlevel10k),
**vim** (gruvbox, NERDTree, fzf, clangd for C) and **Claude Code** (settings + a custom
two-line status line showing context and real quota usage), with a single
idempotent installer for Debian/Ubuntu.

## Quick start

```sh
git clone https://github.com/Extazya/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run   # see what would change
./install.sh             # do it
exec zsh
```

The installer is safe to re-run: every step checks what is already in place
and skips it. Any existing file it replaces is first backed up as
`<file>.bak`.

## What's inside

```
dotfiles/
├── install.sh                  installer (see below)
├── vim/.vimrc                  → ~/.vimrc
├── zsh/.zshrc                  → ~/.zshrc
└── claude/
    ├── settings.json           → merged into ~/.claude/settings.json
    └── statusline-command.sh   → ~/.claude/statusline-command.sh
```

Files are **copied**, not symlinked. To change one, edit it in the repo and
re-run `./install.sh --only <step>`.

## Installer

```sh
./install.sh                     # all steps
./install.sh --dry-run           # print what would be done, change nothing
./install.sh --only zsh,claude   # run only some steps
./install.sh --help
```

| Step       | What it does |
|------------|--------------|
| `packages` | Installs missing apt packages: zsh, vim, git, curl, jq, ripgrep, fzf, build-essential, clangd, bear, fontconfig, ca-certificates (uses `sudo`, or runs directly as root) |
| `zsh`      | Clones oh-my-zsh, Powerlevel10k, zsh-autosuggestions and zsh-syntax-highlighting, then installs `.zshrc` |
| `vim`      | Installs `.vimrc` and vim-plug, then runs `:PlugInstall` |
| `gh`       | Downloads the latest GitHub CLI release to `~/.local/bin/gh` (amd64/arm64) |
| `claude`   | Installs Claude Code with the official installer if missing, the status line script, and merges `settings.json` |
| `fonts`    | Installs the MesloLGS NF font (recommended by Powerlevel10k) to `~/.local/share/fonts` |
| `shell`    | Makes zsh your login shell with `chsh` (asks for your password) |
| `git`      | Asks for your git name/email if no global identity is set |

Notes:

- oh-my-zsh is cloned directly instead of using its official install script,
  which would overwrite `.zshrc` and start a new shell.
- `~/.p10k.zsh` is **not** tracked, so the Powerlevel10k wizard runs the first
  time you open zsh on a new machine.
- After the `fonts` step, select "MesloLGS NF" in your terminal's preferences.
- Your git identity is never stored in the repo: it usually differs between
  machines (personal vs. work).
- Tested on a fresh `debian:trixie` container.

### How `settings.json` is merged

Claude Code settings often contain machine- or project-specific keys that
don't belong in a public repo. So instead of overwriting
`~/.claude/settings.json`, the installer merges the repo's version into it:

```sh
jq -s '.[0] * .[1]' ~/.claude/settings.json claude/settings.json
```

The repo wins on shared keys, arrays (such as permission lists) are replaced
as a whole, and keys that only exist locally are kept.

## Claude Code status line

`claude/statusline-command.sh` is a POSIX `sh` script that Claude Code runs to
draw a two-line status bar:

```
Context: 42% (~58000 tokens left) | Session: 12m | ~/projects/demo -> main
Quota: 18% (4h00m reset) | Weekly: 7% (2d14h reset) | Opus 5.5 · high
```

- **Context**: how full the context window is, and the tokens left.
- **Session**: time since the session started.
- **Directory and git branch** of Claude's current working directory.
- **Quota / Weekly**: real usage of the 5-hour and 7-day rate limits, with
  time until reset. These are the same numbers as `/usage`, read from the JSON
  Claude Code passes to the script. Nothing is estimated.
- **Model and effort level**.

Percentages are green below 60%, yellow from 60% to 79% and red from 80%.
Only the 16 basic ANSI colors are used, so the bar follows your terminal theme.
If your plan has no rate limits, line 2 shows `Quota: unavailable`.

It refreshes on every session event and every 30 seconds (`refreshInterval`),
so reset countdowns keep moving while idle. It needs `jq`.

Test it without Claude Code:

```sh
now=$(date -u +%s)
echo '{"workspace":{"current_dir":"'"$HOME"'"},
       "model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},
       "context_window":{"used_percentage":20,"context_window_size":200000,"total_input_tokens":40000},
       "cost":{"total_duration_ms":720000},
       "rate_limits":{"five_hour":{"used_percentage":18,"resets_at":'$((now+14400))'},
                      "seven_day":{"used_percentage":7,"resets_at":'$((now+216000))'}}}' \
  | sh ~/.claude/statusline-command.sh
```

## Claude Code settings

- Dark theme, `opus` model, `high` effort.
- Status line: the script above, refreshed every 30 s.
- Permissions: `Bash`, `Read`, `Edit` and `Write` are allowed without
  prompting, but destructive commands are denied: `rm -rf`/`rm -fr`, force
  pushes (`--force` and `-f`), `git reset --hard`, `dd`, `mkfs`, and their
  `sudo` variants. Deny rules take precedence over any allow rule, including
  ones in `settings.local.json`.

## vim

Set up for plain C (42 norm style): 4-column tabs (real tabs, not spaces), a
guide at column 81, tabs drawn as thin indent guides and trailing spaces as
dots. Relative line numbers, smart-case search, no line wrapping.

Plugins (via vim-plug): NERDTree, fzf + fzf.vim, vim-commentary,
vim-surround, gruvbox (dark), and [yegappan/lsp](https://github.com/yegappan/lsp)
with **clangd** for C.

| Key      | Action |
|----------|--------|
| `Ctrl-n` | Toggle NERDTree (also opens on startup) |
| `Ctrl-p` | Find files (`:Files`) |
| `Ctrl-f` | Search file contents with ripgrep (`:Rg`) |
| `gd`     | Go to definition (`Ctrl-o` to come back) |
| `gr`     | List references |
| `K`      | Show the type / documentation of the symbol under the cursor |
| `]d` `[d`| Next / previous error or warning |

Completion pops up automatically while typing: `Ctrl-n`/`Ctrl-p` to move,
`Enter` to accept. Errors and warnings show up as you type, with a sign in the
left column and the message at the end of the line.

clangd only analyzes the code for the editor; you still compile with gcc. It
works out of the box on a single folder of `.c` files. If your headers live
elsewhere (e.g. `include/`), tell clangd how you build, once per project:

```sh
bear -- make        # records your gcc flags in compile_commands.json
```

or create a `compile_flags.txt` at the project root, one flag per line:

```
-std=c99
-Wall
-Iinclude
```

## zsh

oh-my-zsh with the Powerlevel10k theme and the `git`, `zsh-autosuggestions`,
`zsh-syntax-highlighting` and `fzf` plugins. `~/.local/bin` is added to
`PATH` (that's where `gh` and `claude` are installed).

## License

Personal configuration, shared as-is. Feel free to copy anything useful.
