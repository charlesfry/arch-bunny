-- :checkhealth bunny — on-demand diagnosis of the notebook stack. Each check is
-- a failure mode that has actually been hit on this hardware.
local M = {}

function M.check()
  local h = vim.health
  h.start("Bunny notebook stack")

  if vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID ~= nil then
    h.ok("kitty graphics terminal detected")
  else
    h.warn("not running in kitty — inline images are off (expected in a TTY or over SSH)")
  end

  local py = vim.g.python3_host_prog
  if py and vim.uv.fs_stat(py) then
    h.ok("python provider pinned: " .. py)
  else
    h.error("provider venv missing (~/.venvs/neovim) — molten/Jupyter cannot work", {
      "run install/45-nvim-notebook.sh from the arch-bunny checkout",
    })
  end

  -- image.nvim's magick_cli processor shells out to ImageMagick; without it
  -- every image chunk silently fails to draw.
  if vim.fn.executable("magick") == 1 then
    h.ok("ImageMagick present (image.nvim magick_cli processor)")
  else
    h.error("magick not on PATH — inline plots cannot be processed", { "sudo pacman -S imagemagick" })
  end

  -- text/latex output chunks go through our pnglatex module, which shells out
  -- to latex + dvipng. Missing TeX degrades LaTeX cells to raw source, nothing
  -- else, so this is a warning.
  local tex = vim.tbl_filter(function(b)
    return vim.fn.executable(b) == 0
  end, { "latex", "dvipng" })
  if #tex == 0 then
    h.ok("TeX toolchain present (LaTeX output renders as images)")
  else
    h.warn("missing " .. table.concat(tex, ", ") .. " — LaTeX cells fall back to raw text", {
      "sudo pacman -S texlive-basic texlive-latex texlive-binextra",
    })
  end

  if vim.fn.exists(":MoltenInit") == 2 then
    h.ok("molten commands registered")
  else
    h.error("MoltenInit absent — remote plugin manifest stale", { "run :UpdateRemotePlugins and restart" })
  end

  local rt = vim.fn.expand("~/.local/share/jupyter/runtime")
  if vim.uv.fs_stat(rt) then
    h.ok("jupyter runtime dir exists")
  else
    h.error("jupyter runtime dir missing — MoltenInit will fail with ENOENT", { "mkdir -p " .. rt })
  end
end

return M
