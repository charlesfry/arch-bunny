-- iron.nvim: send code to a live IPython REPL in a split — the core DS loop
-- (write, send, inspect, iterate) without leaving the editor. Self-contained
-- (no tmux needed) and works in any terminal. Needs `ipython` on PATH (per
-- conda env). Keymaps live under <leader>r.
return {
  {
    "Vigemus/iron.nvim",
    main = "iron.core",
    ft = { "python" },
    cmd = { "IronRepl", "IronFocus", "IronRestart" },
    opts = function()
      local view = require("iron.view")
      local common = require("iron.fts.common")
      return {
        config = {
          scratch_repl = true,
          repl_definition = {
            python = {
              command = { "ipython", "--no-autoindent" },
              format = common.bracketed_paste_python,
            },
          },
          repl_open_cmd = view.split.vertical.botright(0.4),
        },
        keymaps = {
          toggle_repl = "<leader>rr",
          restart_repl = "<leader>rR",
          send_motion = "<leader>rc",
          visual_send = "<leader>rc",
          send_file = "<leader>rf",
          send_line = "<leader>rl",
          send_until_cursor = "<leader>ru",
          send_mark = "<leader>rm",
          cr = "<leader>r<cr>",
          interrupt = "<leader>r<space>",
          exit = "<leader>rq",
          clear = "<leader>rx",
        },
        highlight = { italic = true },
        ignore_blank_lines = true,
      }
    end,
  },
}
