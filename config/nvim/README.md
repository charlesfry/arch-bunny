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
| `molten-nvim` (`molten.lua`) | run cells against a Jupyter kernel | **`<S-Enter>` run the fence under the cursor**, `]m`/`[m` next/prev cell, `<leader>mi` init kernel, `<leader>mo` enter output, `<leader>ms`/`<leader>mh` show/hide |
| `jupytext.nvim` (`molten.lua`) | edit `.ipynb` as markdown | automatic on open |
| `image.nvim` (`molten.lua`) | inline plots and LaTeX — **kitty only** | automatic |
| `csvview.nvim` (`data.lua`) | aligned CSV/TSV columns | `<leader>uV` |
| `render-markdown.nvim` (`data.lua`) | pretty in-buffer markdown | `<leader>um` |
| `vim-dadbod*` (sql extra) | query Postgres etc. from nvim | `<leader>D` |
| `neotest` (test extra + python adapter) | run/debug pytest inline | `<leader>t` group |

Linting/formatting: the python extra already wires **ruff** (LSP) alongside
pyright; `vim.g.autoformat = false`, so formatters run only when invoked.

## One-time setup for the Jupyter stack

The installer's `install/45-nvim-notebook.sh` phase does all of it, and is safe
to re-run on its own from the arch-bunny checkout. It creates a dedicated,
conda-independent Python host at `~/.venvs/neovim` (pynvim, jupyter_client,
jupytext, ipykernel, matplotlib, pillow, sympy) — `options.lua` points
`g:python3_host_prog` at it when present — installs our `pnglatex` module for
LaTeX output, registers a `bunny` kernel, creates the Jupyter runtime dir, and
regenerates the remote-plugin manifest.

The system side is declared in `install/packages`: `imagemagick` (image.nvim's
`magick_cli` processor) and `texlive-basic texlive-latex texlive-binextra`
(`latex` + `dvipng`, which `pnglatex` shells out to).

To add another conda env as a kernel:

```sh
conda activate <env> && pip install ipykernel
python -m ipykernel install --user --name <env>
```

In Neovim run `<leader>mi` (`:MoltenInit`) and pick the kernel, then `<S-Enter>`
inside a ```` ```python ```` fence.

Two things that silently break plots, both worth knowing:

- **Inline images require the kitty graphics protocol.** Everything else still
  works in another terminal; plots just do not render.
- **Do not call `matplotlib.use("Agg")` in a cell.** It replaces ipykernel's
  `matplotlib_inline` backend, and figures then come back as `text/plain` with
  no `image/png` for molten to draw.

`:checkhealth bunny` diagnoses the whole chain — terminal, provider venv, molten
commands, ImageMagick, TeX, and the Jupyter runtime dir.

> Molten is a *remote* (python-host) plugin, so it's loaded eagerly (`lazy = false`)
> rather than via `cmd`/`ft`/`keys` — lazy-loading deletes the manifest-provided
> commands and breaks `:Molten*`. If commands ever go missing (e.g. after an
> update), run `:UpdateRemotePlugins` and restart, or re-run
> `install/45-nvim-notebook.sh`.
