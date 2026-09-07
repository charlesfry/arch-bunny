#!/usr/bin/env bats
# The delay parser is the only branching logic in bunny-reminder: a bare number
# has to mean minutes, and anything that is not a duration has to be refused
# rather than handed to systemd-run.

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"

  cat > "$stub_dir/systemd-run" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  [[ $arg == --on-active=* ]] && echo "SCHEDULED: ${arg#--on-active=}"
done
exit 0
EOF
  cat > "$stub_dir/bunny-notify" <<'EOF'
#!/bin/bash
args=(); while [[ $# -gt 0 ]]; do case "$1" in -u) shift 2;; *) args+=("$1"); shift;; esac; done
printf 'NOTIFY: %s | %s\n' "${args[0]}" "${args[1]:-}"
EOF
  chmod +x "$stub_dir"/*
  PATH="$stub_dir:$PATH"
  reminder="$repo_root/local/bin/bunny-reminder"
}

@test "a bare number is minutes" {
  run "$reminder" 5 stretch your legs
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEDULED: 5m"* ]]
  [[ "$output" == *"NOTIFY: Reminder set | stretch your legs — in 5m"* ]]
}

@test "an explicit unit is kept" {
  run "$reminder" 90s tea
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEDULED: 90s"* ]]
}

@test "a delay with no message still schedules" {
  run "$reminder" 2h
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEDULED: 2h"* ]]
  [[ "$output" == *"NOTIFY: Reminder set | Reminder — in 2h"* ]]
}

@test "a non-duration is refused, not scheduled" {
  run "$reminder" soon do the thing
  [ "$status" -eq 1 ]
  [[ "$output" != *"SCHEDULED"* ]]
  [[ "$output" == *'Not a delay'* ]]
}
