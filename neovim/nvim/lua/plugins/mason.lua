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
        "rubocop",
        "sorbet",
        "stylua",
        "shellcheck",
        "shfmt",
        "typescript-language-server",
      },
    },
  },
}
