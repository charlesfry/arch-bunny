-- Extend LazyVim's built-in grug-far (search/replace across files from cwd).
--   <leader>sr  (LazyVim default) prefills a filter for the current file's extension.
--   <leader>sR  (added here) searches the entire cwd with no extension filter.
return {
  {
    "MagicDuck/grug-far.nvim",
    keys = {
      {
        "<leader>sR",
        function()
          require("grug-far").open({ transient = true })
        end,
        mode = { "n", "x" },
        desc = "Search and Replace (cwd, all files)",
      },
    },
  },
}
