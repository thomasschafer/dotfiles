-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Normal mode mappings
vim.api.nvim_set_keymap("n", "d", '"_d', { noremap = true })
vim.api.nvim_set_keymap("n", "D", '"_D', { noremap = true })
vim.api.nvim_set_keymap("n", "c", '"_c', { noremap = true })
vim.api.nvim_set_keymap("n", "C", '"_C', { noremap = true })
vim.api.nvim_set_keymap("n", "x", '"_x', { noremap = true })
vim.api.nvim_set_keymap("n", "S", '"_S', { noremap = true })
vim.api.nvim_set_keymap("n", "<C-q>", "<leader>bd", { noremap = true, silent = true })

-- Visual mode mappings
vim.api.nvim_set_keymap("v", "d", '"_d', { noremap = true })
vim.api.nvim_set_keymap("v", "D", '"_D', { noremap = true })
vim.api.nvim_set_keymap("v", "c", '"_c', { noremap = true })
vim.api.nvim_set_keymap("v", "C", '"_C', { noremap = true })
vim.api.nvim_set_keymap("v", "p", '"_dP', { noremap = true })
vim.api.nvim_set_keymap("v", "P", '"_dP', { noremap = true })
vim.api.nvim_set_keymap("v", "S", '"_S', { noremap = true })
