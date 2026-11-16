local group = vim.api.nvim_create_augroup("user_config", { clear = true })

-- Briefly highlight what you yanked
vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function() vim.hl.on_yank() end,
})

-- Reopen files where you left off
vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  callback = function(args)
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lines = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= lines and vim.bo[args.buf].filetype ~= "gitcommit" then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Go and Makefiles use real tabs
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "go", "gomod", "make" },
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

-- Equalise splits when the terminal (or tmux pane) is resized
vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  command = "tabdo wincmd =",
})
