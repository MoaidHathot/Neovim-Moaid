return {
	{
		'hrsh7th/cmp-nvim-lsp',
		-- event = { "BufReadPre", "BufNewFile" },
		event = "InsertEnter",
		-- event = "VeryLazy",
	},
	{
		'github/copilot.vim',
		event = "InsertEnter",
		keys = {
			{ "<C-l>", "<Plug>(copilot-next)",        mode = "i" },
			{ "<C-h>", "<Plug>(copilot-previous)",    mode = "i" },
			{ "<C-a>", "<Plug>(copilot-suggest)",     mode = "i" },
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
			local cmp_entry = require('cmp.entry')
			cmp_entry._moaid_get_documentation = cmp_entry._moaid_get_documentation or cmp_entry.get_documentation
			local csharp_keywords = {
				["abstract"] = true,
				["async"] = true,
				["bool"] = true,
				["class"] = true,
				["const"] = true,
				["decimal"] = true,
				["delegate"] = true,
				["double"] = true,
				["enum"] = true,
				["event"] = true,
				["false"] = true,
				["float"] = true,
				["in"] = true,
				["int"] = true,
				["interface"] = true,
				["internal"] = true,
				["long"] = true,
				["new"] = true,
				["null"] = true,
				["object"] = true,
				["out"] = true,
				["override"] = true,
				["private"] = true,
				["protected"] = true,
				["public"] = true,
				["readonly"] = true,
				["ref"] = true,
				["return"] = true,
				["sealed"] = true,
				["short"] = true,
				["static"] = true,
				["string"] = true,
				["struct"] = true,
				["this"] = true,
				["true"] = true,
				["uint"] = true,
				["ulong"] = true,
				["using"] = true,
				["virtual"] = true,
				["void"] = true,
			}

			local function highlight_csharp_cmp_docs(buf)
				if vim.bo[buf].filetype ~= "cmp_docs" or vim.bo.filetype ~= "cs" then
					return
				end

				vim.bo[buf].syntax = "csharp"
				pcall(vim.treesitter.start, buf, "c_sharp")

				local namespace = vim.api.nvim_create_namespace("moaid_cmp_csharp_docs")
				vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

				for line_number, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
					for start_col, text in line:gmatch("()([%a_][%w_]*)") do
						local group
						if csharp_keywords[text] then
							group = "Keyword"
						elseif text:match("^[A-Z]") then
							group = "Type"
						end

						if group then
							vim.api.nvim_buf_add_highlight(buf, namespace, group, line_number - 1, start_col - 1, start_col + #text - 1)
						end
					end

					for start_col, method in line:gmatch("()([%a_][%w_]*)%s*%(") do
						vim.api.nvim_buf_add_highlight(buf, namespace, "Function", line_number - 1, start_col - 1, start_col + #method - 1)
					end
				end
			end
			local kind_icons = {
				Text = "txt",
				Method = "m",
				Function = "fn",
				Constructor = "new",
				Field = "field",
				Variable = "var",
				Class = "class",
				Interface = "iface",
				Module = "mod",
				Property = "prop",
				Unit = "unit",
				Value = "value",
				Enum = "enum",
				Keyword = "kw",
				Snippet = "snip",
				Color = "color",
				File = "file",
				Reference = "ref",
				Folder = "dir",
				EnumMember = "enumv",
				Constant = "const",
				Struct = "struct",
				Event = "event",
				Operator = "op",
				TypeParameter = "type",
			}

			local function set_cmp_highlights()
				vim.api.nvim_set_hl(0, "CmpItemAbbrMatch", { link = "Search" })
				vim.api.nvim_set_hl(0, "CmpItemAbbrMatchFuzzy", { link = "Search" })
				vim.api.nvim_set_hl(0, "CmpItemKindMethod", { link = "Function" })
				vim.api.nvim_set_hl(0, "CmpItemKindFunction", { link = "Function" })
				vim.api.nvim_set_hl(0, "CmpItemKindConstructor", { link = "Function" })
				vim.api.nvim_set_hl(0, "CmpItemKindField", { link = "Identifier" })
				vim.api.nvim_set_hl(0, "CmpItemKindProperty", { link = "Identifier" })
				vim.api.nvim_set_hl(0, "CmpItemKindVariable", { link = "Identifier" })
				vim.api.nvim_set_hl(0, "CmpItemKindClass", { link = "Type" })
				vim.api.nvim_set_hl(0, "CmpItemKindInterface", { link = "Type" })
				vim.api.nvim_set_hl(0, "CmpItemKindStruct", { link = "Type" })
				vim.api.nvim_set_hl(0, "CmpItemKindEnum", { link = "Type" })
				vim.api.nvim_set_hl(0, "CmpItemKindEnumMember", { link = "Constant" })
				vim.api.nvim_set_hl(0, "CmpItemKindKeyword", { link = "Keyword" })
				vim.api.nvim_set_hl(0, "CmpItemKindSnippet", { link = "Special" })
				vim.api.nvim_set_hl(0, "CmpItemKindConstant", { link = "Constant" })
				vim.api.nvim_set_hl(0, "CmpItemKindTypeParameter", { link = "Type" })
				vim.api.nvim_set_hl(0, "CmpItemMenu", { link = "Comment" })
				vim.api.nvim_set_hl(0, "LspSignatureActiveParameter", { link = "IncSearch" })
			end

			set_cmp_highlights()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("moaid_cmp_highlights", { clear = true }),
				callback = set_cmp_highlights,
			})

			vim.api.nvim_create_autocmd("InsertEnter", {
				callback = function()
					require("luasnip.loaders.from_vscode").lazy_load()
				end,
				once = true,
			})
			vim.api.nvim_create_autocmd({ "FileType", "TextChanged" }, {
				group = vim.api.nvim_create_augroup("moaid_cmp_docs_csharp", { clear = true }),
				pattern = "cmp_docs",
				callback = function(ev)
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(ev.buf) then
							highlight_csharp_cmp_docs(ev.buf)
						end
					end)
				end,
			})

			cmp_entry.get_documentation = function(entry)
				local documents = cmp_entry._moaid_get_documentation(entry)
				if entry.context and entry.context.filetype == "cs" then
					for index, line in ipairs(documents) do
						documents[index] = line:gsub("^```cs%s*$", "```csharp")
					end
				end

				return documents
			end

			-- require("luasnip.loaders.from_vscode").lazy_load()
			cmp.setup({
				completion = {
					completeopt = "menu,menuone,noselect",
				},
				preselect = cmp.PreselectMode.None,
				snippet = {
					expand = function(args)
						require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
					end,
				},
				window = {
					completion = cmp.config.window.bordered({
						winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel,Search:None",
					}),
					documentation = cmp.config.window.bordered({
						winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,Search:None",
					}),
				},
				formatting = {
					fields = { "abbr", "kind", "menu" },
					format = function(entry, item)
						local icon = kind_icons[item.kind] or item.kind
						item.kind = string.format("%-7s %s", icon, item.kind)

						if #item.abbr > 42 then
							item.abbr = item.abbr:sub(1, 39) .. "..."
						end

						item.menu = ({
							nvim_lsp = "[LSP]",
							luasnip = "[Snip]",
							nvim_lsp_signature_help = "[Sig]",
							buffer = "[Buf]",
						})[entry.source.name] or ""

						return item
					end,
				},
				mapping = cmp.mapping.preset.insert({
					['<C-b>'] = cmp.mapping.scroll_docs(-4),
					['<C-j>'] = cmp.mapping.scroll_docs(4),
					['<Tab>'] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
						else
							fallback()
						end
					end, { 'i', 's' }),
					['<S-Tab>'] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
						else
							fallback()
						end
					end, { 'i', 's' }),
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
					}),
				experimental = {
					ghost_text = true,
				},
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
		event = "InsertEnter",
		opts = {
			bind = true,
			doc_lines = 3,
			max_height = 10,
			max_width = 90,
			wrap = true,
			floating_window = true,
			floating_window_above_cur_line = true,
			hint_enable = true,
			hint_prefix = "param: ",
			hint_scheme = "Comment",
			hi_parameter = "LspSignatureActiveParameter",
			handler_opts = {
				border = "rounded"
			},
			always_trigger = false,
			cursorhold_update = false,
			extra_trigger_chars = { "(", "," },
			zindex = 200,
		},
		config = function(_, opts)
			require("lsp_signature").setup(opts)

			local cycle_signature = function()
				require('lsp_signature').signature({ trigger = 'NextSignature' })
			end

			vim.keymap.set('i', '<C-Right>', cycle_signature, { desc = 'Next signature overload', silent = true })
			vim.keymap.set('i', '<C-Left>', cycle_signature, { desc = 'Next signature overload', silent = true })
		end,
	}
}
