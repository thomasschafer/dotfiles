-- Colour theme
require("catppuccin").setup({
  flavour = "mocha",
})

-- Set the background to be transparent to work with Tmux config
vim.api.nvim_create_autocmd("VimEnter", {
  pattern = "*",
  callback = function()
    vim.cmd("hi Normal guibg=NONE ctermbg=NONE")
    vim.cmd("hi NonText guibg=NONE ctermbg=NONE")
  end,
})

-- Update colour of visual selection
vim.api.nvim_set_hl(0, "Visual", { background = 0x707070 })

-- Update line number colours
vim.api.nvim_set_hl(0, "LineNr", { fg = "#a6adc8" })
vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#e2e8f8" })
