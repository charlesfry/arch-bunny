-- Remap keys for blink.cmp autocompletion plugin
return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        ["<CR>"] = {
          function(cmp)
            cmp.cancel()
            return false
          end,
          "fallback_to_mappings",
        },
        ["<Tab>"] = { "accept", "fallback" },
        ["<S-Tab>"] = { "select_next", "fallback" },
        ["<C-Tab>"] = { "select_prev", "fallback" },

        ["<Down>"] = { "select_next", "fallback" },
        ["<Up>"] = { "select_prev", "fallback" },
      },
    },
  },
}
