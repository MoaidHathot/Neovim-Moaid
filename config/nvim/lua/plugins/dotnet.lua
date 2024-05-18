return {
	{
		'MoaidHathot/dotnet.nvim',
		cmd = "DotnetUI",
		config = function()
			require('dotnet').setup()
		end
	}
}
