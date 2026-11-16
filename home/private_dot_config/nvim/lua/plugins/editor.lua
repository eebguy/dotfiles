return {
  -- Ctrl-h/j/k/l moves between Neovim splits and tmux panes as if they were one
  {
    "christoomey/vim-tmux-navigator",
    cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Window left" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Window down" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Window up" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Window right" },
    },
  },

  -- Fuzzy finder, built on the fzf binary you already use in the shell
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    dependencies = { "nvim-mini/mini.icons" },
    opts = {
      defaults = { file_icons = "mini" },
      files = { cwd_prompt = false },
    },
    keys = {
      { "<leader><space>", "<cmd>FzfLua files<cr>", desc = "Find files" },
      { "<leader>ff", "<cmd>FzfLua files<cr>", desc = "Files" },
      { "<leader>fg", "<cmd>FzfLua live_grep<cr>", desc = "Grep (text in files)" },
      { "<leader>fw", "<cmd>FzfLua grep_cword<cr>", desc = "Word under cursor" },
      { "<leader>fb", "<cmd>FzfLua buffers<cr>", desc = "Open buffers" },
      { "<leader>fr", "<cmd>FzfLua oldfiles<cr>", desc = "Recent files" },
      { "<leader>fh", "<cmd>FzfLua helptags<cr>", desc = "Help pages" },
      { "<leader>fk", "<cmd>FzfLua keymaps<cr>", desc = "Keymaps" },
      { "<leader>fd", "<cmd>FzfLua diagnostics_document<cr>", desc = "Diagnostics" },
      { "<leader>fs", "<cmd>FzfLua lsp_document_symbols<cr>", desc = "Symbols in file" },
      { "<leader>f.", "<cmd>FzfLua resume<cr>", desc = "Resume last search" },
    },
  },

  -- File explorer that is a normal buffer: edit names, dd to delete, :w to apply
  {
    "stevearc/oil.nvim",
    lazy = false,   -- so `nvim .` opens oil instead of netrw
    dependencies = { "nvim-mini/mini.icons" },
    opts = {
      view_options = { show_hidden = true },
      skip_confirm_for_simple_edits = true,
    },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
    },
  },

  -- Git: change markers in the sign column, hunk actions, inline blame
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(buf)
        local gs = require("gitsigns")
        local function map(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc }) end
        map("]h", function() gs.nav_hunk("next") end, "Next git change")
        map("[h", function() gs.nav_hunk("prev") end, "Previous git change")
        map("<leader>gp", gs.preview_hunk, "Preview change")
        map("<leader>gs", gs.stage_hunk, "Stage change")
        map("<leader>gr", gs.reset_hunk, "Undo change")
        map("<leader>gb", gs.blame_line, "Blame line")
        map("<leader>gd", gs.diffthis, "Diff file")
      end,
    },
  },
}
