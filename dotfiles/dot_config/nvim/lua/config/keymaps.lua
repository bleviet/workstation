-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Set up keymaps for VS Code-like debugging experience
local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

map("n", "<F5>", "<Cmd>lua require'dap'.continue()<CR>", opts)
map("n", "<F9>", "<Cmd>lua require'dap'.toggle_breakpoint()<CR>", opts)
map("n", "<F10>", "<Cmd>lua require'dap'.step_over()<CR>", opts)
map("n", "<F11>", "<Cmd>lua require'dap'.step_into()<CR>", opts)
map("n", "<S-F11>", "<Cmd>lua require'dap'.step_out()<CR>", opts)
map("n", "<F6>", "<Cmd>lua require'dap'.restart()<CR>", opts)
map("n", "<F8>", "<Cmd>lua require'dap'.terminate()<CR>", opts)
