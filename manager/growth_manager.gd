# =========================================================
# GROWTH MANAGER
# =========================================================
# Gestisce la crescita e il potenziamento del personaggio.
#
# Funzionalità principali:
# - Calcola l'energia (XP) ottenuta dai nemici sconfitti.
# - Gestisce un pool di "Energia disponibile" da spendere.
# - Permette di aumentare permanentemente le statistiche massime (HP, MP, ecc.).
#
# Questo manager viene attivato da Game.gd dopo una vittoria in combattimento
# (vedi `_check_victory` in CombatManager).

class_name GrowthManager
extends Node

# Riferimento al gioco principale.
# Iniettato da Game.gd in _ready().
var game

# Energia accumulata pronta per essere distribuita
var available_energy: int = 0

# Variabili per la gestione temporanea dell'assegnazione punti (UI Overlay)
var initial_available_energy: int = 0
var temp_changes: Dictionary = {} # Mappa stat_id -> punti aggiunti


# Calcola quanta energia rilascia un nemico sconfitto.
# La ricompensa è basata sulla somma delle statistiche del nemico (es. Vita + Magia).
func calculate_reward(entity_id: String) -> int:
	var entity = game.entity_data.get(entity_id)
	
	if entity == null:
		push_warning(tr("warn_growth_entity_not_found") % entity_id)
		return 0
	
	# Calcola il valore totale delle statistiche del nemico
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

# --- Nuova Logica per UI Separata ---

# Inizializza la sessione di crescita
func start_growth_session():
	initial_available_energy = available_energy
	temp_changes.clear()

# Tenta di aggiungere un punto a una statistica (temporaneo)
func try_increase_stat(stat_type: String) -> bool:
	if available_energy > 0:
		available_energy -= 1
		temp_changes[stat_type] = temp_changes.get(stat_type, 0) + 1
		return true
	return false

# Tenta di rimuovere un punto assegnato (temporaneo)
func try_decrease_stat(stat_type: String) -> bool:
	if temp_changes.get(stat_type, 0) > 0:
		temp_changes[stat_type] -= 1
		available_energy += 1
		return true
	return false

# Resetta le modifiche attuali
func reset_changes():
	available_energy = initial_available_energy
	temp_changes.clear()

# Conferma le modifiche e applicale al gioco
func confirm_changes():
	if temp_changes.is_empty():
		# Nessuna modifica fatta, esce solo
		game.show_scene(game.current_victory_scene)
		return

	for stat_type in temp_changes:
		var amount = temp_changes[stat_type]
		if amount > 0:
			# 1. Aumenta il valore MASSIMO della statistica
			var current_max = game.player_max_energy.get(stat_type, 0)
			game.player_max_energy[stat_type] = current_max + amount
			
			# 2. Aumenta anche il valore ATTUALE (cura/ripristino parziale)
			game.modify_player_energy(stat_type, amount)
	
	# Pulisce i dati temporanei
	temp_changes.clear()
	initial_available_energy = available_energy
	
	game.update_stats() # Aggiorna le statistiche del giocatore (HP/MP)
	game.show_scene(game.current_victory_scene)
