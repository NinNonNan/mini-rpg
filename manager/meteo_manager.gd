# =========================================================
# METEO MANAGER
# =========================================================
# Gestisce le condizioni meteorologiche del gioco.
#
# Funzionalità:
# - Genera casualmente il meteo quando si cambia scena.
# - Aggiorna l'interfaccia utente con l'icona e il nome del meteo corrente.
#
# Il meteo è puramente estetico al momento, ma la struttura è pronta
# per influenzare le statistiche o il combattimento in futuro
# (es. "Pioggia" potrebbe potenziare le magie di "Fulmine").

class_name MeteoManager
extends Node

# Riferimento al gioco principale.
# Iniettato da Game.gd in _ready().
var game: Game

# ID del meteo corrente (es. "sun", "rain")
var current_weather: String = ""

# Genera una nuova condizione meteo casuale.
# Chiamato da Game.gd in `show_scene`.
func roll_weather():
	# Controllo di sicurezza: se la UI del meteo non è collegata, usciamo.
	if not game or not game.meteo_stats:
		return
		
	# Recupera i dati meteo caricati da definitions.json (uniti in story_data)
	var weather_data = game.story_data.get("weather", {})
	if weather_data.is_empty():
		return

	# Sceglie una chiave a caso (es. "storm")
	var keys = weather_data.keys()
	current_weather = keys.pick_random()
	var w_info = weather_data[current_weather]
	
	var w_name = w_info.get("name", "")
	var w_icon = w_info.get("icon", "")
	
	# Aggiorna la label nella UI principale.
	# Usa tr() per convertire la chiave (es. "weather_sun") nel testo localizzato ("Soleggiato").
	game.meteo_stats.text = "%s %s" % [w_icon, game.tr(w_name)]