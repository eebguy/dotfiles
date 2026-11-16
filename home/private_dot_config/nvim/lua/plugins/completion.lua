-- Autocomplete popup.
--   <C-n>/<C-p> or arrows  move      <C-y> or Enter  accept     <C-e>  close
--   <C-space>  open manually / toggle docs      <Tab>/<S-Tab>  jump in a snippet
return {
  {
    "saghen/blink.cmp",
    version = "1.*",   -- release tags ship a prebuilt fuzzy matcher
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        preset = "default",
        ["<CR>"] = { "accept", "fallback" },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
        list = { selection = { preselect = true, auto_insert = false } },
      },
      signature = { enabled = true },
      sources = {
        default = { "lazydev", "lsp", "path", "snippets", "buffer" },
        providers = {
          lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        },
      },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
  },
}
