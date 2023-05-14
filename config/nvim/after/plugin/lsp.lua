local zero = require('lsp-zero')
-- local lsp = zero.preset({})
local lsp = zero.preset('recommended')
-- local lsp = zero.preset({
-- 	name = 'recommended',
-- 	set_lsp_keymaps = true,
-- 	manage_nvim_cmp = true,
-- 	suggest_lsp_servers = true
-- })

-- local signature = require('lsp_signature')
-- local navic = require('nvim-navic')

lsp.on_attach(function(client, bufnr)
	lsp.default_keymaps({ buffer = bufnr, preserve_mappings = true })
	-- lsp.default_keymaps({ buffer = bufnr, preserve_mappings = true })
	lsp.buffer_autoformat()

	vim.keymap.set({ 'n', 'x' }, '<leader>lf', function()
		vim.lsp.buf.format({ async = false, timeout_ms = 10000 })
	end)


	if client.server_capabilities.signatureHelpProvider then
		local overloads = require('lsp-overloads')
		overloads.setup(client, {})
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

local neodev = require('neodev')

neodev.setup({
	library = {
		plugins = {
			'nvim-dap-ui',
			types = true
		}
	}
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

lspconfig.lua_ls.setup(lsp.nvim_lua_ls())
lspconfig.omnisharp.setup({})



-- signature.setup {
-- 	bind = true,
-- 	handler_opts = {
-- 		border = 'rounded'
-- 	},
-- 	max_width = 130,
-- 	wrap = true,
-- 	floating_window = true,
-- 	always_trigger = true,
-- }


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

lspconfig.lua_ls.setup(lsp.nvim_lua_ls())

require('lsp_lines').setup()
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
	sources = {
		{ name = 'path' },
		-- { name = 'buffer' },
		{ name = 'nvim_lsp' },
		{ name = 'nvim_lua' },
		{ name = 'luasnip' },
		-- { name = 'nvim_lsp_signature_help' }
	},
	snippet = {
		expand = function(args)
			local luasnip = require('luasnip')
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
	end,
})


local null = require('null-ls')

null.setup({
	sources = {
		-- null.builtins.formatting.prettier,
		-- null.builtins.diagnostics.eslint,
		-- null.builtins.formatting.stylua,
	}
})



require('mason').setup()
require('mason-null-ls').setup({
	automatic_setup = true,
})
