-- Teach venv-selector (provided by LazyVim's python extra, bound to <leader>cv)
-- to find your Miniforge/conda envs in ~/miniforge3/envs, not just project-local
-- .venv dirs. Picking one restarts pyright/ruff against that interpreter.
-- Needs `fd` on PATH (installed via pacman-packages.sh).
return {
  {
    "linux-cultist/venv-selector.nvim",
    -- The python extra only maps <leader>cv for ft=python. Add a global one so
    -- it also works in jupytext notebooks (ft=markdown) and other buffers.
    keys = {
      { "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select VirtualEnv" },
    },
    -- Custom searches go under `opts.search` (top level) and are MERGED with the
    -- built-ins. The built-in conda searches only look in ~/miniconda3 and
    -- ~/anaconda3 — neither exists here — so add Miniforge equivalents. Format
    -- mirrors the plugin's defaults: `$FD` is substituted with the fd binary.
    opts = {
      search = {
        home_venv = {
          command = "$FD 'bin/python$' ~/.venvs --no-ignore-vcs --full-path --color never"
        },
      },
    },
  },
}
