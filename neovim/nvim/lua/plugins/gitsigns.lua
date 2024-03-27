return {
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      on_attach = function(buffer)
        local gs = package.loaded.gitsigns

        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
        end

        map("n", "<F53>", gs.next_hunk, "Next Hunk") -- <A-F5>
        map("n", "<M-S-F5>", gs.prev_hunk, "Prev Hunk") -- <A-S-F5>
        map("n", "<F51>", gs.preview_hunk_inline, "Preview Hunk Inline") -- <A-F3>
        map({ "n", "v" }, "<F52>", ":Gitsigns reset_hunk<CR>", "Reset Hunk") -- <A-F4>
      end,
    },
  },
}
