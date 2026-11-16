return {
  -- Colour scheme (blue-heavy, sits well with the BMW tmux/starship palette)
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = { style = "night" },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
    end,
  },

  -- File-type icons (needs a Nerd Font, e.g. Maple Mono NF)
  {
    "nvim-mini/mini.icons",
    lazy = true,
    opts = {},
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "tokyonight",
        globalstatus = true,
        component_separators = "",
        section_separators = "",
      },
      sections = {
        lualine_c = { { "filename", path = 1 } },   -- path relative to the project
        lualine_x = { "diagnostics", "filetype" },
      },
    },
  },

  -- Shows the keys that can follow what you just typed (try <Space>, g, ], z)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      spec = {
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>u", group = "toggle" },
      },
    },
  },
}
