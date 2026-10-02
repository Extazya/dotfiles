#!/bin/bash
# Runs the installer twice as the current user and fails if the second run
# still does something: every step must report "already in place".
# Meant for a fresh, disposable machine (CI container): it really installs.
# Usage: tests/install-twice.sh   (from the repo root)

set -eu
cd "$(dirname "$0")/.."

./install.sh

echo
echo "######## second run"
out=$(./install.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
echo "$out"

# Lines that are expected on every run (not actual changes):
# PlugInstall always runs, chsh can't succeed without a password, and there
# is no p10k config or git identity on a fresh machine.
allowed='PlugInstall|no ~/\.p10k\.zsh|no global identity|-> .*zsh \(password required\)|chsh failed'
changes=$(echo "$out" | grep -E '^    ' | grep -v '(already in place)' | grep -vE "$allowed" || true)

if [ -n "$changes" ]; then
    echo
    echo "FAIL: the second run still made changes:"
    echo "$changes"
    exit 1
fi
echo
echo "ok: second run changed nothing"
