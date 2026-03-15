return {
  -- PowerReview.nvim - PR review inside Neovim
  {
    dir = "P:\\Playground\\PowerReview.nvim",
    name = "power-review.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-neo-tree/neo-tree.nvim",
      "nvim-telescope/telescope.nvim",
      {
        "esmuellert/codediff.nvim",
        opts = {},
      },
    },
    cmd = "PowerReview",
    keys = {
      { "<leader>pr", desc = "[PowerReview] Open/resume review" },
      { "<leader>pl", desc = "[PowerReview] List sessions" },
      { "<leader>pf", desc = "[PowerReview] Toggle files panel" },
      { "<leader>pc", desc = "[PowerReview] Toggle comments panel" },
      { "<leader>pa", desc = "[PowerReview] Add comment", mode = { "n", "v" } },
      { "<leader>pe", desc = "[PowerReview] Edit draft" },
      { "<leader>pA", desc = "[PowerReview] Approve draft" },
      { "<leader>pS", desc = "[PowerReview] Submit pending" },
      { "<leader>pv", desc = "[PowerReview] Set vote" },
      { "<leader>pR", desc = "[PowerReview] Reply to thread" },
      { "<leader>ps", desc = "[PowerReview] Sync remote threads" },
      { "<leader>pQ", desc = "[PowerReview] Close review" },
      { "<leader>pD", desc = "[PowerReview] Delete session" },
      { "]r", desc = "[PowerReview] Next comment" },
      { "[r", desc = "[PowerReview] Previous comment" },
    },
    config = function(_, opts)
      require("power-review").setup(opts)

      -- Inject statusline component into lualine (lualine_b section)
      local ok, lualine = pcall(require, "lualine")
      if ok then
        local sl = require("power-review.statusline")
        local lualine_cfg = lualine.get_config()
        -- Insert into lualine_b so it sits next to branch/diff
        table.insert(lualine_cfg.sections.lualine_b, sl.lualine())
        lualine.setup(lualine_cfg)
      end
    end,
    opts = {
      repos = {
        ["P:\\Work\\Networking\\Repo\\Zero-Trust-Segmentation\\ZTS"] = {
          provider = "azdo",
          azdo = {
            organization = "msazure",
            project = "One",
            repository = "ZTS",
          },
        },
      },

      auth = {
        azdo = {
          method = "az_cli",
        },
      },

      git = {
        strategy = "worktree",
      },

      ui = {
        files = {
          provider = "neo-tree",
        },
        diff = {
          provider = "native",
        },
      },

      mcp = {
        enabled = false, -- set to true when you want MCP server integration
      },
    },
  },
}
