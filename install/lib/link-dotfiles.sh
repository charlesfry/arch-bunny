#!/bin/bash
# Shared symlink logic for arch-bunny's dotfiles trees (home/, config/, local/).
# Meant to be `source`d from both install/20-dotfiles.sh (fresh install) and
# local/bin/bunny-migrate (restow), so this linking behavior is only written once.

# link_tree <source_dir> <target_dir>
#   source_dir: "home", "config", or "local" — read relative to the repo root.
#   target_dir: where those files should end up, e.g. "$HOME" or "$HOME/.config".
link_tree() {
  local source_dir=$1                        # e.g. "config" — which subtree to link from.
  local target_dir=$2                        # e.g. "$HOME/.config" — where it lands.
  local repo_source="$BUNNY_PATH/$source_dir" # absolute path to that subtree in the repo.

  # Walk every regular file under the source tree. -not -path/-name entries skip the
  # same things viacoffee's .stow-local-ignore skipped: git metadata, README/LICENSE
  # docs, and any directory literally named "theme" (build sources, not runtime config).
  find "$repo_source" -type f \
    -not -path '*/.git/*' -not -name '.git*' \
    -not -name 'README.*' -not -name 'LICENSE.*' \
    -not -path '*/theme/*' |
  while IFS= read -r source_file; do
    # Strip the repo-source prefix so "/…/config/nvim/init.lua" becomes "nvim/init.lua".
    local relative_path=${source_file#"$repo_source"/}
    local dest_file="$target_dir/$relative_path"

    # Create the real destination directory before linking into it. This is the part
    # that replaces Stow's --no-folding: every directory stays real, only the leaf
    # files become symlinks, so anything an app writes at runtime (a cache file, a
    # lockfile) lands as an ordinary untracked file, never inside the git repo itself.
    mkdir -p "$(dirname "$dest_file")"

    # A fresh Arch install sometimes leaves a real default file at this exact path
    # (e.g. a stock ~/.bashrc). A symlink can't be created where a real file already
    # is, so clear it first — but only if it's a real file, never touch an existing
    # symlink here (that's what the ln flags below are for).
    if [[ -f $dest_file && ! -L $dest_file ]]; then
      rm -f -- "$dest_file"
    fi

    # -s: make a symlink. -f: overwrite an existing symlink instead of erroring.
    # -n: treat an existing symlink as the thing to replace, not a directory to place
    # a new link inside. Together these make re-running link_tree a safe no-op.
    ln -sfn "$source_file" "$dest_file"
  done
}
