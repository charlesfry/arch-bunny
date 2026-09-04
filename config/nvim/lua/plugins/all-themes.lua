return {
  -- Load all theme plugins but don't apply them
  -- This ensures all colorschemes are available for hot-reloading
  {
    "ribru17/bamboo.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = true,
    priority = 1000,
  },
  {
    "sainnhe/everforest",
    lazy = true,
    priority = 1000,
  },
  {
    "kepano/flexoki-neovim",
    lazy = true,
    priority = 1000,
  },
  {
    "ellisonleao/gruvbox.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "rebelot/kanagawa.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "tahayvr/matteblack.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "loctvl842/monokai-pro.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "shaunsingh/nord.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = true,
    priority = 1000,
  },
  {
    "folke/tokyonight.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "olimorris/onedarkpro.nvim",
    lazy = true,
    priority = 1000,
  },
  {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
      require('onedark').setup  {
          -- Main options --
          style = 'deep', -- Default theme style. Choose between 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer' and 'light'
          transparent = false,  -- Show/hide background
          term_colors = true, -- Change terminal color as per the selected theme style
          ending_tildes = false, -- Show the end-of-buffer tildes. By default they are hidden
          cmp_itemkind_reverse = false, -- reverse item kind highlights in cmp menu

          -- toggle theme style ---
          toggle_style_key = "<leader>ts", -- keybind to toggle theme style. Leave it nil to disable it, or set it to a string, for example "<leader>ts"
          toggle_style_list = {'deep', 'dark', 'darker', 'cool', 'warm', 'warmer'}, -- List of styles to toggle between

          -- Change code style ---
          -- Options are italic, bold, underline, none
          -- You can configure multiple style with comma separated, For e.g., keywords = 'italic,bold'
          code_style = {
              comments = 'italic',
              keywords = 'none',
              functions = 'none',
              strings = 'none',
              variables = 'none'
          },

          -- Lualine options --
          lualine = {
              transparent = false, -- lualine center bar transparency
          },

          -- Custom Highlights --
          colors = {}, -- Override default colors
          highlights = {}, -- Override highlight groups

          -- Plugins Config --
          diagnostics = {
              darker = true, -- darker colors for diagnostic
              undercurl = true,   -- use undercurl instead of underline for diagnostics
              background = true,    -- use background color for virtual text
          },
      }
      require('onedark').load()
    end
  },
}
