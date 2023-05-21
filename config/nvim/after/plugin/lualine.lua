local lualine = require('lualine')


local function get_lsp_name()
	local msg = "LS Inactive"
	local buf_clients = vim.lsp.get_active_clients()
	-- local buf_clients = vim.lsp.buf_get_clients()
	if next(buf_clients) == nil then
		if type(msg) == "boolean" or #msg == 0 then
			return "LS Inactive"
		end
	end
	-- end
	local buf_client_names = {}
	local copilot_active = false


	for _, client in pairs(buf_clients) do
		table.insert(buf_client_names, client.name)

		if client.name == "copilot" then
			copilot_active = true
		end
	end

	local unique_client_names = vim.fn.uniq(buf_client_names)

	local language_servers = "[" .. table.concat(unique_client_names, ", ") .. "]"

	-- return language_servers;
	-- end

	-- if copilot_active then
	-- 	language_servers = language_servers .. "#SLCopilot#" .. "" --.. "%*"
	-- end
	--
	return language_servers
end

lualine.setup {
	options = {
		-- component_separators = { left = '|', right = "|" },
		theme = 'auto',
		icon_enabled = true,
	},
	sections = {
		lualine_x = {
			{ get_lsp_name },
			'selectioncount',
			'filetype'
		},
		-- lualine_c = {
		-- 	'filetype'
		-- }
		-- lualine_b = {
		-- 'diagnostics'
		-- 'diff',
		-- 'diagnostics',

		-- sources = { 'nvim_diagnostic', 'nvim_lsp' },
		-- sections = { 'error', 'warn', 'info', 'hint' },
		-- }
	}
}
