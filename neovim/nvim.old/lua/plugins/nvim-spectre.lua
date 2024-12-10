return {
  "nvim-pack/nvim-spectre",
  build = false,
  cmd = "Spectre",
  opts = { open_cmd = "noswapfile vnew" },
  keys = {
    {
      "<leader>sr",
      function()
        vim.cmd("highlight SpectreSearch guifg=#f28fad guibg=#1e1e2e")
        vim.cmd("highlight SpectreReplace guifg=#abe9b3 guibg=#1e1e2e")
        require("spectre").open()
      end,
      desc = "Replace in Files (Spectre)",
    },
  },
}
