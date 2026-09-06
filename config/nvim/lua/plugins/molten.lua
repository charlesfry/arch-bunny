-- Bunny notebook stack.
-- molten (Jupyter kernels) + image.nvim (kitty graphics) render plots,
-- images, and typeset equations inline; render-markdown (from LazyVim's
-- markdown extra) decorates the buffer; jupytext opens .ipynb as markdown so
-- the same fence-based keymaps work in notebooks and plain .md alike.
--
-- Host side (provider venv, kernel, runtime dir, pnglatex): install/45-nvim-notebook.sh.
return {
  {
    -- .ipynb <-> markdown on read/write. Fences become the cells molten
    -- evaluates, so <S-Enter> below works identically in .md and .ipynb.
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    opts = {
      style = "markdown",
      output_extension = "md",
      force_ft = "markdown",
    },
  },
  {
    "3rd/image.nvim",
    lazy = false,
    opts = {
      backend = "kitty",
      processor = "magick_cli", -- imagemagick CLI; avoids the luarocks magick binding
      -- Bound image height so a figure always fits molten's reserved virt lines
      -- above; an unbounded plot overflows the reservation and the output text
      -- ends up drawn across it.
      max_height_window_percentage = 40,
      integrations = {
        -- renders ![]() images inline in markdown notebooks
        markdown = { enabled = true, clear_in_insert_mode = false },
      },
    },
  },
  {
    "benlubas/molten-nvim",
    -- rplugin commands come from the manifest at startup; lazy-loading
    -- deletes the stubs -> "Not an editor command: MoltenInit"
    lazy = false,
    version = "^1",
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_virt_lines = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_output_win_max_height = 40
      -- images render in the inline virt text ONLY. The default ("both")
      -- also draws them inside the <leader>mo float, stacking a second
      -- offset copy over every plot (author-reported, 2026-08-24).
      vim.g.molten_image_location = "virt"

      -- Reserve enough virtual lines for a whole figure. The default is 12, but a
      -- plot bounded to 40% of the window is ~20 rows, so molten drew its
      -- "Out[n]: Done" status at line 12 while image.nvim drew the full image from
      -- the top, landing the text across the middle of the plot. Keep this at or
      -- above the row count implied by max_height_window_percentage below.
      --
      -- molten_virt_lines_off_by_1 was tried for this 2026-08-27 and made it worse
      -- (image popped out with no reserved space at all). It shifts by one line;
      -- the mismatch here is the whole height of the image, so it was never the
      -- right knob.
      vim.g.molten_virt_text_max_lines = 30

      -- Fail loudly, not silently. Expected absence (TTY/SSH) gets one quiet
      -- INFO line with the reason; :checkhealth bunny carries the full diagnosis.
      local kitty = vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID ~= nil
      if not kitty then
        local reason = vim.env.SSH_TTY and "SSH session" or ("TERM=" .. (vim.env.TERM or "unset"))
        vim.schedule(function()
          vim.notify("molten: no kitty graphics (" .. reason .. ") — inline images off", vim.log.levels.INFO)
        end)
      end
    end,
    keys = {
      {
        "<S-Enter>",
        function()
          -- evaluate the markdown code fence under the cursor.
          -- ignore_injections: the cursor sits in the injected python tree;
          -- the fence node lives in the outer markdown tree
          local node = vim.treesitter.get_node({ ignore_injections = true })
          while node and node:type() ~= "fenced_code_block" do
            node = node:parent()
          end
          if not node then
            return vim.notify("molten: no code fence under cursor", vim.log.levels.WARN)
          end
          for child in node:iter_children() do
            if child:type() == "code_fence_content" then
              local srow, _, erow, _ = child:range() -- 0-based, end-exclusive
              return vim.fn.MoltenEvaluateRange(srow + 1, erow)
            end
          end
        end,
        mode = "n",
        desc = "Evaluate markdown fence",
      },
      -- cell navigation, vim's own bracket-motion convention (no collision
      -- with any LazyVim default; author-requested 2026-08-27).
      { "]m", "<cmd>MoltenNext<cr>", mode = "n", desc = "Next molten cell" },
      { "[m", "<cmd>MoltenPrev<cr>", mode = "n", desc = "Previous molten cell" },
      -- large outputs: enter the output window and scroll it like a buffer;
      -- q leaves. Leader-based on purpose: kitty owns the Ctrl+Shift chords.
      { "<leader>mi", "<cmd>MoltenInit<cr>", mode = "n", desc = "Init molten kernel (picker)" },
      { "<leader>mo", "<cmd>noautocmd MoltenEnterOutput<cr>", mode = "n", desc = "Enter/scroll molten output" },
      { "<leader>mh", "<cmd>MoltenHideOutput<cr>", mode = "n", desc = "Hide molten output" },
      { "<leader>ms", "<cmd>MoltenShowOutput<cr>", mode = "n", desc = "Show molten output" },
    },
  },
}
