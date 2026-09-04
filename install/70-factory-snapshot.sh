#!/bin/bash

# A permanent snapshot of the freshly installed system, so `snapper rollback`
# can always return the machine to its post-install state.
#
# Created with no cleanup algorithm on purpose: Snapper's number/timeline
# cleanup only ever deletes snapshots tagged with an algorithm, so this one
# survives forever. limine-snapper-sync picks it up as a boot menu entry.

step "Checking for the factory snapshot"

factory_description="arch-bunny factory state"

if sudo snapper -c root --csvout list --columns description 2>/dev/null \
  | grep -Fq "$factory_description"; then
  success "Factory snapshot already exists"
else
  run_logged "Creating the factory snapshot" \
    sudo snapper -c root create --description "$factory_description" \
      --userdata "important=yes"
  success "Factory snapshot created: $factory_description"
fi
