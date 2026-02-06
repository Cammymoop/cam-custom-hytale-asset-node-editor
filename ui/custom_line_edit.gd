extends LineEdit
class_name CustomLineEdit

var base_theme_type_variation: = ""

func _init() -> void:
    caret_blink = true
    base_theme_type_variation = theme_type_variation
    editing_toggled.connect(on_editing_toggled)

func _ready() -> void:
    theme_type_variation = base_theme_type_variation

func on_editing_toggled(is_editing: bool) -> void:
    if is_editing:
        theme_type_variation = "LineEditEditing"
    else:
        theme_type_variation = base_theme_type_variation