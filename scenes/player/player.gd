extends CharacterBody2D

const SPEED: float = 200.0

var player_name: String = ""


func init(pname: String) -> void:
	player_name = pname


func _physics_process(delta: float) -> void:
	# Только владелец этого узла обрабатывает ввод
	if not is_multiplayer_authority():
		return

	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	move_and_slide()

	# Синхронизируем позицию для всех остальных
	_sync_position.rpc(global_position)


# Получаем позицию от владельца узла
@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_position(pos: Vector2) -> void:
	global_position = pos
