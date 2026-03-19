class_name GrowthManager
extends Node

var game

# Energia accumulata pronta per essere distribuita
var available_energy: int = 0

# Calcola quanta energia rilascia un nemico (Vita + Magia del nemico)
func calculate_reward(entity_id: String) -> int:
	var entity = game.entity_data.get(entity_id)
	
	if entity == null:
		push_warning(tr("warn_growth_entity_not_found") % entity_id)
		return 0
		
	var reward_base = 0.0 # Usiamo float per i calcoli intermedi
	
	if entity.has("energy"):
		for stat in entity["energy"]:
			# Sommiamo i valori positivi (es. vita), convertendo a float per sicurezza
			var val = float(stat.get("value", 0.0))
			if val > 0:
				reward_base += val
	elif entity.has("health"): # Supporto per la vecchia struttura dati
		reward_base += float(entity.get("health", 0.0))
	
	if reward_base <= 0:
		push_warning(tr("warn_growth_reward_zero") % entity_id)

	# Il reward è una frazione della forza totale (es. 50%), arrotondato per eccesso
	# Diciamo invece che l'energia rilasciata è un terzo di quella forza.
	var final_reward = ceili(reward_base * 0.33)
	return int(final_reward)

# Aggiunge energia al pool del giocatore
func add_energy(amount: int):
	available_energy += amount

# Tenta di spendere energia per potenziare una statistica
# Restituisce true se l'operazione ha successo
func upgrade_stat(stat_type: String):
	if available_energy <= 0:
		return
		
	available_energy -= 1
	
	var upgraded = false
	match stat_type:
		"life":
			game.max_health += 1
			game.health += 1 # Cura anche di 1 quando potenzi
			upgraded = true
		"magic":
			game.max_mana += 1
			game.mana += 1
			upgraded = true
		"mood":
			game.max_mood += 1
			game.mood += 1
			upgraded = true
			
	if not upgraded:
		available_energy += 1 # Restituisce il punto se lo stat non è implementato
		return

	game.update_stats() # Aggiorna le statistiche del giocatore (HP/MP)

	# Se l'energia è esaurita, procedi. Altrimenti, aggiorna il menu.
	if available_energy <= 0:
		game.show_scene(game.current_victory_scene)
	else:
		game._update_growth_menu()
