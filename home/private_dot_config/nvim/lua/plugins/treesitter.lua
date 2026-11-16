-- Treesitter: accurate syntax highlighting and indentation.
-- Parsers are compiled locally with the tree-sitter CLI and a C compiler (install.sh
-- provides both). Add a language by adding it to `parsers`; :TSUpdate updates them all.
local parsers = {
  "bash", "diff", "dockerfile", "git_config", "git_rebase", "gitcommit", "gitignore",
  "go", "gomod", "gosum", "gowork", "hcl", "json", "lua", "luadoc", "make",
  "markdown", "markdown_inline", "query", "terraform", "toml", "vim", "vimdoc", "yaml",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,   -- the plugin itself must not be lazy-loaded
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")
      if vim.fn.executable("tree-sitter") == 1 then
        local have = {}
        for _, p in ipairs(ts.get_installed()) do have[p] = true end
        local missing = vim.tbl_filter(function(p) return not have[p] end, parsers)
        if #missing > 0 then ts.install(missing) end   -- runs in the background
      else
        vim.notify("tree-sitter CLI not found: run install.sh to get syntax parsers", vim.log.levels.WARN)
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
        callback = function(args)
          if not pcall(vim.treesitter.start, args.buf) then return end   -- no parser: keep regex syntax
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}
