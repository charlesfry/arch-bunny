#!/bin/bash
# Checks for home/.bash_prompt against real temporary git repos.
# Run directly: ./tests/prompt.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
prompt="$here/../home/.bash_prompt"

pass=0 fail=0
check() { # name expected_regex  -- assert the rendered prompt matches
	local name="$1" re="$2" got
	got=$(printf '%s' "${PS1@P}" | sed 's/\x1b\[[0-9;]*m//g')
	if [[ $got =~ $re ]]; then
		pass=$((pass + 1)); printf '  ok   %s\n' "$name"
	else
		fail=$((fail + 1)); printf '  FAIL %s (want /%s/, got [%s])\n' "$name" "$re" "$got"
	fi
}

check_not() { # name unwanted_regex  -- assert the rendered prompt does NOT match
	local name="$1" re="$2" got
	got=$(printf '%s' "${PS1@P}" | sed 's/\x1b\[[0-9;]*m//g')
	if [[ $got =~ $re ]]; then
		fail=$((fail + 1)); printf '  FAIL %s (unwanted /%s/ in [%s])\n' "$name" "$re" "$got"
	else
		pass=$((pass + 1)); printf '  ok   %s\n' "$name"
	fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/repo"
git -C "$tmp/repo" commit -q --allow-empty -m init
mkdir -p "$tmp/repo/sub/deep" "$tmp/plain"

source "$prompt"

cd "$tmp/plain" || exit 1
(exit 0); _bunny_prompt
check "outside a repo shows the path and a success mark" '/plain ❯ $'
(exit 1); _bunny_prompt
check "a failed command switches the mark to ✗" '✗ $'

cd "$tmp/repo" || exit 1
(exit 0); _bunny_prompt
check "in a clean repo shows repo name and branch" '^repo (master|main) ❯'
check_not "a clean repo has no dirty marker" '●'

: >"$tmp/repo/untracked"
(exit 0); _bunny_prompt
check "an untracked file marks the repo dirty" '●'
rm "$tmp/repo/untracked"

cd "$tmp/repo/sub/deep" || exit 1
(exit 0); _bunny_prompt
check "path is shown relative to the repo root" '^repo/sub/deep '

# Detached HEAD reports a short SHA rather than a branch name.
sha=$(git -C "$tmp/repo" rev-parse --short HEAD)
git -C "$tmp/repo" checkout -q --detach HEAD
(exit 0); _bunny_prompt
check "detached HEAD shows the short SHA" "$sha"
git -C "$tmp/repo" checkout -q -

VIRTUAL_ENV="$tmp/venvs/myenv" _bunny_prompt
check "an active virtualenv is named" 'myenv'
CONDA_DEFAULT_ENV=base _bunny_prompt
check_not "conda's base env is not shown" 'base'

# The timer only reports at 5s and over, so a fast command stays quiet.
_BT=$EPOCHREALTIME; _bunny_prompt
check_not "a fast command reports no duration" '[0-9]+s'
_BT=$(printf '%d.000000' $((${EPOCHREALTIME%.*} - 9))); _bunny_prompt
check "a 9s command reports its duration" ' 9s '
_bunny_prompt
check_not "the duration clears on the next prompt" '[0-9]+s'

echo
echo "passed=$pass failed=$fail"
exit $((fail > 0))
