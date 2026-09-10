#!/bin/bash

BUILDS_DIR="$BUNNY_INSTALL/builds"

if [[ ! -f $BUILDS_DIR/lib.sh ]]; then
  error "Build library not found: $BUILDS_DIR/lib.sh"
  return 1
fi
# shellcheck source=install/builds/lib.sh
source "$BUILDS_DIR/lib.sh"

mapfile -t build_definitions < <(find "$BUILDS_DIR" -maxdepth 1 -type f -name '*.sh' ! -name lib.sh -print | sort)
if ((${#build_definitions[@]} == 0)); then
  section_note "No project builds configured"
  return 0
fi

for build_definition in "${build_definitions[@]}"; do
  build_project "$build_definition"
done
