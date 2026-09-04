-- LazyVim's own ui.lua turns on snacks.nvim's smooth-scroll animation by
-- default (`scroll = { enabled = true }`), which makes Ctrl-D/Ctrl-U glide
-- instead of jump. That fights CLAUDE.md priority 2a directly (perceived
-- latency, keybind to result) and the author asked for it off outright
-- (2026-08-27): "there shouldnt be a scroll because that just slows me down."
return {
  {
    "folke/snacks.nvim",
    opts = { scroll = { enabled = false } },
  },
}
