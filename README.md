# Neovim-Moaid
My Neovim Configuration

# Installation for Windows
* Install Lazy.vim (Read [documentation](https://github.com/folke/lazy.nvim) for updated steps)
	
* Update `XDG_CONFIG_HOME` if needed

* Winget 0.8.3 at least is needed

* Other dependencies
	* Zig - make sure to use a stable release
   		- `winget install zig.zig` (__slow to install__)
	* fd
   		- `winget install sharkdp.fd`
	* WinGnu32.Make or Kitware.CMake
   		- `winget install Kitware.CMake`
	* ripgrep
   		- `winget install BurntSushi.ripgrep.MSVC`
 	* lazygit
		- `JesseDuffield.lazygit`
  	* netcoredbg
  	  	- https://github.com/Samsung/netcoredbg
	* jq (for nvim-rest)
   		- `winget install jqlang.jq`
	* html-tidy (for nvim-rest)
   		- https://github.com/htacg/tidy-html5
