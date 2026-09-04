#!/usr/bin/env bats

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  mock_bin=$BATS_TEST_TMPDIR/bin
  test_home=$BATS_TEST_TMPDIR/home
  mkdir -p "$mock_bin" "$test_home"
  cat > "$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS"
printf 'clone progress details\n' >&2
clone_dir=${!#}
mkdir -p "$clone_dir"
printf '#!/usr/bin/env bash\nprintf "installer started\\n"\n' > "$clone_dir/install.sh"
EOF
  cat > "$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -n && ${2:-} == true ]] && exit 0
[[ ${1:-} == -v ]] && exit 0
exec "$@"
EOF
  chmod +x "$mock_bin/git" "$mock_bin/sudo"
}

run_bootstrap_in_tty() {
  local answer=$1
  shift
  local command
  printf -v command 'env HOME=%q GIT_CALLS=%q PATH=%q bash %q' \
    "$test_home" "$BATS_TEST_TMPDIR/git.calls" "$mock_bin:$PATH" "$repo_root/bootstrap.sh"
  local argument
  for argument in "$@"; do
    printf -v argument '%q' "$argument"
    command+=" $argument"
  done
  run bash -c 'printf "%s\n" "$1" | script -qefc "$2" /dev/null' _ "$answer" "$command"
}

@test "public submodules use HTTPS URLs" {
  run git -C "$repo_root" config --file .gitmodules --get-regexp '^submodule\..*\.url$'

  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while read -r _ url; do
    [[ $url == https://* ]]
    [[ $url != git@* ]]
  done <<< "$output"
}

@test "README bootstrap preserves terminal input" {
  run grep -F 'bash <(curl -fsSL' "$repo_root/README.md"

  [ "$status" -eq 0 ]
  [[ $output != *"| bash"* ]]
}

@test "bootstrap requires sudo access before setup" {
  auth_line=$(grep -nF 'if ! sudo -n true' "$repo_root/bootstrap.sh" | cut -d: -f1)
  setup_line=$(grep -nF 'if ! command -v git' "$repo_root/bootstrap.sh" | cut -d: -f1)

  [ "$auth_line" -lt "$setup_line" ]
}

@test "bootstrap reads confirmation from the terminal and aborts" {
  run_bootstrap_in_tty n

  [ "$status" -eq 0 ]
  [[ $output == *"Aborted."* ]]
  [[ $output == *$'\033[1;33m! This will configure packages'* ]]
  [[ $output != *$'\033[0;31mThis will configure packages'* ]]
  [[ $output != *"installer started"* ]]
}

@test "bootstrap passes the requested branch and starts after confirmation" {
  run_bootstrap_in_tty y --branch installer-refactor

  [ "$status" -eq 0 ]
  [[ $output == *"installer started"* ]]
  [[ $output != *"Starting installer..."* ]]
  [[ $output != *"clone progress details"* ]]
  grep -Fq 'clone progress details' "$test_home/.local/state/arch-bunny/install.log"
  grep -Fq -- '--recurse-submodules -b installer-refactor' "$BATS_TEST_TMPDIR/git.calls"
}
