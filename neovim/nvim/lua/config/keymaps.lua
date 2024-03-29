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

-- Copy file path to clipboard
local function copyPath(fullPath)
  return function()
    local filepath = vim.fn.expand(fullPath and "%:p" or "%")
    vim.fn.setreg("+", filepath) -- write to clippoard
  end
end

vim.keymap.set("n", "<leader>yc", copyPath(false), { desc = "Copy relative file path", noremap = true, silent = true })
vim.keymap.set("n", "<leader>yC", copyPath(true), { desc = "Copy full file path", noremap = true, silent = true })

-- LSP commands
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "<F24>", "<cmd>Telescope lsp_references<cr>", opts) -- <S-F12>
    vim.keymap.set("n", "<F2>", vim.lsp.buf.rename, opts)
  end,
})
