class_name Panels
## Makes the full-screen panels the level opens by name: the bag and crafting ("inventory"), "pause",
## "death", "journal", the treasure "map", the "weather" station and the "debug" menu.


static func make(lv: Level, panel_name: String) -> Control:
	match panel_name:
		"inventory":
			var inv := InventoryPanel.new()
			inv.setup(lv)
			return inv
		"pause":
			var pp := PausePanel.new()
			pp.setup(lv)
			return pp
		"death":
			var dp := DeathPanel.new()
			dp.setup(lv)
			return dp
		"journal":
			var jp := JournalPanel.new()
			jp.setup(lv)
			return jp
		"map":
			var mp := MapPanel.new()
			mp.setup(lv)
			return mp
		"weather":
			var wp := WeatherPanel.new()
			wp.setup(lv)
			return wp
		"debug":
			var gp := DebugPanel.new()
			gp.setup(lv)
			return gp
	return null
