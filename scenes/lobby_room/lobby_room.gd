extends Control


@onready var player_list: VBoxContainer = %PlayerList
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var btn_ready: Button = %BtnReady
@onready var btn_start: Button = %BtnStart
@onready var btn_leave: Button = %BtnLeave


var _is_ready: bool = false


func _ready() -> void:
	# Подписка на сигналы SteamManager
	SteamManager.lobby_members_updated.connect(_refresh_player_list)
	SteamManager.chat_message_received.connect(_on_chat_received)
	SteamManager.player_ready_changed.connect(_on_ready_changed)
	SteamManager.lobby_left.connect(_on_lobby_left)

	# Кнопка "Старт" только у владельца лобби
	btn_start.visible = (SteamManager.steam_id == Steam.getLobbyOwner(SteamManager.lobby_id))
	btn_start.disabled = true

	_refresh_player_list()
	SteamManager.game_started.connect(_on_game_started) # подключеаем сигнал к началу игры


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for member: Dictionary in SteamManager.lobby_members:
		var label := Label.new()
		var ready_tag: String = " ✓" if member["is_ready"] else " ○"
		var owner_tag: String = " 👑" if member["is_owner"] else ""
		label.text = "%s%s%s" % [member["steam_name"], owner_tag, ready_tag]
		player_list.add_child(label)

	# ✅ Обновляем видимость кнопки при каждом обновлении списка
	btn_start.visible = (SteamManager.steam_id == Steam.getLobbyOwner(SteamManager.lobby_id))
	btn_start.disabled = not SteamManager.all_players_ready()


func _on_chat_received(sender: String, message: String) -> void:
	chat_log.append_text("[b]%s:[/b] %s\n" % [sender, message])


func _on_ready_changed(_sid: int, _ready: bool) -> void:
	_refresh_player_list()


func _on_btn_ready_pressed() -> void:
	_is_ready = not _is_ready
	SteamManager.set_player_ready(_is_ready)
	btn_ready.text = "Не готов" if _is_ready else "Готов"


func _on_btn_send_chat_pressed() -> void:
	SteamManager.send_chat_message(chat_input.text)
	chat_input.clear()


func _on_btn_start_pressed() -> void:
	if not SteamManager.all_players_ready():
		return
	var ok: bool = Steam.setLobbyData(SteamManager.lobby_id, "state", "started")
	print("=== setLobbyData результат: ", ok)  # должно быть true

func _on_game_started() -> void:
	print("Запуск игровой сцены")
	# Сначала поднимаем P2P-соединение, потом меняем сцену
	SteamManager.setup_multiplayer()
	get_tree().change_scene_to_file("uid://dx1hlvfd60um1")  # game.tscn

func _on_btn_leave_pressed() -> void:
	SteamManager.leave_lobby()


func _on_lobby_left() -> void:
	#"res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file("uid://c6t7qd42fgtdw")


func _on_chat_input_text_submitted(new_text: String) -> void:
	SteamManager.send_chat_message(chat_input.text)
	chat_input.clear()
