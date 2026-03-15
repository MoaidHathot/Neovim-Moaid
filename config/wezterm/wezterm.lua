local wezterm = require("wezterm")
local mux = wezterm.mux
local config = wezterm.config_builder()

-- Start with PowerShell Core
config.default_prog = { "pwsh.exe" }

-- No borders, no tab bar
config.window_decorations = "RESIZE"
config.enable_tab_bar = false

-- Font — clean and readable for presentations
config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 16.0

-- Color scheme — high contrast, easy on projectors
config.color_scheme = "Catppuccin Mocha"

-- Window padding — breathing room around content
config.window_padding = {
  left = 16,
  right = 16,
  top = 16,
  bottom = 16,
}

-- Hide scrollbar, steady block cursor
config.enable_scroll_bar = false
config.default_cursor_style = "SteadyBlock"

-- No update popups or warnings during presentations
config.check_for_updates = false
config.warn_about_missing_glyphs = false

-- Start maximized
wezterm.on("gui-startup", function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

return config
