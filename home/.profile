# Set default editor
export EDITOR="nvim"
export VISUAL="$EDITOR"

# Machine-local defaults chosen through bunny-menu-defaults. Sourced after the
# values above so a choice made there wins, and never tracked by git, so one
# machine's editor is not every machine's editor.
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bunny/defaults" ]; then
  . "${XDG_CONFIG_HOME:-$HOME/.config}/bunny/defaults"
fi

# Suppress uwsm console output during session start
export UWSM_SILENT_START=1

# Add ~/.local/bin to PATH
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi

alias vi="nvim"

