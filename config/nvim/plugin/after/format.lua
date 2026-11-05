-- Permanently set formatoptions for all filetypes
--   j  remove the comment leader when joining lines (J)
--   q  allow formatting comments with gq
--   l  don't break lines that were already longer than textwidth when insert began
--   n  recognize numbered lists when formatting (uses formatlistpat)
--   t  auto-wrap text using textwidth as you type
--   c  auto-wrap comments using textwidth, inserting the comment leader
--
-- Other flags to consider (not enabled):
--   r  insert the comment leader after <Enter> in insert mode
--   o  insert the comment leader after o or O in normal mode
--   /  with o, don't insert the leader for // comments after a statement
--   a  automatically reformat paragraphs on every edit (can be surprising)
--   w  trailing white space marks a paragraph continues on the next line
--   v  only break a line at a blank you typed this insert session
--   b  like v, but only if the blank was typed before the cursor's line start
--   m  also break at multibyte characters above 255 (useful for CJK)
--   M  don't insert a space before or after a multibyte character when joining
--   B  don't insert a space between two multibyte characters when joining
--   1  don't break a line after a one-letter word; break before it instead
--   2  use the indent of a paragraph's second line when formatting
--   p  don't break lines at single spaces that follow periods (keeps "e.g. ")
vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    vim.opt_local.formatoptions = "jqlntc"
  end,
})

