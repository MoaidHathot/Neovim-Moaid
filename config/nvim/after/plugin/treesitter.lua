require 'nvim-treesitter.configs'.setup {
	-- A list of parser names, or "all" (the five listed parsers should always be installed)
	ensure_installed = { "javascript", "typescript", "c", "lua", "vim", "vimdoc", "query" },
	-- Install parsers synchronously (only applied to `ensure_installed`
	sync_install = false,
	-- Automatically install missing parsers when entering buffe
	-- Recommendation: set to false if you don't have `tree-sitter` CLI installed locall
	auto_install = true,
	---- If you need to change the installation directory of the parsers (see -> Advanced Setup)
	-- parser_install_dir = "/some/path/to/store/parsers", -- Remember to run vim.opt.runtimepath:append("/some/path/to/store/parsers")!

	highlight = {
		enable = true,
		indent = { enable = true },
		-- incremental_selection = {
		-- 	enabled = true,
		-- 	keymaps = {
		-- 		init_select = '<C-space>',
		-- 		node_incremental = '<C-space>',
		-- 		node_decremental = '<C-space>u',
		-- 		scope_incremental = '<C-space>o',
		-- 	}
		--
		-- },

		-- Setting this to true will run `:h syntax` and tree-sitter at the same time.
		-- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
		-- Using this option may slow down your editor, and you may see some duplicate highlights.
		-- Instead of true it can also be a list of languages
		additional_vim_regex_highlighting = false,
	},
	rainbow = {
		enable = true,
		query = 'rainbow-parents',
		strategy = require('ts-rainbow').strategy.global
	}
}
