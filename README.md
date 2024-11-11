# Neovim-Moaid
My Neovim Configuration :)

# Installation

#### Manual Installation
	
1. Update `XDG_CONFIG_HOME` if needed
    - Should point to the `config/` folder in this repo.
    - For example: `C:/Github/Neovim-Moaid/config`

2. Install Neovim
    - Using Windows via `Winget`
        - `winget install Neovim.Neovim`
    - Using Linux via `apt`
        - `sudo apt install neovim`

3. Install `Zig` (Windows only, not needed for Linux)
    - `winget install zig.zig` (__slow to install__)
    - Make sure to use a stable release

4. Install `WinGnu32.Make` or `Kitware.CMake` (Windows only, not needed for Linux)
    - `winget install Kitware.CMake`

5. Install `fd`
    - Using Windows Windows via `Winget`
        - `winget install sharkdp.fd`
    - Using Linux via apt
        - `sudo apt install fd-find`

5. Install `ripgrep`
    - Using Windows via `Winget`
        - `winget install BurntSushi.ripgrep.MSVC`
    - Using Linux via `apt`
        - `sudo apt install ripgrep`

6. Install `LazyGit`
    - Using Windows via `Winget`
        - `winget install JesseDuffield.lazygit`
    - Using Linux via `apt`
        - `sudo apt install lazygit` 

7. Install `jq` (for `nvim-rest`)
    - Using Windows via `Winget`
   		- `winget install jqlang.jq`
    - Using Linux via `apt`
        - `sudo apt install jq`

8. Install html-tidy (for `nvim-rest`)
    - Using Windows via `Winget`
   		- https://github.com/htacg/tidy-html5

#### Automatic Installation
- For Windows, you can install most of the above automatically using `Winget` as follow
    - `winget configure -f configurations/configuration.dsc.yaml`
    - The only thing missing is `netcoredbg` and `html-tidy` since they are not available via `Winget`
    - **note** - this process may take a *lot* of time to finish due to `Zig`. `Zig`'s binaries are highly compressed and it take an unwordly amount of time to uncompress them. This doesn't relate to `Winget` or to the configuration file, you'll encounter the same experience when running the installer manually.

