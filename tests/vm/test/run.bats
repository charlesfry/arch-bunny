#!/usr/bin/env bats

setup() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)
  runner=$repo_root/tests/vm/run
  mock_bin=$BATS_TEST_TMPDIR/bin
  mock_state=$BATS_TEST_TMPDIR/state
  mock_log=$BATS_TEST_TMPDIR/commands.log

  mkdir -p "$mock_bin" "$mock_state"
  : > "$mock_log"

  export MOCK_STATE=$mock_state
  export MOCK_LOG=$mock_log
  export VM_TEST_CONFIG=$BATS_TEST_TMPDIR/config.local
  export PATH=$mock_bin:$PATH

  cat > "$VM_TEST_CONFIG" <<EOF
VM_CONNECT_URI=qemu:///system
VM_BASE_NAME=arch-bunny-arch-base
VM_NAME_PREFIX=arch-bunny-test-
VM_RESULTS_DIR="$BATS_TEST_TMPDIR/results"
VM_WAIT_TIMEOUT=2
VM_SSH_USER=arch-bunny-user
VM_SSH_KEY="$BATS_TEST_TMPDIR/id_ed25519"
VM_SSH_KNOWN_HOSTS="$BATS_TEST_TMPDIR/known_hosts"
VM_BOOTSTRAP_URL=https://example.test/bootstrap.sh
VM_INSTALL_BRANCH=installer-refactor
EOF

  cat > "$mock_bin/virsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'virsh' >> "$MOCK_LOG"
printf ' %q' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"

if [[ ${1:-} == --connect ]]; then
  shift 2
fi

command=${1:-}
shift || true

case "$command" in
  dominfo)
    vm=$1
    if [[ $vm == arch-bunny-arch-base || -f $MOCK_STATE/$vm ]]; then
      printf 'Name: %s\n' "$vm"
    else
      exit 1
    fi
    ;;
  domstate)
    vm=$1
    if [[ $vm == arch-bunny-arch-base ]]; then
      printf '%s\n' "${MOCK_BASE_STATE:-shut off}"
    else
      cat "$MOCK_STATE/$vm"
    fi
    ;;
  domblklist)
    printf 'Target Source\nvda /var/lib/libvirt/images/test.qcow2\n'
    ;;
  dumpxml)
    printf '<domain><os><nvram>/var/lib/libvirt/qemu/nvram/test_VARS.fd</nvram></os></domain>\n'
    ;;
  start)
    printf 'running\n' > "$MOCK_STATE/$1"
    printf 'Domain %s started\n' "$1"
    ;;
  shutdown)
    printf 'shut off\n' > "$MOCK_STATE/$1"
    ;;
  destroy)
    printf 'shut off\n' > "$MOCK_STATE/$1"
    ;;
  undefine)
    rm -f "$MOCK_STATE/$1"
    ;;
  domiflist)
    printf 'Interface Type Source Model MAC\nvnet0 network default virtio 52:54:00:00:00:01\n'
    ;;
  domifaddr)
    if [[ -f $MOCK_STATE/ip ]]; then
      printf ' Name MAC address Protocol Address\n'
      while read -r ip; do
        printf ' vnet0 52:54:00:00:00:01 ipv4 %s/24\n' "$ip"
      done < "$MOCK_STATE/ip"
    fi
    ;;
  list)
    if [[ ${1:-} == --all && ${2:-} == --name ]]; then
      printf '%s\n' arch-bunny-arch-base
      for state_file in "$MOCK_STATE"/arch-bunny-test-*; do
        [[ -e $state_file ]] && basename "$state_file"
      done
    fi
    ;;
  screenshot)
    : > "$2"
    printf 'Screenshot saved\n'
    ;;
  *)
    printf 'Unexpected mocked virsh command: %s\n' "$command" >&2
    exit 64
    ;;
esac
EOF

  cat > "$mock_bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'ssh' >> "$MOCK_LOG"
printf ' %q' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"

for argument in "$@"; do
  if [[ $argument == *@* ]]; then
    ip=${argument##*@}
    [[ ! -f $MOCK_STATE/unreachable-$ip ]] || exit 255
  fi
done
EOF

  cat > "$mock_bin/virt-clone" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'virt-clone' >> "$MOCK_LOG"
printf ' %q' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"

name=
while (($#)); do
  if [[ $1 == --name ]]; then
    name=$2
    break
  fi
  shift
done

[[ -n $name ]]
printf 'shut off\n' > "$MOCK_STATE/$name"
printf 'Clone %s created\n' "$name"
EOF

  chmod +x "$mock_bin/virsh" "$mock_bin/ssh" "$mock_bin/virt-clone"
}

@test "help describes the lifecycle commands" {
  run "$runner" help

  [ "$status" -eq 0 ]
  [[ $output == *"prepare CASE"* ]]
  [[ $output == *"verify CASE [LABEL]"* ]]
  [[ $output == *"firewall-cleanup CASE"* ]]
  [[ $output == *"remove CASE [--force]"* ]]
}

@test "prepare clones the powered-off baseline and starts the clone" {
  run "$runner" prepare fresh

  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_STATE/arch-bunny-test-fresh")" = running ]
  grep -q 'virt-clone .*--original arch-bunny-arch-base .*--name arch-bunny-test-fresh' "$MOCK_LOG"
  grep -q 'virsh .* start arch-bunny-test-fresh' "$MOCK_LOG"
}

@test "create refuses to clone a running baseline" {
  export MOCK_BASE_STATE=running

  run "$runner" create fresh

  [ "$status" -ne 0 ]
  [[ $output == *"baseline VM must be powered off"* ]]
  run grep -q '^virt-clone ' "$MOCK_LOG"
  [ "$status" -eq 1 ]
}

@test "remove refuses to delete a running clone without force" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"

  run "$runner" remove fresh

  [ "$status" -ne 0 ]
  [[ $output == *"stop it first"* ]]
  [ -f "$MOCK_STATE/arch-bunny-test-fresh" ]
  run grep -q ' undefine ' "$MOCK_LOG"
  [ "$status" -eq 1 ]
}

@test "forced removal destroys and undefines only the named clone" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"

  run "$runner" remove fresh --force

  [ "$status" -eq 0 ]
  [ ! -e "$MOCK_STATE/arch-bunny-test-fresh" ]
  grep -q ' destroy arch-bunny-test-fresh' "$MOCK_LOG"
  grep -q ' undefine arch-bunny-test-fresh --nvram --remove-all-storage' "$MOCK_LOG"
  run grep -q 'undefine arch-bunny-arch-base' "$MOCK_LOG"
  [ "$status" -eq 1 ]
}

@test "ip prints a DHCP lease address" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n' > "$MOCK_STATE/ip"

  run "$runner" ip fresh

  [ "$status" -eq 0 ]
  [ "$output" = 192.168.122.204 ]
}

@test "ip prefers the newest DHCP lease" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.113\n192.168.122.114\n' > "$MOCK_STATE/ip"

  run "$runner" ip fresh

  [ "$status" -eq 0 ]
  [ "$output" = 192.168.122.114 ]
}

@test "ssh-setup generates a key and guarded guest setup commands" {
  run "$runner" ssh-setup

  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/id_ed25519" ]
  [ -f "$BATS_TEST_TMPDIR/id_ed25519.pub" ]
  [[ $output == *"sudo pacman -S --needed curl openssh"* ]]
  [[ $output == *"/etc/bunny-test-vm"* ]]
  [[ $output == *"systemctl enable --now sshd.service"* ]]
}

@test "bootstrap uses the configured branch through SSH" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n' > "$MOCK_STATE/ip"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_ed25519"

  run "$runner" bootstrap fresh

  [ "$status" -eq 0 ]
  grep -q 'arch-bunny-user@192.168.122.204' "$MOCK_LOG"
  grep -Fq 'bash\ \<\(curl\ -fsSL\ https://example.test/bootstrap.sh\)\ -b\ installer-refactor' "$MOCK_LOG"
  run grep -Fq 'pacman\ -S\ --needed\ curl\ \&\&' "$MOCK_LOG"
  [ "$status" -eq 1 ]
}

@test "rerun updates and runs the configured branch through SSH" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n' > "$MOCK_STATE/ip"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_ed25519"

  run "$runner" rerun fresh

  [ "$status" -eq 0 ]
  grep -q 'arch-bunny-user@192.168.122.204' "$MOCK_LOG"
  grep -Fq 'git\ fetch\ origin\ installer-refactor' "$MOCK_LOG"
  grep -Fq 'git\ merge\ --ff-only\ origin/installer-refactor' "$MOCK_LOG"
  grep -Fq 'bash\ install.sh' "$MOCK_LOG"
}

@test "collect records package, repository, and hook baselines" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n' > "$MOCK_STATE/ip"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_ed25519"

  run "$runner" collect fresh baseline

  [ "$status" -eq 0 ]
  for artifact in install-traces.log packages-explicit.txt repositories.txt pacman-configuration.txt generation-hooks.txt boot-generation-events.txt; do
    [ -f "$BATS_TEST_TMPDIR/results/fresh/baseline/$artifact" ]
  done
  grep -Fq 'pacman\ -Qqe' "$MOCK_LOG"
  grep -Fq 'pacman-conf\ --repo-list' "$MOCK_LOG"
  grep -Fq '/etc/pacman.conf.bunny-original' "$MOCK_LOG"
}

@test "SSH commands use a reachable address instead of the last stale lease" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n192.168.122.252\n' > "$MOCK_STATE/ip"
  touch "$MOCK_STATE/unreachable-192.168.122.252"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_ed25519"

  run "$runner" verify fresh reachable

  [ "$status" -eq 0 ]
  grep -q 'arch-bunny-user@192.168.122.204' "$MOCK_LOG"
}

@test "verify runs the read-only guest verifier and saves a transcript" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n' > "$MOCK_STATE/ip"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_ed25519"

  run "$runner" verify fresh baseline

  [ "$status" -eq 0 ]
  grep -Fq 'bash\ install/verify.sh' "$MOCK_LOG"
  [ -f "$BATS_TEST_TMPDIR/results/fresh/verify-baseline.log" ]
}

@test "firewall cleanup removes and verifies the test-only SSH rule" {
  printf 'running\n' > "$MOCK_STATE/arch-bunny-test-fresh"
  printf '192.168.122.204\n' > "$MOCK_STATE/ip"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_ed25519"

  run "$runner" firewall-cleanup fresh

  [ "$status" -eq 0 ]
  grep -Fq 'ufw\ --force\ delete\ allow\ from' "$MOCK_LOG"
  grep -Fq 'allow-bunny-test-host-ssh' "$MOCK_LOG"
  [ "$(find "$BATS_TEST_TMPDIR/results/fresh" -name 'firewall-cleanup-*.log' | wc -l)" -eq 1 ]
}

@test "invalid case names are rejected before calling libvirt" {
  run "$runner" remove ../arch-bunny-arch-base --force

  [ "$status" -ne 0 ]
  [[ $output == *"invalid case name"* ]]
  [ ! -s "$MOCK_LOG" ]
}
