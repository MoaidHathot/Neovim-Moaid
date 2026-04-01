return {
	"kevinhwang91/nvim-ufo",
	event = { "BufReadPost", "BufNewFile" },
	dependencies = {
		"kevinhwang91/promise-async",
	},
	keys = {
		{ "zR", function() require("ufo").openAllFolds() end, desc = "Open All Folds" },
		{ "zM", function() require("ufo").closeAllFolds() end, desc = "Close All Folds" },
		{ "zr", function() require("ufo").openFoldsExceptKinds() end, desc = "Open Folds Except Kinds" },
		{ "zm", function() require("ufo").closeFoldsWith() end, desc = "Close Folds With" },
		{ "zK", function()
			local winid = require("ufo").peekFoldedLinesUnderCursor()
			if not winid then
				vim.lsp.buf.hover()
			end
		end, desc = "Peek Fold / Hover" },
	},
	opts = {
		provider_selector = function(_, filetype, _)
			-- Use treesitter with indent as fallback
			-- LSP-capable filetypes get lsp provider first
			local lsp_fts = { "cs", "vb", "lua" }
			if vim.tbl_contains(lsp_fts, filetype) then
				return { "lsp", "indent" }
			end
			return { "treesitter", "indent" }
		end,
	},
}
