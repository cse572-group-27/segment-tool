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
var waiting := false

@onready var segment_list := $SegmentList


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
	var label_height = segment_list.get_child(0).size.y
	
	var label_position = (viewport_height - label_height) / 2
	segment_list.position.y = label_position
	
	modulate = Color.WHITE


func mark_content() -> void:
	if waiting:
		return
	
	segments[segment_index].type = Segment.Type.CONTENT
	advance_segment()


func mark_advert() -> void:
	if waiting:
		return
	
	segments[segment_index].type = Segment.Type.AD
	advance_segment()


func advance_segment() -> void:
	if waiting:
		return
	
	waiting = true
	set_inputs_disabled.emit(true)

	var next_segment_index = segment_index + 1
		
	var segment_color = colors[segments[segment_index].type]
	
	if next_segment_index < segments.size():
		segment_color *= unfocused_mod
		
	const TWEEN_TIME: float = 0.5
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.tween_property(segments[segment_index].label, "modulate", segment_color, TWEEN_TIME)
	
	if next_segment_index >= segments.size():
		finished.emit()
		return
	
	var segment_height = segments[next_segment_index].label.size.y
	var next_segment_height = segments[next_segment_index].label.size.y
	var delta_y = 0.5 * (segment_height + next_segment_height)
	
	var next_segment_color = colors[segments[next_segment_index].type]
	
	tween.parallel().tween_property(segment_list, "position:y", segment_list.position.y - delta_y, TWEEN_TIME)
	tween.parallel().tween_property(segments[next_segment_index].label, "modulate", next_segment_color, TWEEN_TIME)
	
	tween.tween_callback(func() -> void:
		segment_index += 1
		waiting = false
		set_inputs_disabled.emit(false)
	)
