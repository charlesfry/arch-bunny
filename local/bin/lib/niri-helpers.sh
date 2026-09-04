#!/usr/bin/env bash
# Snapshot-based helpers for niri window management
# Intended to be sourced, not executed
#
# Call niri_init once to pre-fetch window/workspace/output state. Without it,
# each query function issues its own niri IPC request.

# App launcher used by niri_focus_or_spawn; override before sourcing if needed
NIRI_APP_LAUNCHER="${NIRI_APP_LAUNCHER:-uwsm-app}"

# -------------------------------------------------------------------
# Snapshot
# -------------------------------------------------------------------

# Pre-fetch all snapshots. Call this once at script start to avoid
# multiple IPC round-trips when using several query functions.
niri_init() {
  _NIRI_WINDOWS=$(niri msg --json windows)
  _NIRI_WORKSPACES=$(niri msg --json workspaces)
  _NIRI_OUTPUTS=$(niri msg --json outputs)
}

# Snapshot accessors. Return the pre-fetched snapshot if niri_init was
# called, otherwise fetch fresh from niri IPC.
#
# Don't add a write-back here: these always run in a pipe's subshell, so
# the assignment would be discarded. Only niri_init can fill the cache.
niri_windows_json() {
  echo "${_NIRI_WINDOWS:-$(niri msg --json windows)}"
}

niri_workspaces_json() {
  echo "${_NIRI_WORKSPACES:-$(niri msg --json workspaces)}"
}

niri_outputs_json() {
  echo "${_NIRI_OUTPUTS:-$(niri msg --json outputs)}"
}

# -------------------------------------------------------------------
# Internal helpers
# -------------------------------------------------------------------

# Send a niri action to each window ID read from stdin
# Usage: _niri_message_to_ids <action>
_niri_message_to_ids() {
  local action="$1"
  while read -r id; do
    niri msg action "$action" --id "$id"
  done
}

# -------------------------------------------------------------------
# Query primitives
# -------------------------------------------------------------------

# Return true if the given window ID is currently focused
niri_is_window_focused() {
  local window_id="$1"

  niri_windows_json |
    jq -e --argjson wid "$window_id" '
      any(.id == $wid and .is_focused)
    ' > /dev/null
}

# Return the ID of the focused window
niri_focused_window_id() {
  niri_windows_json |
    jq -r '.[] | select(.is_focused) | .id'
}

# Return the ID of the focused workspace
# Read from the workspaces snapshot so it still works on an empty workspace,
# where no window is focused.
niri_focused_workspace_id() {
  niri_workspaces_json |
    jq -r '.[] | select(.is_focused) | .id'
}

# Return all windows on a workspace as streamed JSON objects
# If no workspace ID is given, defaults to the focused workspace
niri_windows_on_workspace() {
  local ws_id="${1:-}"

  if [[ -z "$ws_id" ]]; then
    ws_id="$(niri_focused_workspace_id)"
  fi

  niri_windows_json |
    jq -c --argjson ws "$ws_id" '.[] | select(.workspace_id == $ws)'
}

# Return tiled windows on a workspace in scrolling-layout order.
# If no workspace ID is given, defaults to the focused workspace.
niri_tiled_windows_on_workspace_sorted() {
  niri_windows_on_workspace "$@" |
    jq -s '
      map(select(.is_floating | not))
      | sort_by([
          .layout.pos_in_scrolling_layout[0],
          .layout.pos_in_scrolling_layout[1]
        ])
      | .[]
    '
}

# Return windows matching a pattern in app_id or title as streamed JSON objects
niri_windows_matching() {
  local pattern="$1"

  niri_windows_json |
    jq -c --arg p "$pattern" '
      .[]
      | select(
          (.app_id // "" | test($p; "i")) or
          (.title  // "" | test($p; "i"))
        )
    '
}

# -------------------------------------------------------------------
# Window actions
# -------------------------------------------------------------------

# Close all windows
niri_close_all_windows() {
  niri_windows_json |
    jq -r '.[].id' |
    _niri_message_to_ids close-window
}

# Close all windows on a workspace (default: focused workspace)
niri_close_all_on_workspace() {
  niri_windows_on_workspace "$@" |
    jq -r '.id' |
    _niri_message_to_ids close-window
}

# Close all unfocused windows on a workspace (default: focused workspace)
niri_close_unfocused_on_workspace() {
  niri_windows_on_workspace "$@" |
    jq -r 'select(.is_focused | not) | .id' |
    _niri_message_to_ids close-window
}

# Close all windows matching a pattern
niri_close_matching() {
  local pattern="$1"
  niri_windows_matching "$pattern" |
    jq -r '.id' |
    _niri_message_to_ids close-window
}

# Focus an existing window matching a pattern, or spawn a new process
niri_focus_or_spawn() {
  local pattern="$1"
  shift

  local window_id
  # -s slurps the whole stream so first() can't close the pipe early and
  # hand jq a SIGPIPE under `set -o pipefail`
  window_id="$(niri_windows_matching "$pattern" | jq -r -s 'first(.[]).id // empty')"

  if [[ -n "$window_id" ]]; then
    niri msg action focus-window --id "$window_id"
  else
    # unquoted on purpose: launcher may include args
    $NIRI_APP_LAUNCHER -- "$@" &
  fi
}

# -------------------------------------------------------------------
# Named workspace navigation
# -------------------------------------------------------------------

# Return the name of the focused workspace (empty if unnamed)
niri_focused_workspace_name() {
  niri_workspaces_json |
    jq -r '.[] | select(.is_focused) | .name // empty'
}

# Return workspace JSON object(s) matching a name
niri_workspace_by_name() {
  local name="$1"
  niri_workspaces_json |
    jq -c --arg n "$name" '.[] | select(.name == $n)'
}

# -------------------------------------------------------------------
# Output-aware operations
# -------------------------------------------------------------------

# Return the name of the focused output
niri_focused_output() {
  niri_workspaces_json |
    jq -r '.[] | select(.is_focused) | .output'
}

# Return all workspaces on an output as streamed JSON objects
niri_workspaces_on_output() {
  local output="$1"
  niri_workspaces_json |
    jq -c --arg out "$output" '.[] | select(.output == $out)'
}

# Return all windows on an output as streamed JSON objects
niri_windows_on_output() {
  local output="$1"
  jq -cn \
    --argjson wins "$(niri_windows_json)" \
    --argjson ws "$(niri_workspaces_json)" \
    --arg out "$output" '
      ([$ws[] | select(.output == $out) | .id]) as $ws_ids
      | $wins[]
      | select(.workspace_id as $wid | $ws_ids | any(. == $wid))
    '
}
