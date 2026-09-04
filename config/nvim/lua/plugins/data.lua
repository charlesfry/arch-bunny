-- Data-file ergonomics for DS work.
return {
  -- csvview: render CSV/TSV as aligned columns right in the buffer.
  {
    "hat0uma/csvview.nvim",
    ft = { "csv", "tsv" },
    cmd = { "CsvViewEnable", "CsvViewToggle" },
    opts = {
      view = { display_mode = "border" },
      parser = { comments = { "#" } },
    },
    keys = {
      { "<leader>uV", "<cmd>CsvViewToggle<cr>", desc = "Toggle CSV view" },
    },
  },
  -- render-markdown: pretty in-buffer markdown (notebooks-as-markdown, docs).
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "markdown" },
    opts = {},
    keys = {
      { "<leader>um", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Markdown render" },
    },
  },
}
