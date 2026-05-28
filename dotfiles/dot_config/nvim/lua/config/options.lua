-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Always return the current working directory for searches
vim.g.root_spec = { "cwd" }

-- replace telescope with fzf for picker
vim.g.lazyvim_picker = "fzf"

-- Disable auto comment insertion
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  command = "setlocal formatoptions-=c formatoptions-=r formatoptions-=o",
})

-- Set systemrdl filetype and syntax highlighting
vim.cmd([[
  augroup systemrdl
    autocmd!
    autocmd BufRead,BufNewFile *.rdl set filetype=systemrdl
    autocmd FileType systemrdl source ~/.config/nvim/syntax/systemrdl.vim
  augroup END
]])
