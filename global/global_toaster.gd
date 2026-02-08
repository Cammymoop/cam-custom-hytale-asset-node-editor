extends Node

func show_toast_message(message: String) -> void:
    var toast_message_container: ToastMessageContainer = get_tree().current_scene.get_node_or_null("%ToastMessageContainer")
    if not toast_message_container:
        push_error("ToastMessageContainer not found in the current scene")
        return
    toast_message_container.show_toast_message(message)