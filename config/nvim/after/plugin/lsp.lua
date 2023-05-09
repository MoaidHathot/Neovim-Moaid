local zero = require('lsp-zero')
local lsp = zero.preset('recommended')
-- local lsp = zero.preset({
-- 	name = 'recommended',
-- 	set_lsp_keymaps = true,
-- 	manage_nvim_cmp = true,
-- 	suggest_lsp_servers = true
-- })
local cmp_action = zero.cmp_action()

local signature = require('lsp_signature')
local overloads = require('lsp-overloads')
local hints = require('lsp-inlayhints')
-- local navic = require('nvim-navic')

lsp.on_attach(function(client, bufnr)
	lsp.default_keymaps({ buffer = bufnr, preserve_mappings = false })
	-- lsp.default_keymaps({ buffer = bufnr, preserve_mappings = true })
	lsp.buffer_autoformat()

	vim.keymap.set({ 'n', 'x' }, '<leader>lf', function()
		vim.lsp.buf.format({ async = false, timeout_ms = 10000 })
	end)

	-- signature.on_attach({
	-- 	bind = true,
	-- 	handler_opts = {
	-- 		border = 'rounded'
	-- 	},
	-- 	max_width = 130,
	-- 	wrap = true,
	-- }, bufnr)
	--

	-- if client.server_capabilities.documentSymbolProvider then
	-- 	-- require('nvim-navic').attach(client, bufnr)
	-- 	navic.attach(client, bufnr)
	-- end

	if client.server_capabilities.signatureHelpProvider then
		overloads.setup(client, {})
	end

	hints.on_attach(client, bufnr)

	-- vim.keymap.set('n', '<leader>le', "<cmd>Telescope lsp_references<CR>", {buffer = true})
	-- bind('n', '<leader>r', '<cmd> lua vim.lsp.buf.rename()<cr>')
end)

hints.setup()

vim.keymap.set('n', '<leader>lh', "<cmd>lua require('lsp-inlayhints').toggle()<CR>")

signature.setup {
	bind = true,
	handler_opts = {
		border = 'rounded'
	},
	max_width = 130,
	wrap = true,
	floating_window = false,
}

-- vim.keymap.set({ 'n' }, '<C-k>', function()
-- 		signature.toggle_float_win()
-- 	end,
-- 	{ silent = true, desc = 'toggle signature' })

-- vim.keymap.set({ 'n' }, '<C-l>', function()
-- 		signature.signature_help()
-- 	end,
-- 	{ silent = true, desc = 'toggle signature' })
--
vim.keymap.set({ 'n', }, 'gs', function()
		vim.lsp.buf.signature_help()
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
lspconfig.lua_ls.setup(lsp.nvim_lua_ls())

lsp.ensure_installed({
	--'tsserver',
	--'eslint',
	-- 'Omnisharp',
	-- 'sumneko_lua',
	-- 'rust_analyzer'
})

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

--lsp.set_preferences({ sign_icons = {} })

lspconfig.lua_ls.setup(lsp.nvim_lua_ls())
lsp.setup()

-- local null_ls = require('null-ls')
--
-- null_ls.setup({
-- 	sources = {
--
-- 	}
-- })
--
local luasnip = require('luasnip')

cmp.setup {
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
			luasnip.lsp_expand(args.body)
		end
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
