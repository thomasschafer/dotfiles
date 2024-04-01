return {
  {
    "telescope.nvim",
    dependencies = {
      { "nvim-telescope/telescope-live-grep-args.nvim" },
    },
    config = function()
      local actions = require("telescope.actions")
      require("telescope").load_extension("live_grep_args")
      local lga_actions = require("telescope-live-grep-args.actions")

      vim.keymap.set("n", "<leader>/", function()
        require("telescope").extensions.live_grep_args.live_grep_args()
      end, { desc = "Find files (live grep)" })

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
