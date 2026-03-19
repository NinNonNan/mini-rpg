class_name MeteoManager
extends Node

var game: Game
var current_weather: String = ""

func roll_weather():
	if not game or not game.meteo_stats:
		return
		
	var weather_data = game.story_data.get("weather", {})
	if weather_data.is_empty():
		return

	var keys = weather_data.keys()
	current_weather = keys.pick_random()
	var w_info = weather_data[current_weather]
	
	var w_name = w_info.get("name", "")
	var w_icon = w_info.get("icon", "")
	
	# Usa tr() per convertire la chiave ("weather_sun") nel testo tradotto ("Soleggiato")
	game.meteo_stats.text = "%s %s" % [w_icon, tr(w_name)]