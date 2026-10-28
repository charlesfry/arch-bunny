-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = true
vim.opt.wrap = true
vim.opt.linebreak = true
vim.g.autoformat = true
-- set gw text width before wrapping. Default 79
vim.opt.textwidth = 79
-- also auto-wraps while typing; to stop that for code but keep it for comments:
-- vim.opt.formatoptions:remove("t")
-- Source a trusted per-project .nvim.lua
vim.o.exrc = true
-- open in-line linter errors when jumping to a line. default false.
vim.diagnostic.config({ jump = { float = true } })
-- Dedicated, conda-independent Python host for remote plugins (molten).
-- Only point at it when it exists,
-- so a machine without the Jupyter stack falls back to the default provider.
local nvim_py = vim.fn.expand("~/.venvs/neovim/bin/python")
if vim.fn.executable(nvim_py) == 1 then
  vim.g.python3_host_prog = nvim_py
end
