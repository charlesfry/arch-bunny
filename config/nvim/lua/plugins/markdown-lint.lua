-- LazyVim's markdown extra lints with markdownlint-cli2, which lights up MD012 on
-- notebook-style markdown. CHOICES.md `editor` review item, author's word: tune
-- the specific rule, keep the linter otherwise active.
--
-- markdownlint-cli2's own upward directory-tree config search does NOT apply to
-- nvim-lint's stdin invocation (verified: a config at $HOME was silently ignored
-- when linting a file in a subdirectory via stdin, and worked immediately once
-- passed via --config). So this points it at our shipped config by explicit path,
-- via LazyVim's own `opts.linters` override.
--
-- The key must be the hyphenated form. nvim-lint's `lint.linters` table is
-- metatable-backed: `__index` does a literal `require('lint.linters.' .. key)`
-- with no underscore normalization. The real file is
-- lint/linters/markdownlint-cli2.lua, so `markdownlint_cli2` would resolve to
-- nothing, merge as a dead entry never referenced by `linters_by_ft.markdown`, and
-- silently fail to override anything.
return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", vim.fn.stdpath("config") .. "/.markdownlint.jsonc", "-" },
        },
      },
    },
  },
}
