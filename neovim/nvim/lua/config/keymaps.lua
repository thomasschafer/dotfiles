-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- Don't save deleted lines to clipboard
vim.keymap.set({ "n", "v" }, "d", '"_d', { noremap = true })
vim.keymap.set({ "n", "v" }, "<leader>d", '"+d', { noremap = true })
vim.keymap.set({ "n", "v" }, "D", '"_D', { noremap = true })
vim.keymap.set({ "n", "v" }, "c", '"_c', { noremap = true })
vim.keymap.set({ "n", "v" }, "C", '"_C', { noremap = true })
vim.keymap.set({ "n", "v" }, "S", '"_S', { noremap = true })
vim.keymap.set("n", "x", '"_x', { noremap = true })
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

-- Move buffers left and right using option + left/right
vim.keymap.set({ "n", "v" }, "<M-B>", "<cmd>BufferLineMovePrev<cr>", { desc = "Move buffer left" })
vim.keymap.set({ "n", "v" }, "<M-F>", "<cmd>BufferLineMoveNext<cr>", { desc = "Move buffer right" })

-- Move to left or right buffer with option + h/l
vim.keymap.set({ "n", "v" }, "<M-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
vim.keymap.set({ "n", "v" }, "<M-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })

-- Create cursors with vim-visual-multi without triggering macOS shortcuts
vim.api.nvim_set_keymap(
  "n",
  "<F7>",
  ":call vm#commands#add_cursor_down(0, v:count1)<CR>",
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
  "n",
  "<F8>",
  ":call vm#commands#add_cursor_up(0, v:count1)<CR>",
  { noremap = true, silent = true }
)

-- Commenting
vim.keymap.set({ "n", "x" }, "<leader>.", function()
  return require("vim._comment").operator()
end, { expr = true, desc = "Toggle comment" })
vim.keymap.set("n", "<leader>.", function()
  return require("vim._comment").operator() .. "_"
end, { expr = true, desc = "Toggle comment line" })

-- File picker
vim.keymap.set({ "n", "x" }, "<leader>a", LazyVim.telescope("files"), { desc = "Find Files (Root Dir)" })

-- Resize windows
vim.keymap.set("n", "<M-,>", "<cmd>resize +10<cr>", { desc = "Increase window height" })
vim.keymap.set("n", "<M-m>", "<cmd>resize -10<cr>", { desc = "Decrease window height" })
vim.keymap.set("n", "<M-n>", "<cmd>vertical resize -20<cr>", { desc = "Decrease window width" })
vim.keymap.set("n", "<M-.>", "<cmd>vertical resize +20<cr>", { desc = "Increase window width" })

-- Remove trailing spaces
vim.keymap.set("n", "<leader>cz", function()
  MiniTrailspace.trim()
end, { desc = "Remove trailing spaces" })
