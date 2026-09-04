return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = {
              analysis = {
                diagnosticSeverityOverrides = {
                  reportInvalidTypeForm = "none",
                },
              },
            },
          },
        },
      },
    },
  },
}
