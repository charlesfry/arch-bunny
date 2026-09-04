-- Bunny notebook stack (CHOICES `jupyter-in-neovim` + `editor`; mechanisms
-- proven in benchmarks/4.15 on Arch and re-proven on the NixOS port).
-- molten (Jupyter kernels) + image.nvim (kitty graphics) render plots,
-- images, and typeset equations inline; render-markdown (from LazyVim's
-- markdown extra) decorates the buffer.
return {
  {
    "3rd/image.nvim",
    lazy = false,
    opts = {
      backend = "kitty",
      processor = "magick_cli", -- imagemagick CLI; avoids the luarocks magick binding
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
    -- (CHOICES `jupyter-in-neovim`, gotcha 2)
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

      -- molten_virt_lines_off_by_1 was tried here 2026-08-27 for the rerun-clipping
      -- bug and made it worse (image popped out with no reserved space at all): it
      -- shrinks molten's own virt_lines reservation by one, but image.nvim reserves
      -- the image's space independently, uncoordinated with molten's number.
      -- Reverted; see CHOICES.md `editor` for the traced root cause.

      -- Fail loudly, not silently: the predecessor's silent image gate is why
      -- gripe #3 went undiagnosed for years. Expected absence (TTY/SSH) gets one
      -- quiet INFO line with the reason; :checkhealth bunny carries the on-demand
      -- diagnosis.
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
