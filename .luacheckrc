std = "lua54"
codes = true
unused_args = false
max_line_length = false
files["plugin/**/*.lua"] = {
    read_globals = { "Event", "GameKey", "GameState", "Keyboard", "MiniMenuEntryType", "PlayerList", "Plugin", "config", "id", "prettyui", "ui" },
}
files["plugin/main.lua"] = { globals = { "PluginShutdown" } }
