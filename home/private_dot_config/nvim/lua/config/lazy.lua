-- lazy.nvim: installs plugins on first start, loads each one only when needed.
-- :Lazy opens its dashboard (U = update, S = sync, X = clean unused).
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Failed to clone lazy.nvim:\n" .. out, "ErrorMsg" } }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = { { import = "plugins" } },
  -- Keep the lockfile out of ~/.config/nvim so chezmoi doesn't see it as a local edit
  lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
  install = { colorscheme = { "tokyonight", "habamax" } },
  rocks = { enabled = false },          -- no plugin here needs luarocks
  checker = { enabled = false },        -- no background update checks; run :Lazy update yourself
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
    },
  },
})
