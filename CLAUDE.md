# dotfiles

Portable dev environment (zsh, vim, Claude Code) with an idempotent
Debian/Ubuntu installer. User-facing docs live in `README.md`; this file holds
the maintenance notes.

## Repo rules

- **The repo is public.** Never commit anything personal or machine-specific:
  no real emails, hostnames, employer/client names, project paths, tokens.
  Anything that depends on the machine (global `~/.claude/CLAUDE.md`,
  `~/.p10k.zsh`, `.gitconfig`, project-specific `autoMode` in Claude settings)
  stays out of the repo.
- **Commit identity**: the repo-local git config uses the GitHub noreply
  address (`Extazya <9851067+Extazya@users.noreply.github.com>`). Check
  `git config user.email` before committing; never use the global work identity.
- **No Claude attribution**: no `Co-Authored-By: Claude` trailer or any other
  mention of Claude in commits.
- Conventional commits, in English. Docs (`README.md`, this file) in English.
- Keep `README.md` in sync when behavior changes.

## Layout

```
dotfiles/
├── README.md
├── CLAUDE.md
├── install.sh                  bash installer
├── .gitignore
├── vim/.vimrc
├── zsh/.zshrc
└── claude/
    ├── settings.json           merged into ~/.claude/settings.json
    └── statusline-command.sh   POSIX sh, copied to ~/.claude/
```

## install.sh

- Steps run in this fixed order: `packages zsh vim gh claude fonts shell git`.
  Each is a `step_<name>` function; `--only a,b` filters them, `--dry-run`
  routes every side effect through `run()`, which prints instead of executing.
  Side effects that don't fit `run()` (pipes, redirections) must check
  `$DRY_RUN` explicitly.
- Idempotence is the contract: every step checks the current state first and
  calls `skip` when nothing needs doing. A second run must change nothing.
- `install_file src dst`: no-op if identical, otherwise backs up `dst` to
  `dst.bak` before copying.
- `settings.json` is merged, not copied: `jq -s '.[0] * .[1]' local repo`.
  Repo wins on shared keys, arrays are replaced, local-only keys survive. The
  backup is only written when the merge actually changes something.
- `set -eu`: avoid `[ cond ] && cmd` as the last statement of a function (a
  false condition makes the function return 1 and aborts the script). Use `if`.
- oh-my-zsh is `git clone`d; its official script overwrites `.zshrc` and
  `exec`s a new shell.
- `chsh` fails in containers or without a password: it only warns.

**Test** (fresh machine, takes a few minutes):

```sh
docker run --rm -v "$PWD":/src:ro debian:trixie bash -c '
  apt-get update -qq && apt-get install -y -qq sudo passwd >/dev/null
  useradd -m -s /bin/bash dev && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
  cp -r /src /home/dev/dotfiles && chown -R dev: /home/dev/dotfiles
  su - dev -c "cd ~/dotfiles && ./install.sh && ./install.sh"'
```

The second run should report every step as already in place (except `chsh`,
which cannot succeed in the container).

## Status line (claude/statusline-command.sh)

POSIX `sh` (not bash), run by Claude Code with JSON on stdin. Claude Code has
no built-in equivalent: without it, quotas are only visible via `/usage`.
Input schema: https://code.claude.com/docs/en/statusline

- All fields are extracted in **one jq call** as TSV, with defaults for
  missing fields. Empty strings are mapped to `-` because tab is an IFS
  whitespace character: consecutive tabs would collapse and shift the fields.
- Context: `context_window.used_percentage`, `context_window_size`,
  `total_input_tokens`. Do not use `current_usage`: it is an object, `null`
  before the first API call and right after `/compact`.
- Directory: `workspace.current_dir`, then `cwd`, then `$PWD`. `$PWD` alone is
  the session's starting directory and does not follow `cd` inside the session.
- Quotas: `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`
  (`resets_at` is Unix epoch seconds). Absent on plans without rate limits:
  line 2 then shows an "unavailable" message instead of failing.
- `model.display_name` and `effort.level` are shown at the end of line 2 when
  present.
- No state files. An older version estimated quotas by accumulating token
  deltas in `~/.claude/usage_tracker.json`; it was removed once the harness
  started exposing real values.
- Colors: 16 basic ANSI colors only (plus the bright `9x` variants), so the
  bar follows the terminal theme. Thresholds: green < 60, yellow 60–79,
  red ≥ 80.
- Refreshed on session events and every 30 s (`statusLine.refreshInterval`).

**Test**: see the command in `README.md`, plus edge cases: empty input,
invalid JSON, no `rate_limits`, empty `model.display_name`, a directory
outside `$HOME`, a path with spaces.

## settings.json

- Deny rules take precedence over allow rules, including those in
  `~/.claude/settings.local.json`. When adding a deny pattern, also cover the
  `sudo` variant and alternative flag spellings (`-fr`, `-f`).
- Keep only portable keys here. Project-specific keys (e.g. `autoMode`) live
  only in the local `~/.claude/settings.json` and survive installs thanks to
  the merge.
