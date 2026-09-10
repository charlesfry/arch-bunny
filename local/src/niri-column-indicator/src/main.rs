use std::{
    collections::{BTreeMap, HashMap},
    io::{self, Write},
    thread,
    time::Duration,
};

use clap::{Parser, ValueEnum};
use niri_ipc::{socket::Socket, Event, Request, Response, Window as IpcWindow};

#[derive(Clone, Copy, ValueEnum)]
enum Layout {
    Horizontal,
    Vertical,
}

#[derive(Clone, Copy, ValueEnum)]
enum OutputFormat {
    Json,
    Plain,
}

#[derive(Parser)]
struct Config {
    #[arg(long, value_enum, default_value_t = Layout::Horizontal)]
    layout: Layout,

    #[arg(long, default_value = "○")]
    inactive: String,

    #[arg(long, default_value = "●")]
    active: String,

    #[arg(long)]
    hide_single: bool,

    #[arg(long, value_enum, default_value_t = OutputFormat::Json)]
    output: OutputFormat,
}

#[derive(Default, PartialEq, Eq)]
struct Window {
    workspace: Option<u64>,
    floating: bool,
    position: Option<(usize, usize)>,
}

#[derive(Default)]
struct State {
    windows: HashMap<u64, Window>,
    focused_window: Option<u64>,
    focused_workspace: Option<u64>,
    have_windows: bool,
}

fn is_visible(window: &Window, focused_workspace: Option<u64>) -> bool {
    focused_workspace.is_some_and(|id| {
        window.workspace == Some(id) && !window.floating && window.position.is_some()
    })
}

fn update_window(window: &IpcWindow, state: &mut State) -> bool {
    let current = Window {
        workspace: window.workspace_id,
        floating: window.is_floating,
        position: window.layout.pos_in_scrolling_layout,
    };
    let was_visible = state
        .windows
        .get(&window.id)
        .is_some_and(|old| is_visible(old, state.focused_workspace));
    let changed = state.windows.get(&window.id) != Some(&current);
    let focus_changed = window.is_focused && state.focused_window != Some(window.id);
    if focus_changed {
        state.focused_window = Some(window.id);
    }
    let is_visible = is_visible(&current, state.focused_workspace);
    state.windows.insert(window.id, current);

    focus_changed || (changed && (was_visible || is_visible))
}

fn handle_event(event: Event, state: &mut State) -> bool {
    match event {
        Event::WindowsChanged { windows } => {
            state.windows.clear();
            state.focused_window = None;
            state.have_windows = true;
            for window in &windows {
                update_window(window, state);
            }
            true
        }
        Event::WindowOpenedOrChanged { window } => update_window(&window, state),
        Event::WindowClosed { id } => {
            let was_visible = state
                .windows
                .get(&id)
                .is_some_and(|window| is_visible(window, state.focused_workspace));
            state.windows.remove(&id);
            if state.focused_window == Some(id) {
                state.focused_window = None;
                true
            } else {
                was_visible
            }
        }
        Event::WindowFocusChanged { id } => {
            if state.focused_window == id {
                false
            } else {
                state.focused_window = id;
                true
            }
        }
        Event::WindowLayoutsChanged { changes } => {
            let mut changed = false;
            for (id, layout) in changes {
                if let Some(window) = state.windows.get_mut(&id) {
                    let was_visible = is_visible(window, state.focused_workspace);
                    let position = layout.pos_in_scrolling_layout;
                    let layout_changed = window.position != position;
                    window.position = position;
                    changed |= layout_changed
                        && (was_visible || is_visible(window, state.focused_workspace));
                }
            }
            changed
        }
        Event::WorkspacesChanged { workspaces } => {
            let focused_workspace = workspaces
                .iter()
                .find(|workspace| workspace.is_focused)
                .map(|workspace| workspace.id);
            if state.focused_workspace == focused_workspace {
                false
            } else {
                state.focused_workspace = focused_workspace;
                true
            }
        }
        Event::WorkspaceActivated { id, focused } if focused => {
            if state.focused_workspace == Some(id) {
                false
            } else {
                state.focused_workspace = Some(id);
                true
            }
        }
        _ => false,
    }
}

fn render(config: &Config, state: &State) -> String {
    let mut columns = BTreeMap::new();

    for (&window_id, window) in &state.windows {
        let Some((column, _)) = window.position else {
            continue;
        };
        if !is_visible(window, state.focused_workspace) {
            continue;
        }

        let is_active = Some(window_id) == state.focused_window;
        columns
            .entry(column)
            .and_modify(|active| *active |= is_active)
            .or_insert(is_active);
    }

    if config.hide_single && columns.len() <= 1 {
        return String::new();
    }

    let separator = match config.layout {
        Layout::Horizontal => " ",
        Layout::Vertical => "\n",
    };
    let mut text = String::new();
    for (index, is_active) in columns.into_values().enumerate() {
        if index > 0 {
            text.push_str(separator);
        }
        text.push_str(if is_active {
            &config.active
        } else {
            &config.inactive
        });
    }
    text
}

fn emit(
    config: &Config,
    state: &State,
    previous: &mut Option<String>,
    force: bool,
) -> io::Result<()> {
    let text = render(config, state);
    if !force && previous.as_ref() == Some(&text) {
        return Ok(());
    }

    let stdout = io::stdout();
    let mut stdout = stdout.lock();
    match config.output {
        OutputFormat::Json => writeln!(
            stdout,
            "{{\"text\":{}}}",
            serde_json::to_string(&text).map_err(io::Error::other)?
        )?,
        OutputFormat::Plain => writeln!(stdout, "{text}")?,
    }
    stdout.flush()?;
    *previous = Some(text);
    Ok(())
}

const RECONNECT_DELAY: Duration = Duration::from_secs(1);

fn connect_event_stream() -> Option<Socket> {
    let mut socket = Socket::connect().ok()?;
    matches!(
        socket.send(Request::EventStream).ok()?,
        Ok(Response::Handled)
    )
    .then_some(socket)
}

fn main() {
    let config = Config::parse();
    let mut previous = None;

    loop {
        let Some(socket) = connect_event_stream() else {
            thread::sleep(RECONNECT_DELAY);
            continue;
        };
        let mut state = State::default();
        let mut first = true;
        let mut read_event = socket.read_events();
        while let Ok(event) = read_event() {
            if handle_event(event, &mut state) && state.have_windows {
                if emit(&config, &state, &mut previous, first).is_err() {
                    return;
                }
                first = false;
            }
        }
        thread::sleep(RECONNECT_DELAY);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> Config {
        Config {
            layout: Layout::Horizontal,
            inactive: "o".into(),
            active: "x".into(),
            hide_single: false,
            output: OutputFormat::Json,
        }
    }

    #[test]
    fn renders_one_sorted_indicator_per_column() {
        let state = State {
            windows: HashMap::from([
                (
                    1,
                    Window {
                        workspace: Some(1),
                        floating: false,
                        position: Some((2, 0)),
                    },
                ),
                (
                    2,
                    Window {
                        workspace: Some(1),
                        floating: false,
                        position: Some((0, 0)),
                    },
                ),
                (
                    3,
                    Window {
                        workspace: Some(1),
                        floating: false,
                        position: Some((2, 1)),
                    },
                ),
                (
                    4,
                    Window {
                        workspace: Some(2),
                        floating: false,
                        position: Some((1, 0)),
                    },
                ),
            ]),
            focused_window: Some(3),
            focused_workspace: Some(1),
            have_windows: true,
        };
        assert_eq!(render(&config(), &state), "o x");
    }

    #[test]
    fn hides_a_single_column_when_configured() {
        let mut config = config();
        config.hide_single = true;
        let state = State {
            windows: HashMap::from([(
                1,
                Window {
                    workspace: Some(1),
                    floating: false,
                    position: Some((0, 0)),
                },
            )]),
            focused_window: Some(1),
            focused_workspace: Some(1),
            have_windows: true,
        };
        assert_eq!(render(&config, &state), "");
    }
}
