-- Leader must be set before plugins load, so their keymaps pick it up
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- No plugins here use the Python/Node/Ruby/Perl plugin hosts; skip loading them
for _, p in ipairs({ "python3", "node", "ruby", "perl" }) do vim.g["loaded_" .. p .. "_provider"] = 0 end

local o = vim.opt

-- Look
o.number = true
o.relativenumber = true    -- jump with 5j / 12k
o.signcolumn = "yes"       -- no text shifting when git/diagnostic signs appear
o.cursorline = true
o.wrap = false
o.scrolloff = 8
o.sidescrolloff = 8
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
o.showmode = false         -- lualine shows the mode
o.laststatus = 3           -- one statusline for all splits
o.winborder = "rounded"    -- floating windows (hover, diagnostics)
o.pumheight = 12

-- Editing
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.undofile = true          -- undo survives closing the file
o.confirm = true           -- ask instead of failing on :q with unsaved changes
o.mouse = "a"

-- Search
o.ignorecase = true
o.smartcase = true         -- case-sensitive once you type a capital
o.inccommand = "split"     -- live preview of :%s/old/new/

-- Windows & timing
o.splitright = true
o.splitbelow = true
o.updatetime = 250
o.timeoutlen = 400

-- Clipboard: yanks go to the system clipboard.
--   WSL   → win32yank.exe (install.sh puts it in ~/.local/bin; Neovim finds it itself)
--   macOS → pbcopy/pbpaste (built in)
--   SSH   → copy through the terminal with OSC 52 (works inside tmux too);
--           paste with your terminal's paste key, since most terminals block OSC 52 reads
if vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
vim.schedule(function() vim.opt.clipboard = "unnamedplus" end) -- after startup: provider lookup is slow-ish

-- Diagnostics (errors/warnings from language servers)
vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = "●" },
  severity_sort = true,
  float = { source = "if_many" },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "",
      [vim.diagnostic.severity.WARN] = "",
      [vim.diagnostic.severity.INFO] = "",
      [vim.diagnostic.severity.HINT] = "",
    },
  },
})
