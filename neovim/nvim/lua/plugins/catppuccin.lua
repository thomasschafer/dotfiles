return {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
        require("catppuccin").setup({
            flavour = "macchiato",
        })
        vim.cmd.colorscheme "catppuccin"
        vim.cmd [[
          highlight Normal guibg=none
          highlight NonText guibg=none
          highlight Normal ctermbg=none
          highlight NonText ctermbg=none
        ]]

        -- Update line number colours
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#a6adc8" })
        vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#e2e8f8" })

        -- Set cursor colours and default to block
        vim.opt.guicursor = "n:block-Cursor,i:block-CursorInsert,v:block-CursorVisual"
        vim.cmd([[highlight CursorInsert guifg=NONE guibg=#f4dbd6]])
        vim.cmd([[highlight Cursor guifg=NONE guibg=#b7bdf8]])
        vim.cmd([[highlight CursorVisual guifg=NONE guibg=#f5a97f]])

    end,
}
