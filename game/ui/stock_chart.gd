extends Control
class_name RichmanStockChart

## Source-supported company history chart and two-part ownership pie.
##
## Only prices present in the supplied chronological history are drawn.  The
## helper never pads, interpolates or otherwise invents market observations.

const PLAYER_PIE_COLOR := Color("#ea1d2b")
const OTHER_PIE_COLOR := Color("#151bd2")

var history: Array = []
var current_holdings := 0
var total_shares := 10000
var pie_ratio := 0.0
var line_points: Array = []


func configure(history_value: Variant, holdings_value: int, total_shares_value := 10000) -> void:
	history = _valid_history(history_value)
	current_holdings = maxi(0, holdings_value)
	total_shares = maxi(1, total_shares_value)
	pie_ratio = float(current_holdings) / float(total_shares)
	line_points = _build_points(history)
	queue_redraw()


func source_history() -> Array:
	return history.duplicate(true)


static func history_statistics(history_value: Variant) -> Dictionary:
	var values := _valid_history(history_value)
	return {
		"weekly_mean": _mean(values, 6),
		"monthly_mean": _mean(values, 24),
		"historical_high": _extreme(values, true),
		"historical_low": _extreme(values, false),
		"sample_count": values.size(),
	}


static func _valid_history(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)):
			continue
		var price := float(item)
		if price <= 0.0:
			continue
		result.append(price)
	return result


static func _mean(values: Array, count: int) -> Variant:
	if values.is_empty() or count <= 0:
		return null
	var start := maxi(0, values.size() - count)
	var sum := 0.0
	var samples := 0
	for index in range(start, values.size()):
		var value := float(values[index])
		if value == 0.0 or not is_finite(value):
			continue
		sum = float(PackedFloat32Array([sum + value])[0])
		samples += 1
	if samples == 0:
		return null
	return float(PackedFloat32Array([sum / float(samples)])[0])


static func _extreme(values: Array, high: bool) -> Variant:
	if values.is_empty():
		return null
	var result := float(values[0])
	for value in values:
		result = maxf(result, float(value)) if high else minf(result, float(value))
	return result


func _build_points(values: Array) -> Array:
	var points: Array = []
	if values.is_empty():
		return points
	var plot := Rect2(13.0, 15.0, 344.0, 145.0)
	var low := float(values[0])
	var high := float(values[0])
	for value in values:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	var span := maxf(0.01, high - low)
	var padding := maxf(1.0, span * 0.08)
	low -= padding
	high += padding
	span = maxf(0.01, high - low)
	for index in range(values.size()):
		var fraction := 0.0 if values.size() <= 1 else float(index) / float(values.size() - 1)
		var y_fraction := (float(values[index]) - low) / span
		points.append(Vector2(plot.position.x + plot.size.x * fraction, plot.end.y - plot.size.y * y_fraction))
	return points


func _draw() -> void:
	var plot := Rect2(13.0, 15.0, 344.0, 145.0)
	if line_points.size() == 1:
		draw_circle(line_points[0], 2.5, Color("#fff7d0"))
	elif line_points.size() > 1:
		draw_polyline(PackedVector2Array(line_points), Color("#fff7d0"), 2.0, true)
	for point in line_points:
		draw_circle(point, 1.5, Color("#fff7d0"))

	# Panel75 chunk 2 already carries the source six-bar backdrop and a
	# horizontally rendered pie. Overlay only the source-driven ownership
	# split in that footprint; repainting the bars creates a second chart over
	# the source texture and visibly obscures its labels.
	var center := Vector2(size.x - 78.0, size.y - 46.0)
	var radius := minf(58.0, maxf(18.0, minf(size.x * 0.19, size.y * 0.26)))
	var share_fraction := clampf(pie_ratio, 0.0, 1.0)
	if share_fraction <= 0.0:
		_draw_pie_segment(center, radius, -PI * 0.5, TAU - PI * 0.5, OTHER_PIE_COLOR)
	elif share_fraction >= 1.0:
		_draw_pie_segment(center, radius, -PI * 0.5, TAU - PI * 0.5, PLAYER_PIE_COLOR)
	else:
		_draw_pie_segment(center, radius, -PI * 0.5, -PI * 0.5 + TAU * share_fraction, PLAYER_PIE_COLOR)
		_draw_pie_segment(center, radius, -PI * 0.5 + TAU * share_fraction, TAU - PI * 0.5, OTHER_PIE_COLOR)
	var outline := PackedVector2Array()
	for index in range(65):
		var angle := TAU * float(index) / 64.0
		outline.append(center + Vector2(cos(angle) * radius * 1.52, sin(angle) * radius * 0.50))
	draw_polyline(outline, Color("#0b173d"), 1.0, true)


func _draw_pie_segment(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color) -> void:
	var points := PackedVector2Array([center])
	var steps := maxi(2, int(ceil(absf(end_angle - start_angle) * 20.0)))
	for index in range(steps + 1):
		var angle := lerpf(start_angle, end_angle, float(index) / float(steps))
		points.append(center + Vector2(cos(angle) * radius * 1.52, sin(angle) * radius * 0.50))
	draw_colored_polygon(points, color)
