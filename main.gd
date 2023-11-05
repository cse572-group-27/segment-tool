extends Control

signal close

@onready var classifier := %Classifier
@onready var continue_button := %ContinueButton
@onready var bounds_adjuster := %BoundsAdjuster
@onready var bounds_adjuster_label := %BoundsAdjusterLabel
@onready var bounds_save_button := %BoundsSaveButton
@onready var dialog := $FileDialog


@export var bounds_adjuster_prev_color: Color
@export var bounds_adjuster_color: Color
@export var bounds_adjuster_next_color: Color

enum AdjustMode {
	ADJUST,
	SPLIT
}

var adjust_mode: AdjustMode

var segments: PackedStringArray


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	classifier.set_segments(segments)
	dialog.get_theme_stylebox("panel").bg_color = RenderingServer.get_default_clear_color()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := (event as InputEventKey)
		
		if not k.pressed:
			return
		
		if k.physical_keycode == KEY_SPACE or k.physical_keycode == KEY_DOWN:
			classifier.advance_segment(1)
		elif k.physical_keycode == KEY_UP:
			classifier.advance_segment(-1)
		elif k.physical_keycode == KEY_J:
			classifier.mark_advert()
		elif k.physical_keycode == KEY_K:
			classifier.mark_content()


func _on_classifier_finished(is_finished: bool) -> void:
	continue_button.visible = is_finished


func _on_adjust_bounds_button_pressed() -> void:
	var segments = classifier.start_adjust_bounds()
	bounds_adjuster.visible = true
	
	bounds_adjuster_label.clear()
	
	if (segments[0] != ""):
		bounds_adjuster_label.push_color(bounds_adjuster_prev_color)
		bounds_adjuster_label.append_text(segments[0])
		bounds_adjuster_label.pop()
		
	bounds_adjuster_label.push_color(bounds_adjuster_color)
	bounds_adjuster_label.append_text(segments[1])
	bounds_adjuster_label.pop()
	
	if (segments[2] != ""):
		bounds_adjuster_label.push_color(bounds_adjuster_next_color)
		bounds_adjuster_label.append_text(segments[2])
		bounds_adjuster_label.pop()
	
	bounds_adjuster_label.set_selection_from(segments[0].length())
	bounds_adjuster_label.set_selection_to(segments[0].length() + segments[1].length())
	
	adjust_mode = AdjustMode.ADJUST
	
	await get_tree().process_frame
	bounds_adjuster_label.scroll_to_selection_centered()


func _on_bounds_adjuster_revert_button_pressed() -> void:
	bounds_adjuster.visible = false


func _on_save_button_pressed() -> void:
	var updated_segments := PackedStringArray([
		bounds_adjuster_label.get_before_selected_text(),
		bounds_adjuster_label.get_selected_text(),
		bounds_adjuster_label.get_after_selected_text()
	])
	
	if adjust_mode == AdjustMode.ADJUST:
		classifier.finish_adjust_bounds(updated_segments)
	else:
		classifier.finish_split_segment(updated_segments)
	
	bounds_adjuster.visible = false


func _on_bounds_adjuster_label_selection_active(valid: bool) -> void:
	bounds_save_button.disabled = not valid


func _on_split_segment_button_pressed() -> void:
	var segment = classifier.start_split_segment()
	bounds_adjuster.visible = true
	
	bounds_adjuster_label.text = ""
	bounds_adjuster_label.text = segment
	bounds_adjuster_label.set_selection_from(0)
	bounds_adjuster_label.set_selection_to(segment.length())
	
	adjust_mode = AdjustMode.SPLIT


func _on_cancel_button_pressed() -> void:
	close.emit()


func _on_continue_button_pressed() -> void:
	dialog.visible = true


func _on_file_dialog_file_selected(path: String) -> void:
	dialog.visible = false
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	
	var data = {
		"classifications": classifier.get_classifications(),
		"adjustments": classifier.get_adjustments()
	}
	
	file.store_string(JSON.stringify(data))
	
	file.close()
	
	close.emit()


func _on_jump_unlabeled_button_pressed() -> void:
	classifier.jump_first_unlabeled()
