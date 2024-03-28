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
              -- ["<C-a>"] = actions.to_fuzzy_refine,
            },
            n = {
              ["<C-q>"] = actions.send_to_qflist,
              -- ["<C-a>"] = actions.to_fuzzy_refine,
            },
          },
        },
        -- extensions = {
        --   live_grep_args = {
        --     auto_quoting = true, -- enable/disable auto-quoting
        --     mappings = {
        --       i = {
        --         ["<C-u>"] = lga_actions.quote_prompt(),
        --         -- ["<C-i>"] = lga_actions.quote_prompt({ postfix = " --iglob " }),
        --       },
        --     },
        --   },
        -- },
      })
    end,
  },
}
