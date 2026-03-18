class_name GrowthManager
extends Node

var game

# Energia accumulata pronta per essere distribuita
var available_energy: int = 0

# Calcola quanta energia rilascia un nemico (Vita + Magia del nemico)
func calculate_reward(entity_id: String) -> int:
	var entity = game.entity_data.get(entity_id, {})
	var reward = 0
	
	if entity.has("energy"):
		for stat in entity["energy"]:
			# Sommiamo i valori positivi (es. vita)
			var val = int(stat.get("value", 0))
			if val > 0:
				reward += val
	elif entity.has("health"): # Supporto legacy
		reward += int(entity["health"])
		
	# Facciamo in modo che il reward sia una frazione della forza totale (es. 50%)
	# Arrotondiamo per eccesso (es. lupo con 5 vita -> 3 energia)
	return ceili(reward * 0.5)

# Aggiunge energia al pool del giocatore
func add_energy(amount: int):
	available_energy += amount

# Tenta di spendere energia per potenziare una statistica
# Restituisce true se l'operazione ha successo
func upgrade_stat(stat_type: String) -> bool:
	if available_energy <= 0:
		return false
		
	available_energy -= 1
	
	match stat_type:
		"life":
			game.max_health += 1
			game.health += 1 # Cura anche di 1 quando potenzi
		"magic":
			game.max_mana += 1
			game.mana += 1
			
	game.update_stats()
	return true
