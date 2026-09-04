# Neovim config

LazyVim-based. Beyond the LazyVim defaults + extras (`ai.copilot`, `neo-tree`,
`lang.python`, `lang.sql`, `test.core` — see `lazyvim.json`), this config adds a
data-science layer. Plugin specs live in `lua/plugins/`.

## AI

- **Copilot** (inline ghost-text completion) — kept; accept/cycle with `<M-]>` / `<M-[>`.
- **Claude Code** (`coder/claudecode.nvim`, `ai-claude.lua`) — agentic edits &
  diffs via the `claude` CLI. `<leader>a` group: `ac` toggle, `af` focus,
  `ar` resume, `aC` continue, `am` model, `ab` add buffer, `as` send selection
  (visual) / add file (tree), `aa`/`ad` accept/deny diff.

## Data science

| Plugin | What | Keys |
|--------|------|------|
| `venv-selector` (python extra, tuned in `python-venv.lua`) | pick conda env in `~/miniforge3/envs`; restarts LSP against it | `<leader>cv` |
| `iron.nvim` (`repl.lua`) | send code to an IPython REPL split | `<leader>r` group (`rr` toggle, `rl` line, `rc` motion/visual, `rf` file, `ru` to-cursor, `rq` quit) |
| `molten-nvim` (`jupyter.lua`) | run cells against a Jupyter kernel | `<leader>j` group (`ji` init, **`jj` run current cell**, `ja` run all cells, `jl` line, `je` selection, `jc` re-eval cell, `jo`/`jh` show/hide, `jd` delete) |
| `jupytext.nvim` | edit `.ipynb` as markdown | automatic on open |
| `image.nvim` | inline plots — **kitty/ghostty only** | automatic |
| `csvview.nvim` (`data.lua`) | aligned CSV/TSV columns | `<leader>uV` |
| `render-markdown.nvim` (`data.lua`) | pretty in-buffer markdown | `<leader>um` |
| `vim-dadbod*` (sql extra) | query Postgres etc. from nvim | `<leader>D` |
| `neotest` (test extra + python adapter) | run/debug pytest inline | `<leader>t` group |

Linting/formatting: the python extra already wires **ruff** (LSP) alongside
pyright; `vim.g.autoformat = false`, so formatters run only when invoked.

## One-time setup for the Jupyter stack

Run `scripts/neovim-deps.sh` (also run from `setup.sh`). It creates a dedicated,
conda-independent Python host at `~/.venvs/neovim` (pynvim, jupyter_client,
jupytext, cairosvg) — `options.lua` points `g:python3_host_prog` at it when
present. Then, per conda env you want as a kernel:

```sh
conda activate <env> && pip install ipykernel
python -m ipykernel install --user --name <env>
```

In Neovim run `:MoltenInit` and pick the kernel. **Inline images require the
kitty graphics protocol** — use kitty or ghostty; alacritty can't display them
(everything else still works, plots just won't render inline).

> Molten is a *remote* (python-host) plugin, so it's loaded eagerly (`lazy = false`)
> rather than via `cmd`/`ft`/`keys` — lazy-loading deletes the manifest-provided
> commands and breaks `:Molten*`. If commands ever go missing (e.g. after an
> update), run `:UpdateRemotePlugins` and restart, or re-run `scripts/neovim-deps.sh`.
