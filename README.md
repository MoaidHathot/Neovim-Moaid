# Neovim-Moaid
My Neovim Configuration

# Installation for Windows
* Install Lazy.vim (Read [documentation](https://github.com/folke/lazy.nvim) for updated steps)
	
* Update `XDG_CONFIG_HOME` if needed
    - Should point to the `config/` folder in this repo.
    - For example: `C:\Github\Neovim-Moaid\config`

* Winget 0.8.3 at least is needed

* Install Neovim
    * `winget install Neovim.Neovim`

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

* You can install most of the above automatically using `Winget` as follow
    - `winget configure -f configurations/configuration.dsc.yaml`
    - The only thing missing is `netcoredbg` and `html-tidy` since they are not available in Winget.
