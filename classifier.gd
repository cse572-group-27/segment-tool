extends Control

signal finished
signal set_inputs_disabled(disabled: bool)

@export var colors: Array[Color]
@export var unfocused_mod: Color

class Segment:
	enum Type {
		UNLABLED,
		CONTENT,
		AD
	}
	
	var text: String
	var type: Type
	var label: Label
	
	static func create(segment_text: String) -> Segment:
		var segment = Segment.new()
		segment.text = segment_text
		segment.type = Type.UNLABLED
		
		segment.label = Label.new()
		segment.label.text = segment_text
		segment.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		return segment

var segments: Array[Segment] = []
var segment_index := 0
var screen_midpoint := 0.0
var cached_segment_index := 0
var cached_target_position := 0.0
var cached_movement_speed := 0.0
var scroll_debounce_active := false

const TWEEN_TIME: float = 0.5
const ACCELERATION: float = 8800.0
const DECELERATION: float = 3400.0
const MAX_SPEED: float = 6000.0

@onready var segment_list := $SegmentList
@onready var scroll_debouncer := $ScrollDebouncer


func _process(delta: float) -> void:
	if segments.is_empty():
		return
	
	if cached_segment_index == segment_index:
		var movement_speed = 200.0
		var segment_position = segment_list.global_position
		var to_go = cached_target_position - segment_position.y
		
		var decel_dist = (cached_movement_speed * cached_movement_speed) / (2.0 * DECELERATION)
		
		if abs(to_go) > decel_dist:
			cached_movement_speed = move_toward(cached_movement_speed, MAX_SPEED, ACCELERATION * delta)
		else:
			cached_movement_speed = move_toward(cached_movement_speed, 0.0, DECELERATION * delta)
		
		segment_position.y = move_toward(segment_position.y, cached_target_position, cached_movement_speed * delta)
		segment_list.global_position = segment_position
		return
	
	var segment_half_height = segments[segment_index].label.size.y / 2.0
	var target_position = screen_midpoint - segment_half_height
	var target_offset = target_position - segments[segment_index].label.global_position.y
	cached_target_position = segment_list.global_position.y + target_offset
	cached_segment_index = segment_index



func set_segments(segment_texts: PackedStringArray) -> void:
	var first := true
	
	for segment_text in segment_texts:
		var segment = Segment.create(segment_text)
		segments.append(segment)
		
		segment_list.add_child(segment.label)
		
		if first:
			first = false
			segment.label.modulate = colors[0]
		else:
			segment.label.modulate = colors[0] * unfocused_mod
	
	# Position first label, wait for redraw
	modulate = Color.TRANSPARENT
	await get_tree().process_frame
	
	var viewport_height = size.y
	var label_half_height = segment_list.get_child(0).size.y / 2.0
	
	screen_midpoint = viewport_height / 2.0
	var target_height = screen_midpoint - label_half_height
	segment_list.position.y = target_height
	cached_target_position = segment_list.global_position.y
	
	modulate = Color.WHITE


func mark_content() -> void:
	segments[segment_index].type = Segment.Type.CONTENT
	advance_segment(segment_index + 1)


func mark_advert() -> void:
	segments[segment_index].type = Segment.Type.AD
	advance_segment(segment_index + 1)


func advance_segment(next_segment_index: int) -> void:
	var segment_color = colors[segments[segment_index].type]

	if next_segment_index >= 0 and next_segment_index < segments.size():
		segment_color *= unfocused_mod

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.tween_property(segments[segment_index].label, "modulate", segment_color, TWEEN_TIME)

	check_finished()
	
	if next_segment_index < 0 or next_segment_index >= segments.size():
		return
#
	var next_segment_color = colors[segments[next_segment_index].type]
#
	tween.parallel().tween_property(segments[next_segment_index].label, "modulate", next_segment_color, TWEEN_TIME)
	segment_index = next_segment_index


func _on_gui_input(event: InputEvent) -> void:
	if scroll_debounce_active:
		return
	
	if event is InputEventMouseButton:
		var mb := (event as InputEventMouseButton)
		
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				advance_segment(segment_index - 1)
				scroll_debounce()
			MOUSE_BUTTON_WHEEL_DOWN:
				advance_segment(segment_index + 1)
				scroll_debounce()
			_:
				return
	elif event is InputEventPanGesture:
		var pg := (event as InputEventPanGesture)
		
		if pg.delta.y < 0:
			advance_segment(segment_index - 1)
			scroll_debounce()
		elif pg.delta.y > 0:
			advance_segment(segment_index + 1)
			scroll_debounce()


func scroll_debounce() -> void:
	scroll_debounce_active = true
	scroll_debouncer.start()

func _on_scroll_debouncer_timeout() -> void:
	scroll_debounce_active = false


func check_finished() -> void:
	var is_finished: bool = segments.reduce(func(accum: bool, segment: Segment) -> bool:
		return accum and (segment.type != Segment.Type.UNLABLED)
	, true)
	
	if is_finished:
		finished.emit()
