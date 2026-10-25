extends RefCounted

## Action-scoped daily checkpoint. Persistence never changes simulation data.
## Loading adopts an owner without replaying historical day/log identities.
var _owner: Object
var _pending: Dictionary = {}
var _last_transition := ""
var _attempted := false
var last_result: Dictionary = {}

func cancel() -> void:
	_owner = null
	_pending.clear()
	_last_transition = ""
	_attempted = false
	last_result = {}

func sync_owner(owner: Object) -> void:
	if owner != _owner:
		cancel()
		_owner = owner

func capture_transition(owner: Object, before: Dictionary, after: Dictionary, enabled: bool) -> void:
	sync_owner(owner)
	if owner == null or not enabled: return
	# A whole day, not a turn counter or a historical event, is the trigger.
	if int(after.get("day", 0)) <= int(before.get("day", 0)): return
	if str(after.get("phase", "")) != "await_roll": return
	var identity := JSON.stringify([before, after]).sha256_text()
	if identity == _last_transition: return
	_last_transition = identity
	_pending = owner.to_dict().duplicate(true)
	_attempted = false
	last_result = {}

func pending() -> bool:
	return not _pending.is_empty()

func failed() -> bool:
	return pending() and _attempted and not bool(last_result.get("ok", false))

func retry() -> void:
	_attempted = false

func skip() -> void:
	_pending.clear()
	_attempted = false

func flush(owner: Object, storage: Object, blocked: bool) -> Dictionary:
	sync_owner(owner)
	if blocked or not pending() or _attempted: return {}
	# Never submit an old checkpoint after a replacement or an out-of-band
	# mutation. Ordinary host input is gated while this snapshot is pending.
	if owner.to_dict() != _pending:
		skip()
		return {"ok": false, "error": "checkpoint_changed"}
	_attempted = true
	last_result = storage.write_automatic(_pending)
	if bool(last_result.get("ok", false)): _pending.clear()
	return last_result.duplicate(true)
