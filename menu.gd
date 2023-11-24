extends Control

@onready var vbox := $VBoxContainer2
@onready var button := $VBoxContainer2/VBoxContainer/VBoxContainer/Button
@onready var prelabeled_button := $VBoxContainer2/VBoxContainer/VBoxContainer/PreLabeledButton
@onready var dialog := $VBoxContainer2/VBoxContainer/FileDialog
@onready var prelabeled_dialog := $VBoxContainer2/VBoxContainer/PreLabeledDialog

const MAIN := preload("res://main.tscn")

var main: Control = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	dialog.get_theme_stylebox("panel").bg_color = RenderingServer.get_default_clear_color()


func _on_button_pressed() -> void:
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	dialog.visible = true


func _on_file_dialog_file_selected(path: String) -> void:
	dialog.visible = false
	
	main = MAIN.instantiate()
	main.set_file_path(path)
	
	add_child(main)
	vbox.visible = false
	main.connect("close", _on_main_close)


func _on_main_close() -> void:
	main.queue_free()
	vbox.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_pre_labeled_button_pressed() -> void:
	prelabeled_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	prelabeled_dialog.visible = true


func _on_pre_labeled_dialog_file_selected(path: String) -> void:
	dialog.visible = false
	
	main = MAIN.instantiate()
	main.set_prelabeled_path(path)
	
	add_child(main)
	vbox.visible = false
	main.connect("close", _on_main_close)
