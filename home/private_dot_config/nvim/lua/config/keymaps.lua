-- Plugin keymaps live with their plugin in lua/plugins/. Ctrl-h/j/k/l (move between
-- splits and tmux panes) comes from vim-tmux-navigator in lua/plugins/editor.lua.
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })

-- Buffers (open files)
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Close buffer" })

-- Splits
map("n", "<leader>|", "<cmd>vsplit<cr>", { desc = "Split right" })
map("n", "<leader>-", "<cmd>split<cr>", { desc = "Split below" })

-- Move selected lines up/down; keep the selection when indenting
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move lines down", silent = true })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move lines up", silent = true })
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Diagnostics (Neovim already maps [d / ]d to jump between them)
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Show diagnostic" })

-- Toggles
map("n", "<leader>uw", "<cmd>set wrap!<cr>", { desc = "Toggle line wrap" })
map("n", "<leader>uh", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = "Toggle inlay hints" })
