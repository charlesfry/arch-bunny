-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- gq on python imports: wrap `from x import (...)` one name per line.
-- Expands the range to the whole statement (matching paren) before ruff runs.
function _G.PyImportFormat()
  local buf = 0
  local first = vim.v.lnum
  local last = first + vim.v.count - 1
  local function depth_of(lines, depth)
    for _, l in ipairs(lines) do
      for c in l:gmatch("[()]") do depth = depth + (c == "(" and 1 or -1) end
    end
    return depth
  end
  -- start of statement: walk up while lines are indented continuations
  while first > 1 and vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1]:match("^%s") do
    first = first - 1
  end
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local depth = depth_of(lines, 0)
  -- end of statement: walk down until the parens balance
  while depth > 0 and last < vim.api.nvim_buf_line_count(buf) do
    last = last + 1
    local l = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)
    table.insert(lines, l[1])
    depth = depth_of(l, depth)
  end
  local cmd = "ruff check --fix --select=I001 --exit-zero --quiet --stdin-filename=gq.py - | ruff format --quiet -"
  local out = vim.fn.systemlist(cmd, require("pyimports").explode(lines))
  if vim.v.shell_error ~= 0 then
    vim.notify("ruff failed:\n" .. table.concat(out, "\n"), vim.log.levels.WARN)
    return 0
  end
  vim.api.nvim_buf_set_lines(buf, first - 1, last, false, out)
  return 0 -- done here; 0 stops gq from running its own formatting
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.bo.formatexpr = "v:lua.PyImportFormat()"
  end,
})
