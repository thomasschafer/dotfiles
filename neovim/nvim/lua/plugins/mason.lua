return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "prettierd",
        "pyright",
        "haskell-language-server",
        "stylua",
        "shellcheck",
        "shfmt",
        "typescript-language-server",
      },
    },
  },
}
