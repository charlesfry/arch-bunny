-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = true
vim.g.autoformat = false

-- Dedicated, conda-independent Python host for remote plugins (molten). Created
-- by install/45-nvim-notebook.sh at ~/.venvs/neovim. Only point at it when it exists,
-- so a machine without the Jupyter stack falls back to the default provider.
local nvim_py = vim.fn.expand("~/.venvs/neovim/bin/python")
if vim.fn.executable(nvim_py) == 1 then
  vim.g.python3_host_prog = nvim_py
end
