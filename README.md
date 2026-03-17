# 🐉 Mini-RPG Text Adventure (Godot Engine)

Un'avventura testuale modulare creata con Godot 4, caratterizzata da un sistema data-driven (JSON), combattimenti a turni, gestione inventario e meccaniche di dialogo con NPC.

## ✨ Caratteristiche

*   **Sistema Data-Driven**: Tutta la storia, gli oggetti e i nemici sono definiti in un file `story.json`. Aggiungere nuovi contenuti non richiede modifiche al codice.
*   **Gestione Inventario**: Raccolta oggetti, equipaggiamento automatico dell'arma migliore e uso di consumabili (pozioni).
*   **Combattimento a Turni**: Sistema di attacco, calcolo danni basato sull'equipaggiamento e IA nemica basilare.
*   **Sistema di Dialogo**: Meccanica basata sull'umore ("Mood"). Puoi evitare combattimenti parlando con i nemici e influenzando il loro stato d'animo.
*   **Localizzazione**: Supporto nativo per traduzioni tramite file JSON (es. `it.json`).
*   **Architettura Modulare**: Codice organizzato in Manager specifici (Combat, Item, Dialogue, Empathy) per massima manutenibilità.

## 🛠️ Installazione e Utilizzo

1.  Scarica e installa **Godot Engine 4.x**.
2.  Clona questo repository:
    ```bash
    git clone https://github.com/tuo-username/mini-rpg-godot.git
    ```
3.  Apri Godot e importa il file `project.godot` presente nella cartella.
4.  Premi **F5** (o il tasto Play) per avviare il gioco.

## 📂 Struttura del Progetto

*   `Game.gd`: Il controller principale che gestisce la UI e lo stato globale.
*   `Managers/`:
    *   `CombatManager.gd`: Logica di combattimento.
    *   `ItemManager.gd`: Gestione oggetti e calcolo danni.
    *   `DialogueManager.gd`: Gestione dialoghi e persuasione.
    *   `EmpathyManager.gd`: Analisi dei nemici.
*   `story.json`: Il database della storia, oggetti e nemici.

## 📝 Come Modificare la Storia

Apri il file `story.json`. Ecco come aggiungere contenuti:

### 1. Aggiungere un Oggetto
Nella sezione `"items"`:
```json
"ascia_bipenne": {
    "name": "item_axe",
    "damage": 6
}
