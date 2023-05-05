local lsp = require('lsp-zero').preset({})

local signature = require('lsp_signature')
lsp.on_attach(function(client, bufnr)
	lsp.default_keymaps({ buffer = bufnr })
	lsp.buffer_autoformat()

	vim.keymap.set({ 'n', 'x' }, '<leader>lf', function()
		vim.lsp.buf.format({ async = false, timeout_ms = 10000 })
	end)

	signature.on_attach({
		bind = true,
		handler_opts = {
			border = 'rounded'
		}
	}, bufnr)

	-- vim.keymap.set('n', '<leader>le', "<cmd>Telescope lsp_references<CR>", {buffer = true})
end)

vim.keymap.set({ 'n' }, '<C-k>', function()
		signature.toggle_float_win()
	end,
	{ silent = true, desc = 'toggle signature' })

vim.keymap.set({ 'n', }, 'gs', function()
		vim.lsp.buf.signature_help()
	end,
	{ silent = true, desc = 'toggle signature' })


-- (Optional) Configure lua language server for neovim
local lspconfig = require('lspconfig')
lspconfig.lua_ls.setup(lsp.nvim_lua_ls())

lsp.ensure_installed({
	--'tsserver',
	--'eslint',
	--'Omnisharp',
	--'sumneko_lua',
	-- 'rust_analyzer'
})

local cmp = require('cmp')
local cmp_select = { behavior = cmp.SelectBehavior.Select }

local cmp_mappings = lsp.defaults.cmp_mappings({
	['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
	['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
	['<C-y>'] = cmp.mapping.confirm({ select = true }),
	['<CR>'] = cmp.mapping.confirm({ select = true }),
	['<Tab>'] = cmp.mapping.confirm({ select = true }),
	['<C-space>'] = cmp.mapping.complete(),
})

cmp.setup {
	-- sources = {
	-- 	name = 'nvim_lsp'
	-- }

}

-- local capabilities = require('cmp_nvim_lsp').default_capabilities()
-- lspconfig['Omnisharp'].setup {
-- 	capabilities = capabilities
-- }


lsp.setup_nvim_cmp({
	mapping = cmp_mappings
})

--lsp.set_preferences({ sign_icons = {} })

lsp.setup()
