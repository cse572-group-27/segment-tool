extends Control

@onready var classifier := %Classifier
@onready var continue_button := %ContinueButton

@onready var classify_buttons: Array[Button] = [
	%AdjustBoundsButton,
	%MarkAdvertButton,
	%MarkContentButton
]


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var sample_count = 10
	
	var sample_text = []
	
	for sample in range(sample_count):
		var text = "Sample #%d " % sample
		sample_text.append(text.repeat(100) + "Sample #%d" % sample)
	
	classifier.set_segments(sample_text)


func _on_classifier_finished() -> void:
	continue_button.visible = true


func _on_classifier_set_inputs_disabled(disabled) -> void:
	for button in classify_buttons:
		button.disabled = disabled
