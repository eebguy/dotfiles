-- Format on save. :ConformInfo shows what will run for the current file.
-- <leader>cf formats now; <leader>uf turns format-on-save off/on for this session.
return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true }) end, desc = "Format file" },
      {
        "<leader>uf",
        function()
          vim.g.disable_autoformat = not vim.g.disable_autoformat
          vim.notify("Format on save " .. (vim.g.disable_autoformat and "off" or "on"))
        end,
        desc = "Toggle format on save",
      },
    },
    opts = {
      formatters_by_ft = {
        go = { "goimports", "gofumpt" },   -- fix imports, then stricter gofmt
        terraform = { "terraform_fmt" },
        ["terraform-vars"] = { "terraform_fmt" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        lua = { "stylua" },
      },
      -- Anything not listed (YAML, Markdown, ...) uses the language server's formatter, if any
      default_format_opts = { lsp_format = "fallback" },
      format_on_save = function()
        if vim.g.disable_autoformat then return end
        return { timeout_ms = 1000 }
      end,
      formatters = {
        shfmt = { prepend_args = { "-i", "2", "-ci" } },   -- 2-space indent, indent case items
      },
    },
  },
}
