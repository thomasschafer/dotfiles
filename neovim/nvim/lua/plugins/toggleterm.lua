return  {
  'akinsho/toggleterm.nvim',
  version = "*",
  config = function()
    require("toggleterm").setup({
      size = 20,
      open_mapping = [[<c-\>]],
      hide_numbers = true,
      shade_filetypes = {},
      shade_terminals = true,
      shading_factor = 2,
      start_in_insert = true,
      persist_size = true,
      direction = "float",
    })

    local Terminal = require("toggleterm.terminal").Terminal
    local scooter = Terminal:new({ cmd = "scooter", hidden = true })

    function _scooter_toggle()
      scooter:toggle()
    end

    vim.keymap.set("n", "<leader>s", "<cmd>lua _scooter_toggle()<CR>", {
      noremap = true,
      silent = true,
      desc = "Toggle Scooter"
    })
  end
}
