-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- Map :l to escape in insert, command, visual, and terminal modes
vim.keymap.set("i", ";l", "<Esc>")
vim.keymap.set("c", ";l", "<Esc>")
vim.keymap.set("v", ";l", "<Esc>")
vim.keymap.set("n", ";l", "<Esc>")
vim.keymap.set("t", ";l", "<C-\\><C-n>")
vim.keymap.set("i", ";L", "<Esc>")
vim.keymap.set("c", ";L", "<Esc>")
vim.keymap.set("v", ";L", "<Esc>")
vim.keymap.set("t", ";L", "<C-\\><C-n>")
vim.keymap.set("n", ";L", "<Esc>")

vim.keymap.set("i", ";a", "->")
vim.keymap.set("i", ";A", "->")

-- Math - increment/decrement
vim.keymap.set("n", "+", "<C-a>", { desc = "Increment number" })
vim.keymap.set("n", "-", "<C-x>", { desc = "Decrement number" })

-- Select all
vim.keymap.set("n", "<C-a>", "gg<S-v>G", { desc = "Select all" })

-- Misc
-- <leader>ts is used by onedark to toggle the theme
vim.keymap.set("n", "<leader>dl", "d$")

-- Trim trailing whitespace across the whole buffer, preserving cursor/view and
-- the search history (keeppatterns). Exposed as both a keymap and :Trim.
local function trim_trailing_whitespace()
  local view = vim.fn.winsaveview()
  vim.cmd([[keeppatterns %s/\s\+$//e]])
  vim.fn.winrestview(view)
end
vim.api.nvim_create_user_command("Trim", trim_trailing_whitespace, { desc = "Trim trailing whitespace" })
vim.keymap.set("n", "<leader>tw", trim_trailing_whitespace, { desc = "Trim trailing whitespace (whole buffer)" })
vim.keymap.set("n", "<leader>pi", function()
  -- get current line
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]

  -- append comment if it's not already there
  if not line:match("# pyright: ignore") then
    vim.api.nvim_buf_set_lines(0, line_nr - 1, line_nr, false, { line .. "  # pyright: ignore" })
  end
end, { silent = true, desc = "Append # pyright: ignore to current line" })

