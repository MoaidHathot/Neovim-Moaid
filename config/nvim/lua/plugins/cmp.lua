return {
	{
		'hrsh7th/cmp-nvim-lsp',
		-- event = { "BufReadPre", "BufNewFile" },
		event = "BufReadPost",
		-- event = "VeryLazy",
	},
	{
		'github/copilot.vim',
		event = { "BufReadPre", "BufNewFile" },
		keys = {
			{ "<C-l>", "<Plug>(copilot-next)",        mode = "i" },
			{ "<C-h>", "<Plug>(copilot-previous)",    mode = "i" },
			{ "<C-c>", "<Plug>(copilot-suggest)",     mode = "i" },
			{ "<C-d>", "<Plug>(copilot-dismiss)",     mode = "i" },
			{ "<C-f>", "<Plug>(copilot-accept-word)", mode = "i" },
			{ "<C-g>", "<Plug>(copilot-accept-line)", mode = "i" },
		},
		-- event = "VeryLazy",
	},
	{
		'L3MON4D3/LuaSnip',
		-- event = "VeryLazy",
		lazy = true,
		-- event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			'saadparwaiz1/cmp_luasnip',
			'rafamadriz/friendly-snippets'
		}
	},
	{
		'hrsh7th/nvim-cmp',
		-- event = { "BufReadPre", "BufNewFile" },
		-- event = "BufReadPost",
		event = "InsertEnter",
		-- event = "VeryLazy",
		dependencies = {
			-- 'hrsh7th/cmp-cmdline',
			'hrsh7th/cmp-nvim-lsp-signature-help',
		},
		config = function()
			local cmp = require 'cmp'
			vim.api.nvim_create_autocmd("InsertEnter", {
				callback = function()
					require("luasnip.loaders.from_vscode").lazy_load()
				end,
				once = true,
			})
			-- require("luasnip.loaders.from_vscode").lazy_load()
			cmp.setup({
				snippet = {
					expand = function(args)
						require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
					end,
				},
				window = {
					completion = cmp.config.window.bordered(),
					documentation = cmp.config.window.bordered(),
				},
				mapping = cmp.mapping.preset.insert({
					['<C-b>'] = cmp.mapping.scroll_docs(-4),
					['<C-f>'] = cmp.mapping.scroll_docs(4),
					['<C-Space>'] = cmp.mapping.complete(),
					['<C-e>'] = cmp.mapping.abort(),
					['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
				}),
				sources = cmp.config.sources({
						{ name = 'nvim_lsp' },
						{ name = 'luasnip' }, -- For luasnip users.
						{ name = 'nvim_lsp_signature_help' }
					},
					{
						{ name = 'buffer' },
					})
			})

			-- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
			--cmp.setup.cmdline({ '/', '?' }, {
			--	mapping = cmp.mapping.preset.cmdline(),
			--	sources = {
			--		{ name = 'buffer' }
			--	}
			--})

			-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
			--cmp.setup.cmdline(':', {
			--	mapping = cmp.mapping.preset.cmdline(),
			--	sources = cmp.config.sources({
			--		{ name = 'path' }
			--	}, {
			--		{ name = 'cmdline' }
			--	})
			--})
		end
	},
	{
		"hrsh7th/cmp-cmdline",
		dependencies = { "hrsh7th/nvim-cmp" },
		event = "CmdlineEnter",
		config = function()
			local cmp = require("cmp")
			cmp.setup.cmdline({ '/', '?' }, {
				mapping = cmp.mapping.preset.cmdline(),
				sources = {
					{ name = 'buffer' }
				}
			})

			cmp.setup.cmdline(':', {
				mapping = cmp.mapping.preset.cmdline(),
				sources = cmp.config.sources({
					{ name = 'path' }
				}, {
					{ name = 'cmdline' }
				})
			})
		end
	},
	{
		"ray-x/lsp_signature.nvim",
		event = "VeryLazy",
		enabled = false,
		config = function()
			require("lsp_signature").setup({
				bind = true,
				handler_opts = {
					border = "rounded"
				},
				hint_enable = true,
				floating_window = true,
			})
		end
	}
}
