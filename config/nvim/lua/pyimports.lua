-- Ruff has no isort force_grid_wrap, so add a magic trailing comma to any
-- multi-name `from x import a, b`; ruff then explodes it one name per line.
-- ponytail: skips statements with comments or backslashes, and would also touch
-- a matching line inside a string literal; use a real parser if that bites.
local M = {}

function M.explode(lines)
  local out, i = {}, 1
  while i <= #lines do
    local l, j = lines[i], i
    -- join a parenthesized import spread over several lines
    if l:match("^%s*from%s+%S+%s+import%s*%(") and not l:find(")", 1, true) then
      while j < #lines and not lines[j]:find(")", 1, true) do
        j = j + 1
        l = l .. " " .. lines[j]
      end
    end
    local head, names = l:match("^(%s*from%s+%S+%s+import%s*)%(?([^()#\\]-),?%s*%)?%s*$")
    if names and names:find(",") then
      table.insert(out, head .. "(" .. vim.trim(names) .. ",)")
    else
      vim.list_extend(out, lines, i, j)
    end
    i = j + 1
  end
  return out
end

return M
