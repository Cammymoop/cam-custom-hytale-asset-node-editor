extends PanelContainer

@export var theme_colors_flow: Control
@export var type_colors_flow: Control

func _ready() -> void:
    visibility_changed.connect(on_visibility_changed)

func on_visibility_changed() -> void:
    if visible:
        theme_colors_flow.setup()
        type_colors_flow.setup()
    else:
        print("theme editor hidden")
        ThemeColorVariants.recreate_variants()
        var graph_edit: AssetNodeGraphEdit = get_tree().current_scene.find_child("AssetNodeGraphEdit")
        graph_edit.update_all_gns_themes()
    
