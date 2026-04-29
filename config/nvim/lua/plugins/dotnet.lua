local function normalize_path(path)
	if not path or path == "" then
		return nil
	end

	return vim.fs.normalize(path)
end

local function find_upward(buf, patterns)
	local file = vim.api.nvim_buf_get_name(buf or 0)
	local path = file ~= "" and file or vim.fn.getcwd()
	local found = vim.fs.find(patterns, { upward = true, path = path, limit = 1 })[1]
	return normalize_path(found)
end

local function dotnet_target(buf)
	local selected_solution = normalize_path(vim.g.roslyn_nvim_selected_solution)
	if selected_solution then
		return selected_solution
	end

	return find_upward(buf, function(name)
		return name:match("%.slnx$") or name:match("%.sln$") or name:match("%.slnf$") or name:match("%.csproj$")
	end)
end

local function dotnet_project(buf)
	return find_upward(buf, function(name)
		return name:match("%.csproj$") ~= nil
	end)
end

local function run_dotnet(command, target)
	local Terminal = require("toggleterm.terminal").Terminal
	local quoted_target = target and target ~= "" and string.format(' "%s"', target) or ""
	local term = Terminal:new({
		id = 5,
		direction = "horizontal",
		size = 20,
		close_on_exit = false,
	})

	term:open()
	term:send("dotnet " .. command .. quoted_target .. "\n")
end

local function run_dotnet_for_target(command)
	local target = dotnet_target(0)
	if not target then
		vim.notify("No .sln/.slnx/.slnf/.csproj found", vim.log.levels.WARN, { title = ".NET" })
		return
	end

	run_dotnet(command, target)
end

local function run_dotnet_for_project(command)
	local project = dotnet_project(0)
	if not project then
		vim.notify("No .csproj found", vim.log.levels.WARN, { title = ".NET" })
		return
	end

	run_dotnet(command, project)
end

return {
	{
		'MoaidHathot/dotnet.nvim',
		-- enabled = false,
		branch = 'dev',
		cmd = "DotnetUI",
		keys = {
			{ '<leader>/', mode = { 'n', 'v' } },
			{ '<leader>nb', function() run_dotnet_for_target("build") end, mode = 'n', desc = '.NET build target', silent = true },
			{ '<leader>nB', function() run_dotnet_for_project("build") end, mode = 'n', desc = '.NET build project', silent = true },
			{ '<leader>nt', function() run_dotnet_for_project("test") end, mode = 'n', desc = '.NET test project', silent = true },
			{ '<leader>nT', function() run_dotnet_for_target("test") end, mode = 'n', desc = '.NET test target', silent = true },
			{ '<leader>ns', function() run_dotnet_for_target("restore") end, mode = 'n', desc = '.NET restore target', silent = true },
			{ '<leader>nr', function() run_dotnet_for_project("run --project") end, mode = 'n', desc = '.NET run project', silent = true },
			{ '<leader>na', "<cmd>DotnetUI new_item<CR>", mode = { 'n', 'v' }, desc = '.NET new item', silent = true },
			{ '<leader>nf', "<cmd>DotnetUI file bootstrap<CR>", mode = { 'n', 'v' }, desc = '.NET bootstrap class', silent = true },
			{ '<leader>nRa', "<cmd>DotnetUI project reference add<CR>", mode = { 'n', 'v' }, desc = '.NET add project reference', silent = true },
			{ '<leader>nRr', "<cmd>DotnetUI project reference remove<CR>", mode = { 'n', 'v' }, desc = '.NET remove project reference', silent = true },
			{ '<leader>npa', "<cmd>DotnetUI project package add<CR>", mode = { 'n', 'v' }, desc = '.NET add project package', silent = true },
			{ '<leader>npr', "<cmd>DotnetUI project package remove<CR>", mode = { 'n', 'v' }, desc = '.NET remove project package', silent = true },
		},
		opts = {
			bootstrap = {
				auto_bootstrap = false,
			}
			-- project_selection = {
			-- 	path_display = 'filename_first',
			-- }
		},
	}
}
