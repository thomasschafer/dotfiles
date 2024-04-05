return {
  {
    "karb94/neoscroll.nvim",
    config = function()
      require("neoscroll").setup({
        mappings = { "<C-u>", "<C-d>" },
      })

      require("neoscroll.config").set_mappings({
        ["<C-u>"] = { "scroll", { "-vim.wo.scroll", "true", "120" } },
        ["<C-d>"] = { "scroll", { "vim.wo.scroll", "true", "120" } },
      })
    end,
  },
}
