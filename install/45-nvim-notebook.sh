#!/bin/bash

# Host side of the Neovim notebook stack (molten-nvim + image.nvim + jupytext).
#
# The Lua config needs no step here: config/nvim is stowed by 20-dotfiles.sh and
# lazy.nvim bootstraps its own plugins on first launch. What is left is the
# interpreter behind `vim.g.python3_host_prog` (config/nvim/lua/config/options.lua):
# a venv with the packages molten needs, a registered kernel, the runtime dir
# molten writes to but never creates, and the rplugin manifest that turns
# molten's Python commands into real `:Molten*` ex-commands.
#
# The venv is deliberately conda-independent: kernels come and go with conda
# envs, but the Neovim provider must not.

NVIM_VENV="$HOME/.venvs/neovim"
NVIM_VENV_PYTHON="$NVIM_VENV/bin/python"
JUPYTER_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/jupyter"

# pillow installs under the import name PIL - the one case where the pip name
# and the import name differ, so map rather than assume.
NVIM_PROVIDER_PACKAGES=(pynvim jupyter_client jupytext ipykernel matplotlib pillow sympy)
provider_import_name() {
  case "$1" in
  pillow) printf 'PIL' ;;
  *) printf '%s' "$1" ;;
  esac
}

provider_packages_importable() {
  local package
  for package in "${NVIM_PROVIDER_PACKAGES[@]}"; do
    "$NVIM_VENV_PYTHON" -c "import $(provider_import_name "$package")" >/dev/null 2>&1 || return 1
  done
}

step "Preparing the Neovim Python provider"

if [[ ! -x $NVIM_VENV_PYTHON ]]; then
  run_logged "Creating provider venv at $NVIM_VENV" \
    python3 -m venv "$NVIM_VENV"
fi

if provider_packages_importable; then
  log "Provider packages already present: ${NVIM_PROVIDER_PACKAGES[*]}"
else
  run_logged "Installing provider packages" \
    "$NVIM_VENV_PYTHON" -m pip install --upgrade --quiet pip
  run_logged "Installing ${NVIM_PROVIDER_PACKAGES[*]}" \
    "$NVIM_VENV_PYTHON" -m pip install --quiet "${NVIM_PROVIDER_PACKAGES[@]}"
fi

if ! provider_packages_importable; then
  error "Provider packages do not import from $NVIM_VENV"
  return 1
fi

# pnglatex is copied, never pip-installed: the PyPI package of that name is the
# abandoned one this module replaces (it is broken on Python >= 3.13). molten
# hardcodes `from pnglatex import pnglatex` for text/latex output chunks, so the
# import name is all that has to match.
PNGLATEX_SOURCE="$BUNNY_PATH/assets/nvim/pnglatex.py"
if [[ ! -f $PNGLATEX_SOURCE ]]; then
  error "LaTeX renderer not found: $PNGLATEX_SOURCE"
  return 1
fi
PNGLATEX_TARGET="$("$NVIM_VENV_PYTHON" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')/pnglatex.py"
if ! cmp -s "$PNGLATEX_SOURCE" "$PNGLATEX_TARGET"; then
  run_logged "Installing the LaTeX output renderer" \
    install -Dm644 "$PNGLATEX_SOURCE" "$PNGLATEX_TARGET"
fi
if ! "$NVIM_VENV_PYTHON" -c 'from pnglatex import pnglatex' >/dev/null 2>&1; then
  error "pnglatex does not import from $NVIM_VENV"
  return 1
fi

# molten writes connection files here but never creates the directory, so on a
# machine that has never run Jupyter :MoltenInit fails with ENOENT.
mkdir -p "$JUPYTER_DATA_DIR/runtime"

if [[ ! -d $JUPYTER_DATA_DIR/kernels/bunny ]]; then
  run_logged "Registering the 'bunny' Jupyter kernel" \
    "$NVIM_VENV_PYTHON" -m ipykernel install --user --name bunny --display-name "bunny (nvim)"
fi

# molten is a remote (Python host) plugin: its :Molten* commands come from the
# generated rplugin manifest, not from Lua. The manifest is written against
# whichever provider was current when it was generated, so it has to be rebuilt
# here, after the venv exists. Headless so it works from the installer.
run_logged "Registering molten's remote plugin commands" \
  nvim --headless +UpdateRemotePlugins +qa

if ! nvim --headless '+lua if vim.fn.exists(":MoltenInit") ~= 2 then vim.cmd("cq") end' +qa >/dev/null 2>&1; then
  error "MoltenInit is still missing after :UpdateRemotePlugins"
  return 1
fi

verify_user_ownership "$NVIM_VENV" "$JUPYTER_DATA_DIR"
success "Neovim notebook stack ready (:checkhealth bunny for a live diagnosis)"
