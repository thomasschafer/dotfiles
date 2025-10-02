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
  lockfile = false,
  {
    'akinsho/toggleterm.nvim',
    version = "*",
    config = function()
      require("toggleterm").setup{}
    end
  },
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,
    config = function()
      require('catppuccin').setup({
        flavour = 'macchiato',
        integrations = {
          treesitter = true,
        },
      })
      vim.cmd.colorscheme 'catppuccin'
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = {
          'bash', 'c', 'cpp', 'css', 'dockerfile', 'gitignore', 'go', 'html',
          'javascript', 'json', 'lua', 'markdown', 'python', 'rust', 'sql',
          'toml', 'typescript', 'vim', 'yaml', 'zig'
        },
        sync_install = false,
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },
        indent = {
          enable = true,
        },
      })
    end,
  },
})


-- Misc
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.wo.number = true
vim.wo.relativenumber = true


-- Scooter integration
local Terminal = require("toggleterm.terminal").Terminal
local scooter_term = nil

local function open_scooter()
    if not scooter_term then
        scooter_term = Terminal:new({
            cmd = "scooter",
            direction = "float",
            close_on_exit = true,
            on_exit = function()
                scooter_term = nil
            end
        })
    end
    scooter_term:open()
end

_G.EditLineFromScooter = function(file_path, line)
    if scooter_term and scooter_term:is_open() then
        scooter_term:close()
    end

    local current_path = vim.fn.expand("%:p")
    local target_path = vim.fn.fnamemodify(file_path, ":p")

    if current_path ~= target_path then
        vim.cmd.edit(vim.fn.fnameescape(file_path))
    end

    vim.api.nvim_win_set_cursor(0, { line, 0 })
end

_G.OpenScooterSearchText = function(search_text)
    if scooter_term and scooter_term:is_open() then
        scooter_term:close()
    end

    local escaped_text = vim.fn.shellescape(search_text:gsub("\r?\n", " "))
    scooter_term = Terminal:new({
        cmd = "scooter --search-text " .. escaped_text,
        direction = "float",
        close_on_exit = true,
        on_exit = function()
            scooter_term = nil
        end
    })
    scooter_term:open()
end

vim.keymap.set('n', '<leader>s', open_scooter, { desc = 'Open scooter' })

vim.keymap.set('v', '<leader>r',
    '"ay<ESC><cmd>lua OpenScooterSearchText(vim.fn.getreg("a"))<CR>',
    { desc = 'Search selected text in scooter' })
