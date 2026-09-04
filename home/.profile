# Set default editor
export EDITOR="nvim"
export VISUAL="$EDITOR"

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

