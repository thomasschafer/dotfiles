-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Setup plugins
require("lazy").setup({
  {
    'akinsho/toggleterm.nvim',
    version = "*",
    config = function()
      require("toggleterm").setup{}
    end
  }
})


-- Misc
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.wo.number = true
vim.wo.relativenumber = true


-- Scooter
local Terminal = require("toggleterm.terminal").Terminal
local scooter_term = Terminal:new({
    cmd = "scooter",
    direction = "float",
    close_on_exit = true,
})

_G.EditLineFromScooter = function(file_path, line)
    pcall(function() scooter_term:close() end)

    local current_path = vim.fn.expand("%:p")
    local target_path = vim.fn.fnamemodify(file_path, ":p")

    if current_path ~= target_path then
        vim.cmd.edit(vim.fn.fnameescape(file_path))
    end

    vim.api.nvim_win_set_cursor(0, { line, 0 })
end

vim.keymap.set('n', '<leader>s', function()
    scooter_term:toggle()
end, { desc = 'Toggle scooter' })


_G.ToggleScooterSearchText = function(search_text)
    local escaped_search_text = vim.fn.shellescape(search_text:gsub("\r?\n", " "))
    local search_term = Terminal:new({
        cmd = "scooter --search-text " .. escaped_search_text,
        direction = "float",
        close_on_exit = true,
    })
    search_term:open()
end

vim.keymap.set('v', '<leader>r',
    '"ay<ESC><cmd>lua ToggleScooterSearchText(vim.fn.getreg("a"))<CR>',
    { desc = 'Search selected text in scooter' })
