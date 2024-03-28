return {
  {
    "telescope.nvim",
    config = function()
      local actions = require("telescope.actions")

      require("telescope").setup({
        defaults = {
          layout_strategy = "flex",
          sorting_strategy = "ascending",
          layout_config = {
            prompt_position = "top",
          },
          mappings = {
            i = {
              ["<C-q>"] = actions.send_to_qflist,
              -- ["<C-a>"] = actions.to_fuzzy_refine,
            },
            n = {
              ["<C-q>"] = actions.send_to_qflist,
              -- ["<C-a>"] = actions.to_fuzzy_refine,
            },
          },
        },
      })
    end,
  },
}
