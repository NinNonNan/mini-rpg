# DialogueManager.gd
# Questa classe gestisce tutta la logica del dialogo con le entità nel gioco.
# Usa i segnali per comunicare con altri nodi (UI o Game) invece di manipolare direttamente i controlli.
# In questo modo il dialogo è decouplato dalla UI e può essere riutilizzato facilmente.

class_name DialogueManager
extends Node

# --- Segnali ---
signal text_requested(text_content)      # Emesso per aggiornare il testo del dialogo
signal choices_requested(choices_array)  # Emesso per aggiornare i pulsanti delle scelte
signal dialogue_finished(victory_scene_name) # Emesso quando il dialogo termina con successo
signal dialogue_failed()                  # Emesso quando il dialogo fallisce
signal stats_updated()                    # Emesso quando cambia lo stato (umore) per aggiornare UI/Stats

# --- Stato del dialogo ---
var is_active = false         # Indica se il dialogo è attualmente in corso
var current_mood = 0          # Umore dell'entità durante il dialogo

# Variabili interne per tracciare l'entità corrente
var _entity_name = ""         # Nome dell'entità
var _entity_pronoun = ""      # Pronome dell'entità (es. "lui", "lei")
var _victory_scene = ""       # Scena da mostrare se il dialogo ha successo

# --- Inizio dialogo ---
# entity_name: il nome dell'entità
# pronoun: pronome dell'entità
# starting_mood: umore iniziale
# victory_scene: scena da caricare in caso di successo
func start_dialogue(entity_name: String, pronoun: String, starting_mood: int, victory_scene: String):
	is_active = true
	_entity_name = entity_name
	_entity_pronoun = pronoun
	current_mood = starting_mood
	_victory_scene = victory_scene
	
	# Aggiorna il testo iniziale e notifica la UI di aggiornare le statistiche
	text_requested.emit("Inizi a parlare con %s %s." % [_entity_pronoun, _entity_name])
	stats_updated.emit()
	
	# Piccola pausa per dare ritmo al dialogo (evita che tutto appaia istantaneamente)
	await get_tree().create_timer(1.0).timeout
	_present_choices() # Mostra le scelte al giocatore

# --- Resetta lo stato del dialogo ---
func reset():
	is_active = false
	current_mood = 0

# --- Gestione scelta del giocatore ---
func handle_choice(action_key: String):
	# Se il giocatore sceglie "attacca", il dialogo fallisce immediatamente
	if action_key == "attack":
		_fail_dialogue()
		return

	var mood_change = 0
	var response_text = ""
	
	# Determina l'effetto della scelta sullo stato dell'umore
	match action_key:
		"compliment":
			mood_change = 15
			response_text = "L'entità sembra apprezzare il gesto."
		"threaten":
			mood_change = -20
			response_text = "L'entità non sembra gradire il tuo tono."
	
	# Applica la modifica all'umore e lo limita tra -50 e 50
	current_mood = clamp(current_mood + mood_change, -50, 50)
	
	# Aggiorna il testo e le statistiche della UI tramite segnali
	text_requested.emit(response_text)
	stats_updated.emit()
	
	# Piccola pausa per dare ritmo al dialogo
	await get_tree().create_timer(1.5).timeout
	_check_status() # Controlla se il dialogo continua, finisce o fallisce

# --- Mostra le scelte disponibili al giocatore ---
func _present_choices():
	text_requested.emit("Umore attuale: %d. Cosa dici?" % current_mood)
	# Array di dizionari, ognuno rappresenta un pulsante nella UI
	var choices = [
		{"text": "Fai un complimento", "action": "compliment"},
		{"text": "Minaccia", "action": "threaten"},
		{"text": "Basta parlare, attacca!", "action": "attack"}
	]
	choices_requested.emit(choices) # Invia alla UI le scelte disponibili

# --- Controlla se il dialogo ha raggiunto un esito ---
func _check_status():
	if current_mood >= 30: # Successo del dialogo
		is_active = false
		text_requested.emit("Sei riuscito a convincere %s %s! Ti lascia passare in pace." % [_entity_pronoun, _entity_name])
		await get_tree().create_timer(2.0).timeout
		dialogue_finished.emit(_victory_scene) # Comunica al GameManager o UI che il dialogo è finito con successo
	elif current_mood <= -15: # Fallimento del dialogo
		_fail_dialogue()
	else:
		_present_choices() # Il dialogo continua, mostra nuovamente le scelte

# --- Fallimento del dialogo ---
func _fail_dialogue():
	is_active = false
	# Aggiorna il testo con messaggio di fallimento
	text_requested.emit("Hai fatto infuriare %s %s! Si prepara a combattere." % [_entity_pronoun, _entity_name])
	await get_tree().create_timer(2.0).timeout
	dialogue_failed.emit() # Comunica al GameManager o UI che il dialogo è fallito
