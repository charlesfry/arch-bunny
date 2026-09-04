# Interactive check
[[ $- != *i* ]] && return

# conda, lazy-loaded: defining a function is free, so shell startup pays nothing.
# conda.sh is sourced on first use and replaces this stub with the real function.
conda() {

  local sh="/opt/miniforge/etc/profile.d/conda.sh"
  if [ ! -f "$sh" ]; then
    echo "conda: not installed at $sh" >&2
    return 1
  fi
  unset -f conda
  source "$sh"
  conda "$@"
}

alias vi='nvim'

eval "$(direnv hook bash)"

# Machine-local overrides, never tracked by git (lives in $HOME, outside this repo).

[[ -f "$HOME/.personal.bashrc" ]] && source "$HOME/.personal.bashrc"


# Resolve the repo's default branch (handles main vs master). Prefers the
# remote's HEAD; falls back to whichever of main/master exists locally.
_git_default_branch() {
    local def
    def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    if [ -n "$def" ]; then
        echo "${def#origin/}"
    elif git show-ref --verify --quiet refs/heads/main; then
        echo main
    else
        echo master
    fi
}

gu() {
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    local default_branch
    default_branch=$(_git_default_branch)

    # Check for changes (including untracked) and stash if any
    STASHED=0
    if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        git stash -u
        STASHED=1
    fi
    git checkout "$default_branch"
    git pull
    git checkout "$current_branch"
    # Only pop if we actually stashed something
    if [ "$STASHED" -eq 1 ]; then
        git stash pop
    fi
    git status
}

gur() {
  gu
  git rebase "$(_git_default_branch)"
}

guri() {
  gu
  git rebase -i "$(_git_default_branch)"
}
