extends Control

signal preclassify_message(message: String)
signal preclassify_max(value: int)
signal preclassify_value(value: int)
signal preclassify_finished
signal finished(finished: bool)

@export var colors: Array[Color]
@export var unfocused_mod: Color

class Segment:
	enum Type {
		UNLABELED,
		CONTENT,
		AD,
		MAX
	}
	
	var text: String
	var type: Type
	var label: Label
	var original_text: String
	var adjusted: bool
	
	static func create(segment_text: String, created_from_split: bool = false) -> Segment:
		var segment = Segment.new()
		segment.text = segment_text
		segment.type = Type.UNLABELED
		
		segment.original_text = ""
		segment.adjusted = created_from_split
		
		return segment
	
	func init() -> void:
		label = Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	func update_text(segment_text: String) -> void:
		if original_text == "":
			original_text = text
		
		adjusted = (original_text != segment_text)
		text = segment_text
		label.text = segment_text

var segments: Array[Segment] = []
var segment_index := 0
var screen_midpoint := 0.0
var cached_segment_index := 0
var cached_target_position := 0.0
var cached_movement_speed := 0.0
var scroll_debounce_active := false

var adjustments: Array[Dictionary] = []
var adjusting_from: Array[String] = []

var pre_classifier: BoundProcess
var pre_classify_thread: Thread

const TWEEN_TIME: float = 0.5
const ACCELERATION: float = 8800.0
const DECELERATION: float = 3400.0
const MAX_SPEED: float = 6000.0

@onready var segment_list := $SegmentList
@onready var scroll_debouncer := $ScrollDebouncer


func _ready() -> void:
	pre_classify_thread = Thread.new()


func _preclassify_thread_func(file_path: String) -> void:
	var path = ""
	if OS.has_feature("editor"):
		path = ProjectSettings.globalize_path("res://setup_preclassifier.sh")
	else:
		path = OS.get_executable_path().get_base_dir().path_join("../Resources/setup_preclassifier.sh")
		if (!FileAccess.file_exists(path)):
			printerr("Pre-classifier not found at path: '%s'" % path)
			return
	
	pre_classifier = BoundProcess.start("bash", [path])
	if not pre_classifier.is_running():
		printerr("Unable to start pre-classifier!")
		return
	
	if pre_classifier.write_line("HELLO") != OK or pre_classifier.read_line() != "READY":
		printerr("Unable to initialize pre-classifier!")
		return
	
	if pre_classifier.write_line("READFILE") != OK or pre_classifier.read_line() != "OK":
		printerr("Unable to command to read file!")
		return
	
	if pre_classifier.write_line(file_path) != OK:
		printerr("Unable to send file path!")
		return
	
	emit_signal.call_deferred("preclassify_message", "Segmenting...")
	
	var count := 0
	var processing := true
	
	while processing:
		var line = pre_classifier.read_line()
		
		var message := JSON.parse_string(line) as Dictionary
		count += 1
		
		if message == null:
			printerr("Failed to parse: %s" % line)
		
		if message["message_type"] == "segment_count":
			emit_signal.call_deferred("preclassify_max", int(message["data"]))
			emit_signal.call_deferred("preclassify_message", "Pre-classifying...")
		elif message["message_type"] == "segment":
			receive_segment(message["data"], count)
		elif message["message_type"] == "finished":
			processing = false
	
	pre_classifier.write_line("GOODBYE")
	receive_finished.call_deferred()


func _process(delta: float) -> void:
	if is_instance_valid(pre_classifier):
		if pre_classifier.is_running():
			return
		else:
			pre_classifier = null
	
	if segments.is_empty():
		return
	
	if cached_segment_index == segment_index:
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


func receive_segment(segment_data: Dictionary, count: int) -> void:
	var segment = Segment.create(segment_data["text"])
	segments.append(segment)

	var content = segment_data["content"].to_float()
	var ad = segment_data["ad"].to_float()

	if (content - ad) > 2.0:
		segment.type = Segment.Type.CONTENT
	elif (ad - content) > 2.0:
		segment.type = Segment.Type.AD
		
	emit_signal.call_deferred("preclassify_value", count)


func receive_finished() -> void:
	preclassify_finished.emit()
	
	var first := true
	
	for segment in segments:
		segment.init()
		segment_list.add_child(segment.label)

		if first:
			segment.label.modulate = colors[segment.type]
			first = false
		else:
			segment.label.modulate = colors[segment.type] * unfocused_mod
	
	await get_tree().process_frame

	var viewport_height = size.y
	var label_half_height = segment_list.get_child(0).size.y / 2.0

	screen_midpoint = viewport_height / 2.0
	var target_height = screen_midpoint - label_half_height
	segment_list.position.y = target_height
	cached_target_position = segment_list.global_position.y

	modulate = Color.WHITE
	pre_classify_thread.wait_to_finish()
	
	check_finished()


func set_file_path(file_path: String) -> void:
	pre_classify_thread.start(_preclassify_thread_func.bind(file_path))
	modulate = Color.TRANSPARENT


func set_prelabeled_path(file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	file.get_line() # Skip header
	
	var first = true
	while not file.eof_reached():
		var line = file.get_csv_line()
		
		if line.size() != 2:
			continue
		
		var text = ", ".join(line.slice(1))
		
		var segment = Segment.create(text)
		segments.append(segment)

		if line[0] == "non-sponsor":
			segment.type = Segment.Type.CONTENT
		elif line[0] == "sponsor":
			segment.type = Segment.Type.AD
		segment.init()
		segment_list.add_child(segment.label)

		if first:
			segment.label.modulate = colors[segment.type]
			first = false
		else:
			segment.label.modulate = colors[segment.type] * unfocused_mod
		
	await get_tree().process_frame

	var viewport_height = size.y
	var label_half_height = segment_list.get_child(0).size.y / 2.0

	screen_midpoint = viewport_height / 2.0
	var target_height = screen_midpoint - label_half_height
	segment_list.position.y = target_height
	cached_target_position = segment_list.global_position.y
	
	check_finished()


func mark_content() -> void:
	segments[segment_index].type = Segment.Type.CONTENT
	advance_segment(1)


func mark_advert() -> void:
	segments[segment_index].type = Segment.Type.AD
	advance_segment(1)


func advance_segment(direction: int) -> void:
	var next_segment_index = segment_index + direction
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


func start_adjust_bounds() -> PackedStringArray:
	var out := PackedStringArray()
	adjusting_from = []
	
	if segment_index > 0:
		out.push_back(segments[segment_index - 1].text)
		adjusting_from.push_back(segments[segment_index - 1].text)
	else:
		out.push_back("")
	
	out.push_back(segments[segment_index].text)
	adjusting_from.push_back(segments[segment_index].text)
	
	if segment_index < (segments.size() - 1):
		out.push_back(segments[segment_index + 1].text)
		adjusting_from.push_back(segments[segment_index + 1].text)
	else:
		out.push_back("")
	
	return out


func finish_adjust_bounds(new_segments: PackedStringArray) -> void:
	var adjusting_to: Array[String] = []
	
	if segment_index > 0:
		if new_segments[0].is_empty():
			segments[segment_index - 1].label.queue_free()
			segments.remove_at(segment_index - 1)
			segment_index -= 1
		else:
			segments[segment_index - 1].update_text(new_segments[0])
			adjusting_to.push_back(new_segments[0])
	elif not new_segments[0].is_empty():
		var segment = Segment.create(new_segments[0], true)
		segment.init()
		segments.insert(0, segment)
		segment_list.add_child(segment.label)
		segment_list.move_child(segment.label, 0)
		segment.label.modulate = colors[0] * unfocused_mod
		segment_index += 1
		adjusting_to.push_back(new_segments[0])
	
	segments[segment_index].update_text(new_segments[1])
	adjusting_to.push_back(new_segments[1])
	
	if segment_index < (segments.size() - 1):
		if new_segments[2].is_empty():
			segments[segment_index + 1].label.queue_free()
			segments.remove_at(segment_index + 1)
		else:
			segments[segment_index + 1].update_text(new_segments[2])
			adjusting_to.push_back(new_segments[2])
	elif not new_segments[2].is_empty():
		var segment = Segment.create(new_segments[2], true)
		segment.init()
		segments.append(segment)
		segment_list.add_child(segment.label)
		segment.label.modulate = colors[0] * unfocused_mod
		adjusting_to.push_back(new_segments[2])
	
	adjustments.push_back({
		"original": adjusting_from,
		"adjusted": adjusting_to
	})
	
	cached_segment_index = -1
	check_finished()


func start_split_segment() -> String:
	adjusting_from = [segments[segment_index].text]
	return String(segments[segment_index].text)


func finish_split_segment(new_segments: PackedStringArray) -> void:
	var adjusting_to: Array[String] = []
	
	if not new_segments[0].is_empty():
		var segment = Segment.create(new_segments[0], true)
		segment.init()
		segments.insert(segment_index, segment)
		segment_list.add_child(segment.label)
		segment_list.move_child(segment.label, segment_index)
		segment.label.modulate = colors[0] * unfocused_mod
		segment_index += 1
		adjusting_to.push_back(new_segments[0])
	
	segments[segment_index].update_text(new_segments[1])
	adjusting_to.push_back(new_segments[1])
	
	if not new_segments[2].is_empty():
		var segment = Segment.create(new_segments[2], true)
		segment.init()
		segments.insert(segment_index + 1, segment)
		segment_list.add_child(segment.label)
		segment_list.move_child(segment.label, segment_index + 1)
		segment.label.modulate = colors[0] * unfocused_mod
		adjusting_to.push_back(new_segments[2])
	
	adjustments.push_back({
		"original": adjusting_from,
		"adjusted": adjusting_to
	})
	
	cached_segment_index = -1
	check_finished()


func jump_first_unlabeled() -> void:
	for index in range(segments.size()):
		if segments[index].type == Segment.Type.UNLABELED:
			var delta = index - segment_index
			advance_segment(delta)
			return


func _on_gui_input(event: InputEvent) -> void:
	if scroll_debounce_active:
		return
	
	if event is InputEventMouseButton:
		var mb := (event as InputEventMouseButton)
		
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				advance_segment(-1)
				scroll_debounce()
			MOUSE_BUTTON_WHEEL_DOWN:
				advance_segment(1)
				scroll_debounce()
			_:
				return
	elif event is InputEventPanGesture:
		var pg := (event as InputEventPanGesture)
		
		if pg.delta.y < 0:
			advance_segment(-1)
			scroll_debounce()
		elif pg.delta.y > 0:
			advance_segment(1)
			scroll_debounce()


func scroll_debounce() -> void:
	scroll_debounce_active = true
	scroll_debouncer.start()

func _on_scroll_debouncer_timeout() -> void:
	scroll_debounce_active = false


func check_finished() -> void:
	var is_finished: bool = segments.reduce(func(accum: bool, segment: Segment) -> bool:
		return accum and (segment.type != Segment.Type.UNLABELED)
	, true)
	
	finished.emit(is_finished)


func get_classifications() -> Array[Dictionary]:
	var classifications: Array[Dictionary] = []
	
	for segment in segments:
		if segment.type == Segment.Type.UNLABELED:
			continue
		
		var type = "content" if segment.type == Segment.Type.CONTENT else "ad"
		classifications.append({ "text": segment.text, "type": type })
	
	return classifications


func get_adjustments() -> Array[Dictionary]:
	return adjustments


func _pre_classify(text: String) -> Segment.Type:
	if not is_instance_valid(pre_classifier):
		printerr("Pre-classifier not initialized!")
		return Segment.Type.UNLABELED
	
	if not pre_classifier.is_running():
		printerr("Pre-classifier is not running!")
		return Segment.Type.UNLABELED
	
	if pre_classifier.write_line("PREDICT") != OK or pre_classifier.read_line() != "OK":
		printerr("Pre-classifier is not ready!")
		return Segment.Type.UNLABELED
	
	if pre_classifier.write_line(text) != OK:
		printerr("Could not send segment to pre-classifier!")
		return Segment.Type.UNLABELED
	
	var errors = []
	var response = pre_classifier.read_line(BoundProcess.READ_STDOUT, errors)
	if errors[0] != OK:
		printerr("Pre-classifier could not send response!\n\t%s" % errors[0])
		return Segment.Type.UNLABELED
	
	if response == "ERROR":
		printerr("Pre-classifier returned an error!")
		
		var error = pre_classifier.read_line(BoundProcess.READ_STDOUT, errors)
		if errors[1] != OK:
			printerr("Pre-classifier could not send error!")
			return Segment.Type.UNLABELED
		
		print("Error received from pre-classifier:\n\t", error)
		return Segment.Type.UNLABELED
	
	if not response.is_valid_int():
		printerr("Pre-classifier did not return an expected value!")
		return Segment.Type.UNLABELED
	
	var resp_value = response.to_int()
	
	if resp_value < 0 or resp_value >= Segment.Type.MAX:
		printerr("Pre-classifier did not return an expected value!")
		return Segment.Type.UNLABELED
	
	return resp_value as Segment.Type
