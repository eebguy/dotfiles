-- Language servers: autocomplete, go-to-definition, rename, diagnostics.
-- Mason installs the servers and tools into ~/.local/share/nvim/mason (:Mason to browse).
--
-- Keys once a server is attached (the gr* ones are Neovim defaults):
--   gd definition   gD declaration   grr references   gri implementation
--   grn rename      gra code action  K hover docs     <C-s> signature (insert mode)
--   gO symbols      [d ]d prev/next diagnostic        <leader>cd show diagnostic
local servers = {
  gopls = {
    settings = {
      gopls = {
        gofumpt = true,
        staticcheck = true,
        usePlaceholders = false,
        analyses = { unusedparams = true, shadow = true },
        hints = {
          assignVariableTypes = true, compositeLiteralFields = true, constantValues = true,
          functionTypeParameters = true, parameterNames = true, rangeVariableTypes = true,
        },
      },
    },
  },
  terraformls = {},
  bashls = {},   -- also runs shellcheck on your scripts
  yamlls = {
    settings = {
      yaml = {
        -- Schemas for well-known files (GitHub Actions, docker-compose, Helm Chart.yaml...)
        schemaStore = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
        -- Kubernetes manifests: files in these places get the Kubernetes schema
        schemas = {
          kubernetes = {
            "k8s/**/*.{yml,yaml}", "kubernetes/**/*.{yml,yaml}", "manifests/**/*.{yml,yaml}",
            "*.k8s.{yml,yaml}",
          },
        },
        validate = true,
        keyOrdering = false,
      },
    },
  },
  lua_ls = {
    settings = {
      Lua = {
        workspace = { checkThirdParty = false },
        completion = { callSnippet = "Replace" },
        hint = { enable = true },
      },
    },
  },
  marksman = {},
}

-- Mason package names for the servers above, plus linters/formatters
local tools = {
  "gopls", "terraform-ls", "bash-language-server", "yaml-language-server",
  "lua-language-server", "marksman",
  "shellcheck", "shfmt", "gofumpt", "goimports", "stylua",
}

return {
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    opts = {},
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    event = "VeryLazy",
    opts = { ensure_installed = tools, run_on_start = true },
    config = function(_, opts)
      require("mason-tool-installer").setup(opts)
      vim.cmd("MasonToolsInstall")   -- run_on_start can't fire when loaded after startup
    end,
  },

  -- nvim-lspconfig supplies ready-made server definitions; Neovim's built-in
  -- vim.lsp.config/vim.lsp.enable do the rest.
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim", "saghen/blink.cmp" },
    config = function()
      -- mason (a dependency, so already set up) has put its bin folder on PATH
      for name, cfg in pairs(servers) do
        vim.lsp.config(name, cfg)
      end
      vim.lsp.enable(vim.tbl_keys(servers))

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp", { clear = true }),
        callback = function(args)
          local function map(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gD", vim.lsp.buf.declaration, "Go to declaration")
          map("<leader>cr", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
        end,
      })
    end,
  },

  -- Completion and docs for the Neovim Lua API while editing this config
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
    },
  },
}
