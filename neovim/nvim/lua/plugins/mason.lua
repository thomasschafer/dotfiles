return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "jsonnet-language-server",
        "jsonnetfmt",
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
