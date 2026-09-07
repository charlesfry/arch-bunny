#!/bin/bash

signal_waybar() {
  if [[ -n "$1" ]]; then
    pkill "-RTMIN+$1" waybar
  fi
}

# Re-exec the calling script inside a floating terminal when it does not have
# one. Call as: require_terminal "$0" "$@"
#
# Anything that needs sudo needs a terminal to prompt on. This setup runs no
# polkit authentication agent on purpose -- polkit-gnome is installed but
# nothing autostarts it -- because that is a resident process standing by for
# something wanted a few times a month. The terminal appears only when a
# privileged helper is actually run.
require_terminal() {
  [[ -t 0 ]] && return 0
  exec bunny-launch-term-float "$@"
}
