#!/bin/bash

step "Validating the firewall backend"
if ! command_exists ufw; then
  error "UFW is not installed"
  return 1
fi
if ! command_exists iptables; then
  error "The iptables backend required by UFW is not installed"
  return 1
fi
run_logged "Checking the iptables backend" sudo iptables --version

# Test VMs only, and ahead of the deny-incoming default so an SSH run survives it
if [[ -f /etc/bunny-test-vm && -n ${SSH_CONNECTION:-} ]]; then
  ssh_client_ip=${SSH_CONNECTION%% *}
  run_logged "Allowing test VM SSH traffic" \
    sudo ufw allow from "$ssh_client_ip" to any port 22 proto tcp \
      comment 'allow-bunny-test-host-ssh'
fi

step "Configuring firewall defaults"
run_logged "Denying unsolicited incoming traffic" sudo ufw default deny incoming
run_logged "Allowing outgoing traffic" sudo ufw default allow outgoing

run_logged "Allowing LocalSend UDP traffic" sudo ufw allow 53317/udp
run_logged "Allowing LocalSend TCP traffic" sudo ufw allow 53317/tcp

run_logged "Enabling UFW" sudo ufw --force enable
run_logged "Enabling the UFW system service" sudo systemctl enable ufw

success "Firewall configured and enabled"
