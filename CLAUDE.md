@README.md

The README above describes what this repo does and how to use it. This file
only adds what is needed to maintain it.

## Repo rules

- **The repo is public.** Never commit anything personal or machine-specific:
  no real emails, hostnames, employer/client names, project paths, tokens.
  Machine-dependent files (global `~/.claude/CLAUDE.md`, `~/.p10k.zsh`,
  `.gitconfig`, project-specific `autoMode` in Claude settings) stay out.
- **Commit identity**: the repo-local git config uses the GitHub noreply
  address (`Extazya <9851067+Extazya@users.noreply.github.com>`). Check
  `git config user.email` before committing; never use the global work identity.
- **No Claude attribution**: no `Co-Authored-By: Claude` trailer or any other
  mention of Claude in commits.
- English everywhere (code, comments, script output, docs, commits).
  Conventional commits.
- Update `README.md` whenever behavior changes.

## install.sh internals

- Each step is a `step_<name>` function, run in the order of `ALL_STEPS`.
  `--dry-run` routes side effects through `run()`, which prints instead of
  executing; side effects that don't fit `run()` (pipes, redirections) must
  check `$DRY_RUN` explicitly.
- Idempotence is the contract: check the current state first and call `skip`
  when there is nothing to do. A second run must change nothing.
- `set -eu`: don't end a function with `[ cond ] && cmd` (a false condition
  makes the function return 1 and aborts the script). Use `if`.
- `merge_json src dst [filter]` merges JSON settings (Claude, Sublime): repo
  wins, local-only keys survive, `.bak` only when something changes. Sublime
  files may have trailing commas: they are stripped before jq parses them. A
  file jq still can't parse (comments) is left untouched with a warning.
- Sublime package lists use an order-preserving union (`$l + ($r - $l)`):
  `unique` would sort them and make every run report a change.

## Status line internals

Input schema: https://code.claude.com/docs/en/statusline

- POSIX `sh`, not bash.
- All fields come from one jq call as TSV. Empty strings are mapped to `-`
  because tab is an IFS whitespace character: consecutive tabs would collapse
  and shift the following fields.
- Use `context_window.total_input_tokens`, not `current_usage`: the latter is
  an object, `null` before the first API call and right after `/compact`.
- Directory comes from `workspace.current_dir`, then `cwd`, then `$PWD`.
  `$PWD` is the session's starting directory and doesn't follow `cd`.
- No state files: an older version estimated quotas from token deltas stored
  in `~/.claude/usage_tracker.json`; it was dropped once the harness exposed
  real `rate_limits`.

## Testing

CI (`.github/workflows/ci.yml`) runs the same scripts on every push; run them
before pushing:

- `docker run --rm -v "$PWD":/mnt:ro koalaman/shellcheck:stable install.sh claude/statusline-command.sh tests/*.sh`
  (shellcheck isn't installed locally). Must be clean, including style notes.
- `sh tests/statusline.sh`: add a case there for any status line change.
- `tests/install-twice.sh` really installs everything: only in a container,
  exactly like CI:

  ```sh
  docker run --rm -v "$PWD":/src:ro debian:trixie bash -c '
    apt-get update -qq && apt-get install -y -qq sudo passwd git >/dev/null
    useradd -m -s /bin/bash dev && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
    cp -r /src /home/dev/dotfiles && chown -R dev: /home/dev/dotfiles
    su - dev -c "cd ~/dotfiles && tests/install-twice.sh"'
  ```

  It fails if the second run prints any change. Lines that legitimately show
  up on every run are listed in its `allowed` pattern; keep that list short.
- Tools installed to `~/.local/bin` must be found on the second run:
  install.sh prepends that directory to `PATH` for this reason.

## settings.json

- Deny rules take precedence over allow rules, including those in
  `~/.claude/settings.local.json`. When adding a deny pattern, also cover the
  `sudo` variant and alternative flag spellings (`-fr`, `-f`).
