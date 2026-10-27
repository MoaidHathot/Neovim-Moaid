local function augroup(name)
	return vim.api.nvim_create_augroup("moaid_" .. name, { clear = true })
end

local function is_tui_terminal(buf)
	-- A terminal name also contains its working directory. Match only the
	-- command, so editing inside an "opencode" directory does not trap Escape.
	local command = vim.api.nvim_buf_get_name(buf):match("^term://.-//%d+:(.*)$") or ""
	command = command:lower()
	for _, name in ipairs({ "opencode", "lazygit", "copilot", "sidekick" }) do
		if command:find(name, 1, true) then
			return true
		end
	end
	return false
end

-- auto format file on save
-- vim.cmd [[autocmd BufWritePre * lua vim.lsp.buf.format()]]

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	group = augroup("highlight_yank"),
	callback = function()
		vim.highlight.on_yank()
	end,
})

-- resize splits if window got resized
vim.api.nvim_create_autocmd({ "VimResized" }, {
	group = augroup("resize_splits"),
	callback = function()
		vim.cmd("tabdo wincmd =")
	end,
})

-- go to last loc when opening a buffer
vim.api.nvim_create_autocmd("BufReadPost", {
	group = augroup("last_loc"),
	callback = function()
		local exclude = { "gitcommit" }
		local buf = vim.api.nvim_get_current_buf()
		if vim.tbl_contains(exclude, vim.bo[buf].filetype) then
			return
		end
		local mark = vim.api.nvim_buf_get_mark(buf, '"')
		local lcount = vim.api.nvim_buf_line_count(buf)
		if mark[1] > 0 and mark[1] <= lcount then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- close some filetypes with <q>
vim.api.nvim_create_autocmd("FileType", {
	group = augroup("close_with_q"),
	pattern = {
		"PlenaryTestPopup",
		"help",
		"lspinfo",
		"man",
		"notify",
		"qf",
		"spectre_panel",
		"startuptime",
		"tsplayground",
		"neotest-output",
		"checkhealth",
		"neotest-summary",
		"neotest-output-panel",
	},
	callback = function(event)
		vim.bo[event.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
	end,
})

-- wrap and check for spell in text filetypes
vim.api.nvim_create_autocmd("FileType", {
	group = augroup("wrap_spell"),
	pattern = { "gitcommit", "markdown" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
})

-- Set 'writebackup' to false for d2 filetype because the D2 CLI can't handle nvim's backup files
vim.api.nvim_create_autocmd("FileType", {
    pattern = "d2",
    callback = function()
        vim.bo[0].writebackup = false
    end,
})

vim.api.nvim_create_autocmd("TermOpen", {
	group = vim.api.nvim_create_augroup("custom-terminal-group", { clear = true }),
	callback = function(event)
		local bufnr = event.buf
		if is_tui_terminal(bufnr) then
			-- Pass <Esc> through to the terminal application
			vim.keymap.set("t", "<Esc>", "<Esc>", { buffer = bufnr, noremap = true, silent = true })
			return
		end

		-- Default: <Esc> exits terminal mode
		vim.keymap.set("t", "<esc>", "<C-\\><C-n>", { buffer = bufnr, silent = true })
	end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*/chart/templates/*.yaml", "*/chart/templates/*.yml" },
  callback = function()
    vim.bo.filetype = "helm"
  end,
})

-- Auto-enter terminal mode for TUI applications (OpenCode, lazygit, etc.)
-- This prevents Neovim's normal mode from interfering with the application's keybindings
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
	group = augroup("tui-auto-terminal-mode"),
	callback = function(event)
		if vim.bo[event.buf].buftype == "terminal" and is_tui_terminal(event.buf) then
			vim.cmd("startinsert")
		end
	end,
})

-- Screen clearing on exit is handled by the PowerShell wrapper function
-- (moaid) in profile.ps1, which runs *after* nvim exits and reliably
-- restores the terminal even if nvim crashes. (neovim#30175, terminal#17874)
