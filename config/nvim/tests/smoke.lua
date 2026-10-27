-- Loaded before init.lua by run.lua, so startup errors are included.
vim.g.auto_session_enabled = false
vim.o.lines = 45
vim.o.columns = 120
local errors = {}
vim.notify = function(message, level)
	if (level or vim.log.levels.INFO) >= vim.log.levels.ERROR then
		table.insert(errors, tostring(message))
	end
end

local function wait_for(predicate, message)
	assert(vim.wait(5000, predicate, 20), message)
end

local function mapping(lhs)
	return assert(vim.fn.maparg(lhs, "n", false, true).callback, "Missing mapping: " .. lhs)
end

local function check_picker(query, expected_count)
	local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
	local complete = false
	picker:register_completion_callback(function() complete = true end)
	picker:reset_prompt(query)
	local finished = vim.wait(5000, function() return complete end, 20)
	assert(finished, "Picker did not finish: " .. query .. " " .. vim.inspect({
		closed = picker.closed, results = picker.manager and picker.manager:num_results(),
		prompt = vim.api.nvim_buf_is_valid(picker.prompt_bufnr) and picker:_get_prompt(),
	}))
	assert(picker.manager:num_results() == expected_count,
		("Expected %d results for %q, got %d"):format(expected_count, query, picker.manager:num_results()))
	require("telescope.actions").close(picker.prompt_bufnr)
end

local function check_completion()
	require("lazy").load({ plugins = { "nvim-cmp", "cmp-cmdline" } })
	local sources = {}
	for _, source in pairs(require("cmp").core.sources) do sources[source.name] = source.source end
	for _, name in ipairs({ "buffer", "path", "luasnip", "cmdline" }) do
		assert(sources[name], "Completion source not registered: " .. name)
	end

	vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(vim.fn.getcwd(), "visible file.txt")))
	local result
	sources.buffer:complete({ option = {}, offset = 1, context = { cursor_before_line = "CONFIG" } },
		function(items) result = items.items end)
	wait_for(function() return result ~= nil end, "Buffer completion timed out")
	assert(vim.iter(result):any(function(item) return item.label == "CONFIG_SMOKE_TOKEN" end), "Buffer completion is empty")

	result = nil
	sources.path:complete({
		option = { get_cwd = function() return vim.fn.getcwd() end }, offset = 3,
		context = { bufnr = vim.api.nvim_get_current_buf(), cursor_before_line = "./v" },
	}, function(items) result = items end)
	wait_for(function() return result ~= nil end, "Path completion timed out")
	assert(vim.iter(result):any(function(item) return item.label == "visible file.txt" end), "Path completion is empty")
end

local function check_terminal()
	require("lazy").load({ plugins = { "toggleterm.nvim" } })
	local shell = require("toggleterm.config").get("shell")
	if vim.fn.has("win32") == 0 then assert(shell == vim.o.shell, "Unix shell was overridden") end
	-- Exercise the configured shell without profiles or interactive stdin.
	local flag = shell:find("pwsh", 1, true) and " -NoProfile -Command"
		or (shell:find("cmd.exe", 1, true) and " /c" or " -c")
	local cmd = shell .. flag .. ' "echo CONFIG_TERMINAL_OK"'
	local exit_code
	local term = require("toggleterm.terminal").Terminal:new({
		cmd = cmd, direction = "horizontal", close_on_exit = false,
		on_exit = function(_, _, code) exit_code = code end,
	})
	term:open()
	assert(term.job_id and term.job_id > 0, "Terminal failed to start")
	wait_for(function() return exit_code ~= nil end, "Configured shell did not execute a command")
	assert(exit_code == 0, "Configured shell command failed")
	local escape = vim.api.nvim_buf_call(term.bufnr, function() return vim.fn.maparg("<Esc>", "t", false, true) end)
	assert((escape.rhs or ""):lower() == "<c-\\><c-n>", "Escape does not leave an ordinary terminal")
	term:shutdown()

	-- Exercise the TUI mappings without launching an interactive application.
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "term://test-directory//123:opencode")
	vim.api.nvim_exec_autocmds("TermOpen", { buffer = buf, group = "custom-terminal-group" })
	escape = vim.api.nvim_buf_call(buf, function() return vim.fn.maparg("<Esc>", "t", false, true) end)
	assert((escape.rhs or ""):lower() == "<esc>", "Escape was not passed through to a TUI")
	vim.api.nvim_buf_delete(buf, { force = true })
end

local function check_power_review(expected)
	local neo_tree = require("neo-tree").ensure_config()
	local extension = rawget(require("telescope").extensions, "power_review")
	assert(vim.tbl_contains(neo_tree.sources, "power_review") == expected, "Incorrect Neo-tree sources")
	assert((extension ~= nil) == expected, "Incorrect Telescope extensions")
	assert((vim.fn.exists(":PowerReview") == 2) == expected, "Incorrect PowerReview command availability")
	if not expected then
		assert(vim.tbl_isempty(vim.fn.maparg("<leader>pr", "n", false, true)), "Stale PowerReview keymap")
		return
	end

	local pr = require("power-review")
	assert(vim.deep_equal(require("power-review.config").get().cli.executable, { "dnx", "--yes", "PowerReview", "--" }),
		"CLI configuration was not applied before integrations loaded")
	pr._set_current_session({
		id = "config-smoke-test", pr_id = 123, pr_title = "Configuration smoke test",
		source_branch = "HEAD", target_branch = "HEAD", worktree_path = vim.fn.getcwd(),
		files = { { path = "visible file.txt", change_type = "edit", additions = 1, deletions = 0 } },
	})
	vim.cmd("Neotree focus source=power_review")
	local state = require("neo-tree.sources.manager").get_state("power_review")
	wait_for(function() return state.tree and state.tree:get_node("file:visible file.txt") ~= nil end,
		"PowerReview files panel did not render")
	assert(state.window.mappings.v == "toggle_reviewed", "Review-status mappings were lost")
	vim.cmd("Neotree close")
	extension.changed_files({ previewer = false })
	check_picker("visible", 1)

	local statusline = require("power-review.statusline")
	assert(statusline.get():find("PR #123", 1, true), "Review statusline did not render")
	local components = require("lualine").get_config().sections.lualine_b
	assert(vim.iter(components):any(function(component)
		return type(component) == "table" and component[1] == statusline.get
	end), "PowerReview statusline component is missing")
	pr._set_current_session(nil)
end

vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		vim.schedule(function()
			local ok, err = xpcall(function()
				local plugins = require("lazy.core.config").plugins
				-- lazy.nvim waits for an attached UI before firing VeryLazy.
				vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
				wait_for(function() return plugins["which-key.nvim"]._.loaded ~= nil end, "VeryLazy startup did not complete")
				local expected_dir = vim.env.NVIM_TEST_EXPECTED_PR or ""
				local expected = expected_dir ~= ""
				assert((plugins["power-review.nvim"] ~= nil) == expected, "Incorrect PowerReview plugin spec")
				if expected then
					assert(require("config.power-review").dir == vim.fs.normalize(expected_dir), "Incorrect checkout resolution")
				end

				local first = vim.env.NVIM_TEST_FIRST
				if first == "neo-tree" then
					vim.cmd("Neotree focus filesystem")
					vim.cmd("Neotree close")
				elseif first == "PowerReview" then
					vim.cmd("PowerReview files")
				else
					require("telescope.builtin").find_files({ previewer = false })
					check_picker("visible", 1)
				end
				require("lazy").load({ plugins = { "neo-tree.nvim", "telescope.nvim" } })
				assert(rawget(require("telescope").extensions, "ui-select"), "UI-select failed to load")
				check_power_review(expected)

				if vim.env.NVIM_TEST_FULL == "1" then
					mapping("<leader>sf")()
					check_picker("visible  *.txt", 1)
					mapping("<leader>sg")()
					check_picker("CONFIG_SMOKE_TOKEN", 1)
					mapping("<leader>sG")()
					check_picker("CONFIG_SMOKE_TOKEN", 3)
					check_completion()
					mapping("<leader>tf")()
					local state = require("neo-tree.sources.manager").get_state("filesystem")
					wait_for(function() return state.tree and state.tree:get_node() and state.tree:get_node().name == "visible file.txt" end,
						"Neo-tree did not reveal a filename containing spaces")
					vim.cmd("Neotree close")
					assert(require("nvim-treesitter.configs").get_module("highlight").enable, "Treesitter configuration failed")
					check_terminal()
				end
			end, debug.traceback)

			-- Let scheduled notifications finish before checking for errors.
			vim.schedule(function()
				local terminals = package.loaded["toggleterm.terminal"]
				if terminals then
					for _, term in ipairs(terminals.get_all(true)) do pcall(term.shutdown, term) end
				end
				for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
				if not ok then table.insert(errors, err) end
				local messages = vim.api.nvim_exec2("messages", { output = true }).output
				if messages:match("E%d+:") or messages:find("stack traceback", 1, true) then
					table.insert(errors, messages)
				end
				if #errors > 0 then
					io.stderr:write(table.concat(errors, "\n") .. "\n")
					vim.cmd("cquit 1")
				else
					vim.cmd("qa!")
				end
			end)
		end)
	end,
})
