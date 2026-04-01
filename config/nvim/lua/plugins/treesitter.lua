return {
	'nvim-treesitter/nvim-treesitter',
	build = ':TSUpdate',
	event = { "BufReadPost", "BufNewFile" },
	dependencies = {
		'nvim-treesitter/nvim-treesitter-textobjects',
	},
	config = function()
		-- Workaround for Neovim 0.12.0 bug: treesitter's async parsing of injected
		-- languages (e.g. markdown_inline in markdown) can produce invalidated nodes
		-- whose :range() method is nil, crashing the highlighter.
		-- Wrap vim.treesitter.get_range to silently catch these stale-node errors.
		-- TODO: Remove when fixed upstream in a future Neovim release
		local original_get_range = vim.treesitter.get_range
		vim.treesitter.get_range = function(node, source, metadata)
			local ok, result = pcall(original_get_range, node, source, metadata)
			if ok then
				return result
			end
			-- Return a zero-width range so the caller can continue without crashing
			return { 0, 0, 0, 0, 0, 0 }
		end

		local config = require('nvim-treesitter.configs')
		config.setup({
			auto_install = true,
			sync_install = false,
			highlight = {
				enable = true,
				additional_vim_regex_highlighting = false
			},
			indent = {
				enable = true,
			},
			textobjects = {
				move = {
					enable = true,
					set_jumps = true,
					goto_next_start = {
						["]m"] = "@function.outer",
						["]c"] = "@class.outer",
					},
					goto_next_end = {
						["]M"] = "@function.outer",
						["]C"] = "@class.outer",
					},
					goto_previous_start = {
						["[m"] = "@function.outer",
						["[c"] = "@class.outer",
					},
					goto_previous_end = {
						["[M"] = "@function.outer",
						["[C"] = "@class.outer",
					},
				},
				select = {
					enable = true,
					lookahead = true,
					keymaps = {
						["af"] = "@function.outer",
						["if"] = "@function.inner",
						["am"] = "@function.outer",
						["im"] = "@function.inner",
						["ac"] = "@class.outer",
						["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
						["ib"] = "@block.inner",
						["ab"] = "@block.outer",
						["iP"] = "@parameter.inner",
						["aP"] = "@parameter.outer",
					}
				}
			}
		})
	end
}
