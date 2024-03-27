return {
  {
    "telescope.nvim",
    config = function()
      local actions = require("telescope.actions")

      require("telescope").setup({
        defaults = {
          mappings = {
            i = {
              ["<C-q>"] = actions.send_to_qflist,
            },
            n = {
              ["<C-q>"] = actions.send_to_qflist,
            },
          },
        },
      })
    end,
  },
}
