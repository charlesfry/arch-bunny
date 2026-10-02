-- isort before ruff: force_grid_wrap=2 explodes any multi-name import into
-- parens, then ruff's magic trailing comma keeps it that way.
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = { python = { "isort", "ruff_format" } },
      formatters = {
        isort = { prepend_args = { "--profile", "black", "--force-grid-wrap", "2" } },
      },
    },
  },
  { "mason-org/mason.nvim", opts = { ensure_installed = { "isort" } } },
}
