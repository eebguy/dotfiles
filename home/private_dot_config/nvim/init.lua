-- ~/.config/nvim/init.lua — managed by chezmoi (edit the source with `chezmoi edit`)
--
-- Layout:
--   lua/config/options.lua   editor settings
--   lua/config/keymaps.lua   keymaps that don't belong to a plugin
--   lua/config/autocmds.lua  small automatic behaviours
--   lua/config/lazy.lua      plugin manager bootstrap
--   lua/plugins/*.lua        one file per area; every file returns lazy.nvim specs
--
-- Press <Space> and wait: which-key shows every leader keymap.

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
