-- explode_imports adds a magic trailing comma to multi-name imports, ruff
-- sorts them and keeps the comma, then ruff format puts one name per line.
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = { python = { "explode_imports", "ruff_organize_imports", "ruff_format" } },
      formatters = {
        explode_imports = {
          format = function(_, _, lines, callback)
            callback(nil, require("pyimports").explode(lines))
          end,
        },
      },
    },
  },
}
