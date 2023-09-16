local zero = require('lsp-zero')
-- local lsp = zero.preset({})
local lsp = zero.preset('recommended')
-- local lsp = zero.preset({
-- 	name = 'recommended',
-- 	set_lsp_keymaps = true,
-- 	manage_nvim_cmp = true,
-- 	suggest_lsp_servers = true
-- })

-- local navic = require('nvim-navic')
--
lsp.on_attach(function(client, bufnr)
	lsp.default_keymaps({ buffer = bufnr, preserve_mappings = true })
	-- lsp.default_keymaps({ buffer = bufnr, preserve_mappings = true })
	lsp.buffer_autoformat()

	vim.keymap.set({ 'n', 'x' }, '<leader>lf', function()
		vim.lsp.buf.format({ async = false, timeout_ms = 10000 })
	end, { desc = "Format Buffer", silent = true })


	if client.server_capabilities.signatureHelpProvider then
		local overloads = require('lsp-overloads')
		overloads.setup(client, {
		})

		-- overloads.setup(client, {
		-- 	keymaps = {
		-- 		-- next_signature = "<C-j>",
		-- 		next_signature = '<leader>lk',
		-- 		-- previous_signature = "<C-k>",
		-- 		previous_signature = "<leader>lj",
		-- 		next_parameter = '<C-l>',
		-- 		previous_parameter = '<C-h>',
		-- 		close_signature = "<A-s>"
		-- 	},
		-- 	display_automatically = true
		-- })
	end
	-- vim.keymap.set('n', '<leader>le', "<cmd>Telescope lsp_references<CR>", {buffer = true})
	-- bind('n', '<leader>r', '<cmd> lua vim.lsp.buf.rename()<cr>')
end)

vim.keymap.set('n', '<A-k>', ":LspOverloadsSignature<CR>", { desc = 'Toggle Method Signature Overloads', silent = true })
vim.keymap.set('i', '<A-k>', "<CMD>:LspOverloadsSignature<CR>",
	{ desc = 'Toggle Method Signature Overloads', silent = true })
-- vim.api.nvim_set_keymap("n", "<A-s>", ":LspOverloadsSignature<CR>",
-- 	{ noremap = true, silent = true, desc = 'Toggle Method Signature Overloads' })
--
-- vim.api.nvim_set_keymap("i", "<A-s>", "<cmd>LspOverloadsSignature<CR>",
-- 	{ noremap = true, silent = true, desc = 'Toggle Method Signature Overloads' })

-- vim.keymap.set({ 'n' }, '<C-k>', function()
-- 		signature.toggle_float_win()
-- 	end,
-- 	{ silent = true, desc = 'toggle signature' })

-- vim.keymap.set({ 'n' }, '<C-l>', function()
-- 		signature.signature_help()
-- 	end,
-- 	{ silent = true, desc = 'toggle signature' })
--
vim.keymap.set({ 'n', }, '<C-M-k>', function()
		vim.lsp.buf.signature_help()
	end,
	{ silent = true, desc = 'toggle signature' })


vim.keymap.set({ 'n', }, '<leader>ls', function()
		require('lsp_signature').toggle_float_win()
	end,
	{ silent = true, desc = 'toggle signature' })

-- vim.keymap.set('n', '<leader>la', vim.lsp.buf.code_action())

-- (Optional) Configure lua language server for neovim

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(ev)
		local neodev = require('neodev')

		neodev.setup({
			library = {
				plugins = {
					'nvim-dap-ui',
					types = true
				}
			}
		})

		local signature = require('lsp_signature')

		signature.setup {
			bind = true,
			handler_opts = {
				border = 'rounded'
			},
			max_width = 130,
			wrap = true,
			floating_window = false,
			always_trigger = false,
		}
	end
})


local lspconfig = require('lspconfig')

local schemas = require('schemastore')

lspconfig.jsonls.setup {
	settings = {
		json = {
			schemas = schemas.json.schemas(),
			validate = { enable = true },
		}
	}
}

lspconfig.yamlls.setup {
	settins = {
		yamlls = {
			schemas = schemas.yaml.schemas(),
		},
	},
}

-- lspconfig.lua_ls.setup(lsp.nvim_lua_ls())

lspconfig.omnisharp.setup({
	enable_roslyn_analysers = true,
	enable_import_completion = true,
	organize_imports_on_format = true,
	filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props' },
})

lspconfig.lua_ls.setup(lsp.nvim_lua_ls())


local cmp = require('cmp')
local cmp_select = { behavior = cmp.SelectBehavior.Select }

local cmp_mappings = lsp.defaults.cmp_mappings({
	['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
	['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
	-- ['<leader>.'] = cmp.mapping.complete_common_string(),
	-- ['<C-f>'] = cmp.mapping.scroll_docs(4),
	['<C-y>'] = cmp.mapping.confirm({ select = true }),
	['<CR>'] = cmp.mapping.confirm({ select = true }),
	['<Tab>'] = cmp.mapping.confirm({ select = true }),
	-- ['<C-space>'] = cmp.mapping.complete(),
})

-- vim.api.nvim_set_keymap('i', "<A-s>", "<cmd>LspOverloadsSignature<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', "<A-s>", "<cmd>LspOverloadsSignature<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('i', "<leader>zz", "<cmd>LspOverloadsSignature<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', "<leader>zz", "<cmd>LspOverloadsSignature<CR>", { noremap = true, silent = true })
--
-- local capabilities = require('cmp_nvim_lsp').default_capabilities()
-- lspconfig['Omnisharp'].setup {
-- 	capabilities = capabilities
-- }


lsp.setup_nvim_cmp({
	mapping = cmp_mappings
})

lsp.set_sign_icons({
	error = '✘',
	warn = '▲',
	hint = '⚑',
	info = '»'
})



vim.diagnostic.config({
	virtual_lines = false,
	virtual_text = true,
})

local function toggleLines()
	local new_value = not vim.diagnostic.config().virtual_lines
	vim.diagnostic.config({ virtual_lines = new_value, virtual_text = not new_value })
	return new_value
end

vim.keymap.set('n', '<leader>lu', toggleLines, { desc = "Toggle Underline Diagnostics", silent = true })

lsp.setup()

-- some shorthands...
-- local s = ls.snippet
-- local sn = ls.snippet_node
-- local t = ls.text_node
-- local i = ls.insert_node
-- local f = ls.function_node
-- local c = ls.choice_node
-- local d = ls.dynamic_node
-- local r = ls.restore_node
-- local l = require("luasnip.extras").lambda
-- local rep = require("luasnip.extras").rep
-- local p = require("luasnip.extras").partial
-- local m = require("luasnip.extras").match
-- local n = require("luasnip.extras").nonempty
-- local dl = require("luasnip.extras").dynamic_lambda
-- local fmt = require("luasnip.extras.fmt").fmt
-- local fmta = require("luasnip.extras.fmt").fmta
-- local types = require("luasnip.util.types")
-- local conds = require("luasnip.extras.conditions")
-- local conds_expand = require("luasnip.extras.conditions.expand")


vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(ev)
		require('lsp_lines').setup()

		local luasnip = require('luasnip')
		luasnip.config.set_config({
			enable_autosnippets = true,
			history = true
		})
		luasnip.config.setup({
			enable_autosnippets = true,
			history = true
		})

		function create_namespace_from_path(path)
			return 'namespace ' .. path:gsub('[a-zA-Z]:[\\/]', ''):gsub('[\\/]', '.') .. ';'
		end

		function get_namespace()
			local fname = vim.api.nvim_buf_get_name(0)
			print('fname: ' .. fname)
			local util = require('lspconfig.util')
			local path = util.root_pattern '*.csproj' (fname) or util.root_pattern '*.sln' (fname) or
				util.root_pattern '*.sln' ('./') or util.root_pattern '*.csproj' ('./') or util.root_pattern '*.slnx'
			print('path: ', path)

			if path == nil then
				path = ''
			end

			local result = fname:gsub(path .. '/', ''):gsub(path .. '\\', '')
			print('temp-result: ' .. result)
			local no_fname = result:gsub('[\\/]?[a-zA-Z0-9_@]+.cs$', '')

			print('no_fname: ' .. no_fname)

			local namespace = create_namespace_from_path(no_fname)
			return namespace
		end

		local function get_class_name()
			local start_index, end_index, file_name = string.find(vim.api.nvim_buf_get_name(0), '([a-zA-Z_@<>0-9]+).cs')
			local name = file_name:gsub('.cs', ''):gsub('/', ''):gsub('\\', '')

			return name
		end

		local function get_class_with_namespace()
			local class_name = get_class_name()
			local namespace_name = get_namespace()
			local type = "class"

			if (class_name:sub(1, 1) == "I") then
				type = "interface"
			end

			return {
				namespace_name,
				[[]],
				'public ' .. type .. ' ' .. class_name,
				[[{]],
				[[]],
				'}'
			}
		end

		luasnip.add_snippets(nil, {
			cs = {
				luasnip.snippet({
						trig = 'namespace',
						name = 'add namesapce',
						dscr = 'Add namespace'
					},
					{
						luasnip.function_node(get_namespace, {})
					}
				),
				luasnip.snippet({
						trig = 'class',
						name = 'class with namesapce',
						dscr = 'class with namesapce'
					},
					{
						luasnip.function_node(get_class_with_namespace, {})
					})
			}
		})

		luasnip.setup()

		require('luasnip.loaders.from_vscode').lazy_load()

		local cmp_action = zero.cmp_action()

		cmp.setup {
			windows = {
				completion = cmp.config.window.bordered(),
				documentation = cmp.config.window.bordered(),
			},
			mapping = {
				['<Tab'] = cmp_action.tab_complete(),
				['<S-Tab>'] = cmp_action.select_prev_or_fallback(),
				-- check if the below <c-l> is needed. It was added as a test
				['<C-l>'] = cmp.mapping(function(fallback)
					if cmp.visible() then
						return cmp.complete_common_string()
					end
					fallback()
				end, { 'i', 'c', 'n' })
			},
			sources = cmp.config.sources({
				{ name = 'nvim_lsp' },
				{ name = 'nvim_lua' },
				{ name = 'luasnip' },
				{ name = 'path' },
				-- 	-- { name = 'nvim_lsp_signature_help' }
			}),
			snippet = {
				expand = function(args)
					luasnip.lsp_expand(args.body)
				end
			},
			formatting = {
				fields = { 'abbr', 'kind', 'menu' },
				format = require('lspkind').cmp_format({
					mode = 'symbol_text',
					maxwidth = 50,
					ellipsis_char = '...'
				})
			}
			-- sources = {
			-- 	name = 'nvim_lsp'
			-- }
		}

		cmp.setup.cmdline('/', {
			mapping = cmp.mapping.preset.cmdline(),
			sources = { { name = 'buffer' } }
		})

		cmp.setup.cmdline(':', {
			mapping = cmp.mapping.preset.cmdline(),
			sources = cmp.config.sources({
					{ name = 'path' }
				},
				{
					{
						name = 'cmdline',
						option = {
							ignore_cmds = { 'Main', '!' }
						}
					}
				}
			)
		})
	end,
})


vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(ev)
		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		local function toSnakeCase(str)
			return string.gsub(str, "%s*[- ]%s*", "_")
		end

		if client.name == 'omnisharp' then
			local tokenModifiers = client.server_capabilities.semanticTokensProvider.legend.tokenModifiers
			for i, v in ipairs(tokenModifiers) do
				tokenModifiers[i] = toSnakeCase(v)
			end
			local tokenTypes = client.server_capabilities.semanticTokensProvider.legend.tokenTypes
			for i, v in ipairs(tokenTypes) do
				tokenTypes[i] = toSnakeCase(v)
			end
		end

		-- Below are separate from the above

		local null = require('null-ls')

		null.setup({
			sources = {
				-- null.builtins.formatting.prettier,
				-- null.builtins.diagnostics.eslint,
				-- null.builtins.formatting.stylua,
				null.builtins.code_actions.gitsigns,
			}
		})

		require('mason').setup()
		require('mason-null-ls').setup({
			automatic_setup = true,
		})
	end,
})
