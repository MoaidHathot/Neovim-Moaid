local dap = require('dap')

local log = require('structlog')

local function getHighestVersionDirectory(dir)
	local command = 'dir /B ' .. dir -- For Windows, use 'dir /B ' .. dir instead
	local max_version, max_dir = -1, ''
	local p = io.popen(command)
	local lines = p:lines()
	for dirname in lines do
		local version = tonumber(dirname:match('net(%d+%.%d+)'))
		if version and version > max_version then
			max_version = version
			max_dir = dirname
		end
	end
	if p ~= nil then
		p:close()
	end

	return max_dir
end

local function getDotnetCoreDebugger()
	local directory_name = 'netcoredbg'
	local file_name = '/netcoredbg'

	local main = "E:/Program Files/Programs/" .. directory_name
	local secondary = "C:/Program Files/" .. directory_name

	local found_main = vim.fn.finddir(main, "");
	if found_main ~= ""
	then
		-- print('netcore: ' .. main .. file_name)
		return main .. file_name
	end

	local found_secondary = vim.fn.finddir(secondary, "");
	if found_secondary ~= ""
	then
		-- print('netcore: ' .. secondary .. file_name)
		return secondary .. file_name
	end

	return nil
end

dap.adapters.coreclr = {
	type = 'executable',
	command = getDotnetCoreDebugger(),
	args = { '--interpreter=vscode' }
	-- args = { '--interpreter=vscode', '--log=file' }
}

Moaid_config = {
	debug_dllPath = nil
}

dap.configurations.cs = {
	{
		type = "coreclr",
		name = "launch - netcoredbg",
		request = "launch",
		program = function()
			local path = vim.fn.getcwd()
			local logger = log.get_logger('moaid_vim')
			logger:info('Path is: ' .. path)
			local sep = path:match('[/\\]') -- Get the path separator used (either / or \)
			local last_dir = path:match('([^' .. sep .. ']+' .. sep .. '?)$')
			local project_name = last_dir:sub(1, -1) -- Remove the trailing separator if it exists
			local version_directory = path .. "\\bin\\Debug"
			local latest_version = getHighestVersionDirectory(version_directory);
			-- logger:info('Hieghest version: ' .. latest_version)
			local executable_path = version_directory .. "\\" .. latest_version .. "\\" .. project_name .. ".dll"
			-- local tokens = string.gmatch(path, "\\")
			-- local project_name = tokens[#(tokens) - 1] .. "\\"
			if (Moaid_config.debug_dllPath ~= nill) then
				executable_path = Moaid_config.debug_dllPath
			end

			local result = vim.fn.input('Path to dll: ', executable_path, 'file')
			Moaid_config.debug_dllPath = result
			-- logger:info('Result: ' .. result)
			return result
		end,
		-- env = {},
		-- cwd = ""
	},
}

require('nvim-dap-virtual-text').setup()

local dapui = require('dapui')

dap.listeners.after.event_initialized['dapui_config'] = function()
	dapui.open()
end

dap.listeners.before.event_terminated['dapui_config'] = function()
	dapui.close()
end

dap.listeners.before.event_exited['dapui_config'] = function()
	dapui.close()
end


dapui.setup()


vim.keymap.set('n', '<leader>dt', "<cmd>:lua require('dap').toggle_breakpoint()<CR>")
vim.keymap.set('n', '<F9>', "<cmd>:lua require('dap').toggle_breakpoint()<CR>")
vim.keymap.set('n', '<leader>ds', "<cmd>:lua require('dap').continue()<CR>")
vim.keymap.set('n', '<F5>', "<cmd>:lua require('dap').continue()<CR>")
vim.keymap.set('n', '<leader>di', "<cmd>:lua require('dap').step_into()<CR>")
vim.keymap.set('n', '<F11>', "<cmd>:lua require('dap').step_into()<CR>")
vim.keymap.set('n', '<leader>dO', "<cmd>:lua require('dap').step_out()<CR>")
vim.keymap.set('n', '<S-F11>', "<cmd>:lua require('dap').step_out()<CR>")
vim.keymap.set('n', '<leader>do', "<cmd>:lua require('dap').step_over()<CR>")
vim.keymap.set('n', '<F10>', "<cmd>:lua require('dap').step_over()<CR>")
vim.keymap.set('n', '<leader>du', "<cmd>:lua require('dapui').toggle()<CR>")
