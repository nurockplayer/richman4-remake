extends RefCounted

## The pending game belongs to this core instance. Display snapshots contain no
## mutable reward authority. Saving is explicitly unavailable until return.
const Model = preload("res://game/core/source_minigame_model.gd")
const KINDS := {6: "penguin", 7: "balloon", 8: "catching"}
var _model: RefCounted
var _identity: Dictionary = {}
var _shortcut_reward := 0
var _settled := false

func admit(game: Object, player_id: int, encounter_id: int, animation: bool, input_data: Dictionary) -> void:
	var player: Dictionary = game._player(player_id)
	var tile: Dictionary = game.state.board[int(player.position)]
	var kind: String = KINDS.get(int(tile.get("event_code", 0)), "")
	var shortcut := bool(player.get("is_ai", false)) or not animation
	_identity = {"kind":kind, "edition":str(game.state.get("map_source",{}).get("edition","Game")), "player_id":player_id, "character_id":int(player.get("character_id",0)), "encounter_id":encounter_id, "shortcut":shortcut}
	if shortcut:
		_shortcut_reward = game._rng.randi_range(50,69)
	else:
		_model = Model.new()
		var model_input := input_data.duplicate(false)
		var characters: Array = input_data.get("catching_characters",{}).get(str(_identity.edition),[])
		if int(_identity.character_id)>=0 and int(_identity.character_id)<characters.size():
			model_input["character_frames"] = characters[int(_identity.character_id)]
		_model.configure(kind, game._rng.randi_range(0,2147483647), model_input)
	game.state.phase = "await_minigame"
	game.state.action_options = []
	game._record_event("minigame_entered", _identity.duplicate(true))

func matches(game: Object, encounter_id: int) -> bool:
	return not _settled and not _identity.is_empty() and int(_identity.encounter_id)==encounter_id and game.state.get("phase","")=="await_minigame" and int(game.state.get("current_player",-1))==int(_identity.player_id) and bool(game._player(int(_identity.player_id)).get("alive",false))

func snapshot() -> Dictionary:
	if _settled: return {}
	var result := _identity.duplicate(true)
	result["model"] = _model.snapshot() if _model != null else {}
	result["finished"] = _model.finished() if _model != null else true
	result["reward"] = _model.reward() if _model != null else _shortcut_reward
	return result

func tick(game: Object, encounter_id: int) -> bool:
	if not matches(game,encounter_id) or _model==null or _model.finished(): return false
	_model.tick()
	return true

func pointer(game: Object, encounter_id: int, position: Vector2, pressed: bool) -> bool:
	if not matches(game,encounter_id) or _model==null or _model.finished() or not position.is_finite() or not Rect2(0,0,640,480).has_point(position): return false
	_model.pointer(position,pressed)
	return true

func finish(game: Object, encounter_id: int) -> Dictionary:
	if not matches(game,encounter_id) or (_model != null and not _model.finished()): return game._error("目前無法結束小遊戲")
	var reward: int = _model.reward() if _model != null else _shortcut_reward
	if reward < 0: return game._error("小遊戲點數無效")
	var player: Dictionary = game._player(int(_identity.player_id))
	var awarded: int = mini(reward, game.MAX_GRAPH_POINTS-int(player.get("points",0)))
	player.points = int(player.get("points",0))+awarded
	_settled = true
	game.state.phase = "await_action"
	game._set_action_options(int(_identity.player_id))
	game._record_event("minigame_completed", {"player_id":int(_identity.player_id),"kind":str(_identity.kind),"encounter_id":encounter_id,"points":awarded,"source_points":reward,"shortcut":bool(_identity.shortcut)})
	return game._result(true,"獲得 %d 點" % awarded)
