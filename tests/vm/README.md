# VM test harness

This host-side harness manages disposable full clones of the powered-off
`arch-bunny-arch-base` VM. It does not modify or start the baseline.

## Configure

The defaults match `VM_SETUP_AND_TESTING.md`. To override them:

```bash
cp tests/vm/config.example tests/vm/config.local
$EDITOR tests/vm/config.local
```

`config.local` is ignored by the repository's `*.local` rule.

## Create the SSH-enabled automation baseline

Keep `arch-bunny-arch-base` unchanged. Create a separate clone and generate its
test-only SSH key:

```bash
./tests/vm/run prepare automation-base
./tests/vm/run keygen
./tests/vm/run ssh-setup
./tests/vm/run view automation-base
```

Unlock LUKS, log in as `arch-bunny-user`, and paste the commands printed by
`ssh-setup`. Back on the host, verify access and power it off:

```bash
./tests/vm/run wait-ssh automation-base
./tests/vm/run stop automation-base
```

Then change this line in `tests/vm/config.local`:

```bash
VM_BASE_NAME=arch-bunny-test-automation-base
```

New test clones inherit OpenSSH, the public test key, and the
`/etc/bunny-test-vm` marker. The original production-like baseline remains
unchanged.

### Test-only firewall rule

When the installer is tested over SSH, keep the following guarded block in the
firewall phase, currently `install/50-firewall.sh`. It must run before UFW's
default policies are changed so the harness does not lose its active SSH
connection:

```bash
# Keep host-side automation reachable only on explicitly marked test VMs. Add
# this rule before changing defaults in case UFW is already active in the base.
if [[ -f /etc/bunny-test-vm && -n ${SSH_CONNECTION:-} ]]; then
  ssh_client_ip=${SSH_CONNECTION%% *}
  run_logged "Allowing test VM SSH traffic" \
    sudo ufw allow from "$ssh_client_ip" to any port 22 proto tcp \
      comment 'allow-bunny-test-host-ssh'
fi
```

Both guards are required: the marker limits the behavior to test VMs, and
`SSH_CONNECTION` limits the rule to SSH-driven runs and supplies the host-side
source address. The rule is temporary test infrastructure, not production
firewall policy.

## Lifecycle

Create and start a clone for a test case:

```bash
./tests/vm/run prepare fresh
```

Open its graphical console and unlock LUKS:

```bash
./tests/vm/run view fresh
```

Inspect it, wait for its DHCP address, and connect after unlocking LUKS:

```bash
./tests/vm/run status fresh
./tests/vm/run wait-ip fresh
./tests/vm/run wait-ssh fresh
./tests/vm/run ssh fresh
```

Run the documented bootstrap command interactively. `bootstrap` uses
`VM_INSTALL_BRANCH` from `config.local`; an explicit argument overrides it:

```bash
./tests/vm/run bootstrap fresh
./tests/vm/run bootstrap fresh another-branch
```

Collect logs and system state under the configured results directory:

```bash
./tests/vm/run collect fresh after-install
```

After pushing changes to the configured branch, update the existing clone and
rerun the complete installer for the idempotency test:

```bash
./tests/vm/run rerun fresh
./tests/vm/run collect fresh after-rerun
```

Rerun transcripts are stored beside bootstrap transcripts in the case results
directory.

Run the read-only post-install verifier after installation and after reboot. It
uses a TTY because checks under `/boot` and UFW may request the disposable
user's sudo password:

```bash
./tests/vm/run verify fresh after-install
./tests/vm/run verify fresh after-reboot
```

Verification transcripts are stored in the case results directory and the
command exits nonzero when an assertion fails.

Save a screenshot under the configured results directory:

```bash
./tests/vm/run screenshot fresh
```

After the final verification and evidence collection, remove the test-only SSH
firewall rule. Do this as the last guest-side operation because subsequent SSH
connections may be blocked:

```bash
./tests/vm/run firewall-cleanup fresh
```

The command verifies that the `allow-bunny-test-host-ssh` rule is gone and
saves a cleanup transcript. If the installer is rerun later over SSH, it will
add the rule again and cleanup must be repeated.

If a firewall test makes SSH unreachable, `firewall-cleanup` cannot connect.
Use the graphical console to recover the guest or discard the disposable clone
with `remove CASE --force`; removing the clone also removes its firewall state.

Request a clean shutdown, then remove the clone and its storage:

```bash
./tests/vm/run stop fresh
./tests/vm/run remove fresh
```

Removal refuses to act on a running VM unless `--force` is explicit:

```bash
./tests/vm/run remove fresh --force
```

List all VMs managed under the configured name prefix:

```bash
./tests/vm/run list
```

Run `./tests/vm/run help` for every command.

## Check the harness

The lifecycle tests mock `virsh` and `virt-clone`; they never contact libvirt:

```bash
shellcheck tests/vm/run tests/bootstrap.bats tests/install.bats tests/static.bats tests/vm/test/run.bats
TMPDIR=/tmp bats tests/bootstrap.bats tests/install.bats tests/static.bats tests/vm/test/run.bats
```

## Current boundary

LUKS unlock remains manual. Bootstrap confirmation is intentionally interactive,
and privileged guest commands may still request the disposable test password.
Serial control can later cover encrypted boot and early-boot logging.
