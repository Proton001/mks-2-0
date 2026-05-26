extends Control

@onready var btn_create: Button = %BtnCreateLobby
@onready var btn_browse: Button = %BtnBrowseLobbies
@onready var panel: Panel = %CreateLobbyPanel
@onready var name_edit: LineEdit = %LobbyNameEdit
@onready var max_slider: HSlider = %MaxPlayersSlider
@onready var label_max: Label = %LabelMaxPlayers
@onready var privacy_option: OptionButton = %PrivacyOption
@onready var btn_confirm: Button = %BtnConfirmCreate


# ─── Типы приватности — соответствуют константам Steam ────────────────────────
const PRIVACY_TYPES: Array[int] = [
	Steam.LOBBY_TYPE_PUBLIC,          # 0 — Публичное
	Steam.LOBBY_TYPE_FRIENDS_ONLY,    # 1 — Только друзья
]

func _ready() -> void:
	# Настройка слайдера
	max_slider.min_value = 2
	max_slider.max_value = 6
	max_slider.step      = 1
	max_slider.value     = 4
	label_max.text       = "Игроков: 4"

	# Настройка выпадающего списка приватности
	privacy_option.clear()
	privacy_option.add_item("Публичное")
	privacy_option.add_item("Только друзья")
	privacy_option.select(0)

	# Панель скрыта по умолчанию
	panel.hide()

	# Подключение сигналов кнопок
	btn_create.pressed.connect(_on_btn_create_pressed)
	btn_browse.pressed.connect(_on_btn_browse_pressed)
	btn_confirm.pressed.connect(_on_btn_confirm_pressed)
	max_slider.value_changed.connect(_on_slider_changed)

	# Слушаем результат создания лобби от SteamManager
	SteamManager.lobby_created_ok.connect(_on_lobby_created_ok)
	SteamManager.lobby_join_failed.connect(_on_lobby_failed)


# ─── Показать/скрыть панель создания лобби ───────────────────────────────────
func _on_btn_create_pressed() -> void:
	# Тоггл — повторное нажатие закрывает панель
	panel.visible = not panel.visible
	if panel.visible:
		name_edit.text = ""
		name_edit.grab_focus()


# ─── Переход к списку лобби ──────────────────────────────────────────────────
func _on_btn_browse_pressed() -> void:
	# Меняем сцену на браузер лобби
	#"res://scenes/lobby_browser/lobby_browser.tscn"
	get_tree().change_scene_to_file("uid://xxpaqo0m3mw2")

# ─── Обновление подписи слайдера ─────────────────────────────────────────────
func _on_slider_changed(value: float) -> void:
	label_max.text = "Игроков: %d" % int(value)


# ─── Подтверждение создания лобби ────────────────────────────────────────────
func _on_btn_confirm_pressed() -> void:
	var lobby_name: String = name_edit.text.strip_edges()

	# Валидация названия
	if lobby_name.is_empty():
		_show_error("Введите название лобби")
		return

	if lobby_name.length() > 64:
		_show_error("Название не должно превышать 64 символа")
		return

	var max_players: int = int(max_slider.value)
	var privacy: int     = PRIVACY_TYPES[privacy_option.selected]

	# Блокируем кнопку чтобы не создать два лобби подряд
	btn_confirm.disabled = true
	btn_confirm.text     = "Создание..."

	SteamManager.create_lobby(lobby_name, max_players, privacy)


# ─── Колбэки от SteamManager ─────────────────────────────────────────────────
func _on_lobby_created_ok(lobby_id: int) -> void:
	print("Лобби создано: %d" % lobby_id)
	panel.hide()
	#"res://scenes/lobby_room/lobby_room.tscn"
	get_tree().change_scene_to_file("uid://ii5saug6ok5e")

func _on_lobby_failed(reason: String) -> void:
	btn_confirm.disabled = false
	btn_confirm.text     = "Создать"
	_show_error("Ошибка: %s" % reason)


# ─── Показ ошибки (можно заменить на диалог) ─────────────────────────────────
func _show_error(text: String) -> void:
	# Простой вариант — вывод в label. Замени на AcceptDialog если нужен попап.
	push_warning(text)
	var err_label: Label = panel.get_node_or_null("LabelError")
	if err_label:
		err_label.text = text
