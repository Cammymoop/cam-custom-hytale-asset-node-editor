extends PanelContainer

signal closing

@export var dialog_handler: DialogHandler
@onready var prompt: Label = find_child("Prompt")

var after_save_callback: Callable = Callable()

func _ready() -> void:
    assert(dialog_handler != null, "Save Confirm: Dialog handler is not set, please set it in the inspector")
    visibility_changed.connect(on_visibility_changed)

func on_visibility_changed() -> void:
    if not visible:
        after_save_callback = Callable()
        prompt.text = ""

func set_prompt_text(prompt_text: String) -> void:
    prompt.text = prompt_text

func set_after_save_callback(new_callback: Callable) -> void:
    if new_callback.is_valid():
        after_save_callback = new_callback
    else:
        after_save_callback = Callable()

func on_cancel() -> void:
    after_save_callback = Callable()
    closing.emit()

func on_ignore_save_chosen() -> void:
    if after_save_callback.is_valid():
        after_save_callback.call()
    after_save_callback = Callable()
    closing.emit()

func show_save_dialog() -> void:
    dialog_handler.show_save_file_dialog()
    if not dialog_handler.requested_save_file.is_connected(current_was_saved):
        dialog_handler.requested_save_file.connect(current_was_saved.unbind(1), CONNECT_ONE_SHOT)

func current_was_saved() -> void:
    var graph_edit: AssetNodeGraphEdit = get_tree().current_scene.find_child("AssetNodeGraphEdit")
    await graph_edit.finished_saving
    if after_save_callback.is_valid():
        after_save_callback.call()
    after_save_callback = Callable()
    closing.emit()
