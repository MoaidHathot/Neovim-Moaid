require 'nvim-treesitter.configs'.setup {
	-- A list of parser names, or "all" (the five listed parsers should always be installed)
	ensure_installed = { "javascript", "typescript", "c", "lua", "vim", "vimdoc", "query", "c_sharp", "bicep", "yaml",
		"python", 'http', 'json', 'html' },
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
	},
	textobjects = {
		select = {
			enable = true,

			-- Automatically jump forward to textobj, similar to targets.vim
			lookahead = true,

			keymaps = {
				-- You can use the capture groups defined in textobjects.scm
				['aa'] = '@parameter.outer',
				['ia'] = '@parameter.inner',
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				-- ["al"] = "@loop.outer",
				-- ["il"] = "@loop.inner",
				["ac"] = "@class.outer",
				-- You can optionally set descriptions to the mappings (used in the desc parameter of
				-- nvim_buf_set_keymap) which plugins like which-key display
				["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
				-- You can also use captures from other query groups like `locals.scm`
				-- ["as"] = { query = "@scope", query_group = "locals", desc = "Select language scope" },
			},
			-- You can choose the select mode (default is charwise 'v')
			--
			-- Can also be a function which gets passed a table with the keys
			-- * query_string: eg '@function.inner'
			-- * method: eg 'v' or 'o'
			-- and should return the mode ('v', 'V', or '<c-v>') or a table
			-- mapping query_strings to modes.
			selection_modes = {
				['@parameter.outer'] = 'v', -- charwise
				['@function.outer'] = 'V', -- linewise
				['@class.outer'] = '<c-q>', -- blockwise
			},
			-- If you set this to `true` (default is `false`) then any textobject is
			-- extended to include preceding or succeeding whitespace. Succeeding
			-- whitespace has priority in order to act similarly to eg the built-in
			-- `ap`.
			--
			-- Can also be a function which gets passed a table with the keys
			-- * query_string: eg '@function.inner'
			-- * selection_mode: eg 'v'
			-- and should return true of false
			include_surrounding_whitespace = true,
		},
		swap = {
			enable = true,
			swap_next = {
				["<leader>m<Right>"] = "@parameter.inner",
			},
			swap_previous = {
				["<leader>m<Left>"] = "@parameter.inner",
			},
		},
		move = {
			enable = true,
			set_jumps = true, -- whether to set jumps in the jumplist
			goto_next_start = {
				["]f"] = "@function.outer",
				["]]"] = { query = "@class.outer", desc = "Next class start" },
				--
				-- You can use regex matching (i.e. lua pattern) and/or pass a list in a "query" key to group multiple queires.
				["]l"] = "@loop.*",
				-- ["]o"] = { query = { "@loop.inner", "@loop.outer" } }
				--
				-- You can pass a query group to use query from `queries/<lang>/<query_group>.scm file in your runtime path.
				-- Below example nvim-treesitter's `locals.scm` and `folds.scm`. They also provide highlights.scm and indent.scm.
				-- ["]s"] = { query = "@scope", query_group = "locals", desc = "Next scope" },
				["]z"] = { query = "@fold", query_group = "folds", desc = "Next fold" },
			},
			goto_next_end = {
				["]F"] = "@function.outer",
				["]["] = "@class.outer",
			},
			goto_previous_start = {
				["[f"] = "@function.outer",
				["[l"] = "@loop.*",
				["[["] = "@class.outer",
			},
			goto_previous_end = {
				["[F"] = "@function.outer",
				["[]"] = "@class.outer",
			},
			-- Below will go to either the start or the end, whichever is closer.
			-- Use if you want more granular movements
			-- Make it even more gradual by adding multiple queries and regex.
			goto_next = {
				["]i"] = "@conditional.outer",
			},
			goto_previous = {
				["[i"] = "@conditional.outer",
			}
		},
		-- incremental_selection = {
		-- 	enable = true,
		-- 	keymaps = {
		-- 		-- mappings for incremental selection (visual mappings)
		-- 		init_selection = "gnn", -- maps in normal mode to init the node/scope selection
		-- 		node_incremental = "grn", -- increment to the upper named parent
		-- 		scope_incremental = "grc", -- increment to the upper scope (as defined in locals.scm)
		-- 		node_decremental = "grm", -- decrement to the previous node
		-- 	},
		-- },
	},
}
