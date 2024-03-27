-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Don't save deleted lines to clipboard
vim.keymap.set({ "n", "v" }, "d", '"_d', { noremap = true })
vim.keymap.set({ "n", "v" }, "D", '"_D', { noremap = true })
vim.keymap.set({ "n", "v" }, "c", '"_c', { noremap = true })
vim.keymap.set({ "n", "v" }, "C", '"_C', { noremap = true })
vim.keymap.set({ "n", "v" }, "S", '"_S', { noremap = true })
vim.keymap.set("n", "x", '"_x', { noremap = true })
vim.keymap.set("v", "D", '"_D', { noremap = true })
vim.keymap.set("v", "p", '"_dP', { noremap = true })
vim.keymap.set("v", "P", '"_dP', { noremap = true })

vim.keymap.set({ "n", "i" }, "<F4>", ":cnext<CR>", { noremap = true, silent = true })
vim.keymap.set({ "n", "i" }, "<F16>", ":cprev<CR>", { noremap = true, silent = true }) -- <S-F4>
vim.keymap.set({ "n", "i" }, "<F3>", "<cmd>Telescope resume<cr>", { desc = "Resume" })
vim.keymap.set({ "n", "i" }, "<F10>", "<cmd>qa<cr>", { desc = "Quit All" })
