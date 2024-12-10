return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      filtered_items = {
        visible = true,
        show_hidden_count = true,
        hide_dotfiles = false,
        hide_gitignored = true,
        hide_by_name = {},
        never_show = {
          ".git",
          ".DS_Store",
          "thumbs.db",
        },
      },
    },
    window = {
      mappings = {
        ["b"] = function(state)
          local node = state.tree:get_node()
          require("neo-tree.ui.renderer").focus_node(state, node:get_parent_id())
        end,
      },
    },
  },
}
