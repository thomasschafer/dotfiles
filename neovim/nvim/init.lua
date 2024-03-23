-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

require("catppuccin").setup({
  flavour = "mocha", -- latte, frappe, macchiato, mocha
})

-- Set the background to be transparent to work with Tmux config
vim.cmd([[
  autocmd VimEnter * hi Normal guibg=NONE ctermbg=NONE
  autocmd VimEnter * hi NonText guibg=NONE ctermbg=NONE
]])
vim.api.nvim_set_hl(0, "Visual", { background = 0x707070 })
