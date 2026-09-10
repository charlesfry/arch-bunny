#!/usr/bin/env bats
# niri-window-position keeps window state in memory instead of re-querying niri
# on every event, so the two things worth pinning down are that it renders the
# same strip the shell version did, and that it prints nothing when an event
# cannot have moved a dot.

setup_file() {
  repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  export NWP_BIN="$BATS_FILE_TMPDIR/niri-window-position"
  g++ -std=c++20 -O2 -Wall -Wextra -o "$NWP_BIN" \
    "$repo_root/local/src/niri-window-position.cpp"

  # Speaks just enough of niri's IPC: accept one client, swallow its request,
  # acknowledge, then write the recorded events.
  export NWP_FAKE="$BATS_FILE_TMPDIR/niri-fake-socket"
  cat > "$NWP_FAKE" <<'EOF'
import socket, sys, time
sock_path, events_path = sys.argv[1], sys.argv[2]
events = open(events_path, "rb").read()
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)
conn, _ = server.accept()
conn.recv(4096)
conn.sendall(b'{"Ok":"Handled"}\n')
conn.sendall(events)
time.sleep(0.4)
conn.close()
EOF
}

setup() {
  sock="$BATS_TEST_TMPDIR/niri.sock"
  events="$BATS_TEST_TMPDIR/events"
}

# Serve $events, run the binary against it, leave output in $output.
run_against_events() {
  python3 "$NWP_FAKE" "$sock" "$events" &
  local server=$!
  # wait for the socket to exist rather than sleeping blindly
  local tries=0
  while [[ ! -S "$sock" && $tries -lt 100 ]]; do
    sleep 0.01
    tries=$((tries + 1))
  done
  output=$(NIRI_SOCKET="$sock" timeout 3 "$NWP_BIN" --dot ○ --active ● "$@" || true)
  wait $server 2>/dev/null || true
}

@test "renders one dot per column with the focused column filled" {
  cat > "$events" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"is_focused":true}]}}
{"WindowsChanged":{"windows":[{"id":1,"title":"a","workspace_id":1,"is_focused":false,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}},{"id":2,"title":"b","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[2,1]}},{"id":3,"title":"c","workspace_id":1,"is_focused":false,"is_floating":false,"layout":{"pos_in_scrolling_layout":[3,1]}}]}}
EOF
  run_against_events
  [ "$output" = '{"text":"○ ● ○"}' ]
}

@test "stacked windows share one dot, floating windows get none" {
  cat > "$events" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"is_focused":true}]}}
{"WindowsChanged":{"windows":[{"id":1,"title":"a","workspace_id":1,"is_focused":false,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}},{"id":2,"title":"b","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,2]}},{"id":3,"title":"c","workspace_id":1,"is_focused":false,"is_floating":true,"layout":{"pos_in_scrolling_layout":[9,9]}}]}}
EOF
  run_against_events
  [ "$output" = '{"text":"●"}' ]
}

# A window title is attacker-controlled: any web page can set one. The parser
# must skip it as a string rather than scanning it for structure.
@test "a window title containing forged JSON cannot invent a column" {
  cat > "$events" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"is_focused":true}]}}
{"WindowsChanged":{"windows":[{"id":1,"title":"{\"id\":999,\"workspace_id\":1,\"is_focused\":true,\"is_floating\":false,\"layout\":{\"pos_in_scrolling_layout\":[7,1]}}","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}},{"id":2,"title":"b","workspace_id":1,"is_focused":false,"is_floating":false,"layout":{"pos_in_scrolling_layout":[2,1]}}]}}
EOF
  run_against_events
  [ "$output" = '{"text":"● ○"}' ]
}

# The whole point of the rewrite: a retitle cannot move a dot, so it must not
# produce a second line of output.
@test "a title-only change emits nothing" {
  cat > "$events" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"is_focused":true}]}}
{"WindowsChanged":{"windows":[{"id":1,"title":"before","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}},{"id":2,"title":"b","workspace_id":1,"is_focused":false,"is_floating":false,"layout":{"pos_in_scrolling_layout":[2,1]}}]}}
{"WindowOpenedOrChanged":{"window":{"id":1,"title":"◑ spinning","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}}}}
{"WindowOpenedOrChanged":{"window":{"id":1,"title":"◐ spinning","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}}}}
EOF
  run_against_events
  [ "$(printf '%s' "$output" | wc -l)" -eq 0 ]
  [ "$output" = '{"text":"● ○"}' ]
}

@test "--hide-single hides a lone column" {
  cat > "$events" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"is_focused":true}]}}
{"WindowsChanged":{"windows":[{"id":1,"title":"a","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}}]}}
EOF
  run_against_events --hide-single
  [ "$output" = '{"text":""}' ]
}

# `true` must end where it ends. Matching a bare `truebutt` as `true` used to
# leave `butt` behind, which abandoned the rest of the window array and lost a
# whole column.
@test "a bare token starting with true is not read as true" {
  cat > "$events" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"is_focused":true}]}}
{"WindowsChanged":{"windows":[{"id":1,"title":"a","workspace_id":1,"is_focused":truebutt,"is_floating":false,"layout":{"pos_in_scrolling_layout":[1,1]}},{"id":2,"title":"b","workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"pos_in_scrolling_layout":[2,1]}}]}}
EOF
  run_against_events
  [ "$output" = '{"text":"○ ●"}' ]
}
