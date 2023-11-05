extends Control

@onready var vbox := $VBoxContainer2
@onready var button := $VBoxContainer2/VBoxContainer/Button
@onready var dialog := $VBoxContainer2/VBoxContainer/FileDialog

const MAIN := preload("res://main.tscn")

var main: Control = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	dialog.get_theme_stylebox("panel").bg_color = RenderingServer.get_default_clear_color()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	dialog.visible = true


func _on_file_dialog_file_selected(path: String) -> void:
	dialog.visible = false
	
	main = MAIN.instantiate()
	main.segments = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	
	add_child(main)
	vbox.visible = false
	main.connect("close", _on_main_close)


func _on_main_close() -> void:
	main.queue_free()
	vbox.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()
