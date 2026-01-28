@tool
extends PanelContainer

@export var graph_edit: AssetNodeGraphEdit
var schema: AssetNodesSchema

@export var scroll_min_height: = 100
@export var scroll_max_height_ratio: = 0.85
var scroll_max_height: = 0

@onready var scroll_container: ScrollContainer = find_child("ScrollContainer")
@onready var node_list_tree: Tree = scroll_container.get_node("Tree")

@export var preview_categories: Array[String] = []:
    get: return preview_categories
    set(value):
        preview_categories = value.duplicate()
        if Engine.is_editor_hint():
            rebuild_preview_tree()
@export var preview_items: Array[String] = []:
    get: return preview_items
    set(value):
        preview_items = value.duplicate()
        if Engine.is_editor_hint():
            rebuild_preview_tree()

var an_types_by_output_value_type: Dictionary[String, Array] = {}
var an_types_by_input_value_type: Dictionary[String, Array] = {}
var an_input_types: Dictionary[String, Array] = {}

var test_filters: Array = [
    true, "Density",
    false, "Density",
    true, "CurvePoint",
    false, "CurvePoint",
    true, "KeyMultiMix",
    false, "KeyMultiMix",
    true, "Material",
    false, "Material",
]
var test_filter_idx: int = -1

func _ready() -> void:
    set_max_popup_height()
    get_window().size_changed.connect(set_max_popup_height)
    node_list_tree.resized.connect(on_tree_size_changed)
    if Engine.is_editor_hint():
        return
    if not graph_edit:
        push_warning("Graph edit is not set, please set it in the inspector")
        print("Graph edit is not set, please set it in the inspector")
    schema = graph_edit.schema
    
    #rebuild_preview_tree()

    build_lookups()
    build_node_list()

func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        return
    if Input.is_action_just_pressed("_debug_next_filter") and OS.has_feature("debug"):
        test_filter_idx += 1
        if test_filter_idx >= floori(test_filters.size() / 2.):
            test_filter_idx = 0
        open_menu(test_filters[test_filter_idx * 2], test_filters[test_filter_idx * 2 + 1])

func build_lookups() -> void:
    an_types_by_input_value_type.clear()
    an_types_by_output_value_type.clear()
    an_input_types.clear()
    for val_type in schema.value_types:
        an_types_by_output_value_type[val_type] = Array([], TYPE_STRING, "", null)
        an_types_by_input_value_type[val_type] = Array([], TYPE_STRING, "", null)
    
    for node_type in schema.node_schema.keys():
        an_input_types[node_type] = Array([], TYPE_STRING, "", null)

    for an_type in schema.node_schema.keys():
        var output_value_type: String = schema.node_schema[an_type].get("output_value_type", "")
        if output_value_type and output_value_type in schema.value_types:
            an_types_by_output_value_type[output_value_type].append(an_type)
        
        for conn_name in schema.node_schema[an_type].get("connections", {}).keys():
            var conn_value_type: String = schema.node_schema[an_type]["connections"][conn_name]["value_type"]
            an_types_by_input_value_type[conn_value_type].append(an_type)
            an_input_types[an_type].append(conn_value_type)

func build_node_list() -> void:
    if not schema:
        print("No schema, cannot build node list")
        return
    node_list_tree.clear()
    var root_item: = node_list_tree.create_item(null)
    for val_type in schema.value_types:
        var type_category_item: = root_item.create_child()
        type_category_item.set_text(0, val_type)
        type_category_item.set_selectable(0, false)
        type_category_item.set_custom_color(0, Color.WHITE)
        type_category_item.set_custom_bg_color(0, TypeColors.get_actual_color_for_type(val_type))
    
    for category_parent in root_item.get_children():
        var val_type: = category_parent.get_text(0)
        for node_type in an_types_by_output_value_type[val_type]:
            var node_type_item: = category_parent.create_child()
            var display_name: String = schema.node_schema[node_type].get("display_name", node_type)
            node_type_item.set_text(0, display_name)
            node_type_item.set_meta("node_type", node_type)
            node_type_item.set_tooltip_text(0, "%s (%s)" % [display_name, node_type])

func hide_all_categories() -> void:
    for category_item in node_list_tree.get_root().get_children():
        category_item.visible = false

func set_category_items_visible(type_category: String, to_visible: bool) -> void:
    for category_item in node_list_tree.get_root().get_children():
        if category_item.get_text(0) == type_category:
            for child_item in category_item.get_children():
                child_item.visible = to_visible

func show_all_items() -> void:
    for category_item in node_list_tree.get_root().get_children():
        category_item.visible = true
        for child_item in category_item.get_children():
            child_item.visible = true

func filter_node_list_output(val_type: String) -> void:
    hide_all_categories()
    for category_item in node_list_tree.get_root().get_children():
        if category_item.get_text(0) == val_type:
            category_item.visible = true
            set_category_items_visible(category_item.get_text(0), true)

func filter_node_list_input(val_type: String) -> void:
    hide_all_categories()
    for category_item in node_list_tree.get_root().get_children():
        for child_item in category_item.get_children():
            var item_node_type: = child_item.get_meta("node_type", "") as String
            if val_type in an_input_types[item_node_type]:
                if not category_item.visible:
                    category_item.visible = true
                    set_category_items_visible(category_item.get_text(0), false)
                child_item.visible = true

func open_menu(for_left_connection: bool, connection_value_type: String) -> void:
    show()
    if for_left_connection:
        filter_node_list_output(connection_value_type)
    else:
        filter_node_list_input(connection_value_type)

func rebuild_preview_tree() -> void:
    if not is_inside_tree():
        return
    scroll_container = find_child("ScrollContainer")
    node_list_tree = scroll_container.get_node("Tree")
    if not schema:
        schema = AssetNodesSchema.new()
    if not an_types_by_input_value_type:
        build_lookups()
    build_node_list()
    filter_node_list_output("Density")

func on_tree_size_changed() -> void:
    print("tree size changed")
    scroll_container.custom_minimum_size.y = clampi(int(node_list_tree.size.y), scroll_min_height, scroll_max_height)

func set_max_popup_height() -> void:
    var window_height: = get_window().size.y
    scroll_max_height = roundi(window_height * scroll_max_height_ratio)
