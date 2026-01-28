extends Node

signal requested_open_file(path: String)
signal requested_save_file(path: String)

var last_open_from_directory: String = ""

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("open_file_shortcut"):
        show_open_file_dialog()
    if Input.is_action_just_pressed("save_file_shortcut"):
        show_save_file_dialog()

func show_open_file_dialog() -> void:
    var file_dialog: FileDialog = FileDialog.new()
    file_dialog.use_native_dialog = true
    if last_open_from_directory:
        file_dialog.current_dir = last_open_from_directory
    else:
        file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
    file_dialog.filters = ["*.json"]
    
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    
    file_dialog.canceled.connect(on_open_dialog_closed)
    file_dialog.file_selected.connect(on_file_selected)
    
    file_dialog.popup()

func on_file_selected(path: String) -> void:
    last_open_from_directory = path.get_base_dir()
    on_open_dialog_closed()
    requested_open_file.emit(path)

func on_open_dialog_closed() -> void:
    pass


func show_save_file_dialog() -> void:
    var file_dialog: FileDialog = FileDialog.new()
    file_dialog.use_native_dialog = true
    if last_open_from_directory:
        file_dialog.current_dir = last_open_from_directory
    else:
        file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)

    file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    file_dialog.add_filter("*.json", "JSON files")
    file_dialog.canceled.connect(on_save_dialog_closed)
    file_dialog.file_selected.connect(on_file_save_location_selected)
    file_dialog.popup()

func on_save_dialog_closed() -> void:
    pass

func on_file_save_location_selected(path: String) -> void:
    last_open_from_directory = path.get_base_dir()
    on_save_dialog_closed()
    requested_save_file.emit(path)