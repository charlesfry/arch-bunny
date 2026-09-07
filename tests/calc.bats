#!/usr/bin/env bats
# bunny-calc's own logic is the output tidying and the failure path, not the
# arithmetic. bc is stubbed so this runs whether or not bc is installed.

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"

  cat > "$stub_dir/wl-copy" <<'EOF'
#!/bin/bash
printf 'CLIPBOARD: '; cat
echo
EOF
  cat > "$stub_dir/bunny-notify" <<'EOF'
#!/bin/bash
args=(); while [[ $# -gt 0 ]]; do case "$1" in -u) shift 2;; *) args+=("$1"); shift;; esac; done
printf 'NOTIFY: %s\n' "${args[0]}"
EOF
  # Echoes whatever BC_OUTPUT holds, standing in for bc -l's real formatting.
  cat > "$stub_dir/bc" <<'EOF'
#!/bin/bash
cat >/dev/null
printf '%s\n' "$BC_OUTPUT"
EOF
  chmod +x "$stub_dir"/*
  PATH="$stub_dir:$PATH"
  calc="$repo_root/local/bin/bunny-calc"
}

@test "an integer result is left alone" {
  export BC_OUTPUT=1024
  run "$calc" "2^10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTIFY: 2^10 = 1024"* ]]
  [[ "$output" == *"CLIPBOARD: 1024"* ]]
}

@test "bc's scale padding is trimmed" {
  export BC_OUTPUT=2.50000000000000000000
  run "$calc" "10/4"
  [[ "$output" == *"NOTIFY: 10/4 = 2.5"* ]]
}

@test "a result that is whole after trimming loses its point" {
  export BC_OUTPUT=3.00000000000000000000
  run "$calc" "9/3"
  [[ "$output" == *"NOTIFY: 9/3 = 3"* ]]
}

@test "bc's leading point gets a zero" {
  export BC_OUTPUT=.30000000000000000000
  run "$calc" "0.1+0.2"
  [[ "$output" == *"NOTIFY: 0.1+0.2 = 0.3"* ]]
}

@test "a negative leading point gets a zero" {
  export BC_OUTPUT=-.12500000000000000000
  run "$calc" "-1/8"
  [[ "$output" == *"NOTIFY: -1/8 = -0.125"* ]]
}

@test "an unevaluable expression reports instead of copying" {
  export BC_OUTPUT=""
  run "$calc" "5 +"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOTIFY: Calculator"* ]]
  [[ "$output" != *"CLIPBOARD"* ]]
}
