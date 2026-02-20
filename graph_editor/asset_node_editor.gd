class_name CHANE_AssetNodeEditor
extends Control

const AssetNodeFileHelper = preload("./asset_node_file_helper.gd")

const SpecialGNFactory = preload("res://graph_editor/custom_graph_nodes/special_gn_factory.gd")
const GraphNodeFactory = preload("res://graph_editor/custom_graph_nodes/graph_node_factory.gd")

const UndoManager = preload("res://graph_editor/undo_redo/undo_manager.gd")

enum ContextMenuItems {
    COPY_NODES = 1,
    CUT_NODES,
    CUT_NODES_DEEP,
    PASTE_NODES,
    DUPLICATE_NODES,

    DELETE_NODES,
    DELETE_NODES_DEEP,
    DELETE_GROUPS_ONLY,
    DISSOLVE_NODES,
    BREAK_CONNECTIONS,
    
    EDIT_TITLE,
    EDIT_GROUP_TITLE,
    
    CHANGE_GROUP_COLOR,
    SET_GROUP_SHRINKWRAP,
    SET_GROUP_NO_SHRINKWRAP,

    SELECT_SUBTREE,
    SELECT_SUBTREE_GREEDY,
    SELECT_GROUP_NODES,
    SELECT_GROUPS_NODES,
    SELECT_ALL,
    DESELECT_ALL,
    INVERT_SELECTION,
    
    CREATE_NEW_NODE,
    CREATE_NEW_GROUP,
    
    NEW_FILE,
}

const DEFAULT_HY_WORKSPACE_ID: String = "HytaleGenerator - Biome"
var hy_workspace_id: String = ""

var graphs: Array[CHANE_AssetNodeGraphEdit] = []
var focused_graph: CHANE_AssetNodeGraphEdit = null

var serializer: CHANE_HyAssetNodeSerializer

@export var popup_menu_root: PopupMenuRoot

@export var save_formatted_json: = true

@export var use_json_positions: = true
@export var json_positions_scale: Vector2 = Vector2(0.6, 0.6)

@onready var graph_node_factory: GraphNodeFactory = GraphNodeFactory.new()
@onready var special_gn_factory: SpecialGNFactory = graph_node_factory.special_gn_factory

var undo_manager: UndoManager = UndoManager.new()

var cur_drop_info: Dictionary = {}

var root_asset_node: HyAssetNode = null
var root_graph_node: CustomGraphNode = null
var all_asset_nodes: Dictionary[String, HyAssetNode] = {}
var asset_node_aux_data: Dictionary[String, HyAssetNode.AuxData] = {}

var floating_an_tree_roots: Array[String] = []

var gn_lookup: Dictionary[String, CustomGraphNode] = {}

var raw_metadata: Dictionary = {}

var is_loaded: = false

var file_helper: AssetNodeFileHelper
var file_history_version: int = -10 

func _ready() -> void:
    serializer = CHANE_HyAssetNodeSerializer.new()
    serializer.name = "HyAssetNodeSerializer"
    add_child(serializer, true)
    undo_manager.set_editor(self)

    file_helper = AssetNodeFileHelper.new()
    file_helper.name = "FileHelper"
    file_helper.after_loaded.connect(on_after_file_loaded)
    file_helper.after_saved.connect(on_after_file_saved)
    add_child(file_helper, true)

    get_window().files_dropped.connect(on_files_dropped)

    FileDialogHandler.requested_open_file.connect(_on_requested_open_file)
    FileDialogHandler.requested_save_file.connect(_on_requested_save_file)
    
    popup_menu_root.new_gn_menu.node_type_picked.connect(on_new_node_type_picked)
    popup_menu_root.new_gn_menu.cancelled.connect(on_new_node_menu_cancelled)
    popup_menu_root.popup_menu_opened.connect(on_popup_menu_opened)

    for child in get_children():
        if child is CHANE_AssetNodeGraphEdit:
            child.set_editor(self)
            graphs.append(child)
    if graphs.size() > 0:
        focused_graph = graphs[0]

    await get_tree().process_frame
    if not is_loaded:
        popup_menu_root.show_new_file_type_chooser()
    
    graph_node_factory.name = "GraphNodeFactory"
    add_child(graph_node_factory, true)

func is_different_from_file_version() -> bool:
    return undo_manager.undo_redo.get_version() != file_history_version

func on_after_file_loaded() -> void:
    undo_manager.clear()

func on_after_file_saved() -> void:
    file_history_version = undo_manager.undo_redo.get_version()
    undo_manager.prevent_merges()

func connect_new_request(drop_info: Dictionary) -> void:
    cur_drop_info = drop_info
    popup_menu_root.show_filtered_new_gn_menu(drop_info["is_right"], drop_info["connection_value_type"])

func on_new_node_type_picked(node_type: String) -> void:
    var new_an: HyAssetNode = get_new_asset_node(node_type)
    var dropping_in_graph: CHANE_AssetNodeGraphEdit = cur_drop_info.get("dropping_in_graph", null)
    var dropping_at_pos_offset: Vector2 = cur_drop_info.get("dropping_at_pos_offset", Vector2.ZERO)
    var pos_is_centered: bool = false
    if not cur_drop_info.get("has_position", false):
        dropping_at_pos_offset = dropping_in_graph.get_center_pos_offset()
        pos_is_centered = true
    var new_gn: = make_and_add_graph_node(dropping_in_graph, new_an, dropping_at_pos_offset, pos_is_centered, true)

    var skip_connection: bool = true
    var connection_info: Dictionary = {}
    if cur_drop_info.get("connection_info", {}):
        var conn_value_type: String = cur_drop_info.get("connection_value_type", "")
        connection_info = cur_drop_info["connection_info"]
        skip_connection = not can_connect_dropped_node(connection_info, new_an.an_type, conn_value_type)

        if connection_info.has("from_node"):
            connection_info["to_node"] = new_gn.name
            connection_info["to_port"] = 0
            new_gn.position_offset += dropping_in_graph.get_drop_offset_for_output_port()
        else:
            connection_info["from_node"] = new_gn.name
            # start at top right corner
            new_gn.position_offset.x -= new_gn.size.x
            # "from_port" already set by can_connect_dropped_node()
            new_gn.position_offset += dropping_in_graph.get_drop_offset_for_input_port(connection_info["from_port"])
        
    if cur_drop_info.get("into_group", null):
        dropping_in_graph.add_ge_to_group(new_gn, cur_drop_info["into_group"], true)
    if skip_connection:
        pass#create_add_new_ge_undo_step(new_gn)
    else:
        pass
        #cur_connection_added_ges.append(new_gn)
        dropping_in_graph.add_connection_info(connection_info)

## Also updates dropped_conn_info["from_port"] if it found a valid input port for a left connect
func can_connect_dropped_node(dropped_conn_info: Dictionary, dropped_node_type: String, conn_value_type: String) -> bool:
    if dropped_conn_info.has("from_node"):
        var num_outputs: int = SchemaManager.schema.get_num_output_connections(dropped_node_type)
        if num_outputs == 0:
            return false
        var output_type: String = SchemaManager.schema.get_output_value_type(dropped_node_type)
        return conn_value_type == "" or conn_value_type == output_type
    else:
        var input_value_types: Array[String] = SchemaManager.schema.get_input_conn_value_types_list(dropped_node_type)
        var first_with_type_idx: = input_value_types.find(conn_value_type)
        if first_with_type_idx >= 0:
            dropped_conn_info["from_port"] = first_with_type_idx
        return first_with_type_idx >= 0


func on_new_node_menu_cancelled() -> void:
    clear_cur_drop_info()

func clear_cur_drop_info() -> void:
    cur_drop_info.clear()

func on_file_menu_id_pressed(id: int, file_menu: PopupMenu) -> void:
    var menu_item_text: = file_menu.get_item_text(file_menu.get_item_index(id))
    match menu_item_text:
        "Open":
            FileDialogHandler.show_open_file_dialog()
        "Save":
            if file_helper.has_saved_to_cur_file:
                resave_current_file()
            else:
                FileDialogHandler.show_save_file_dialog(file_helper.has_cur_file())
        "Save As ...":
            FileDialogHandler.show_save_file_dialog(false)
        "New":
            popup_menu_root.show_new_file_type_chooser()

func on_settings_menu_index_pressed(index: int, settings_menu: PopupMenu) -> void:
    var menu_item_text: = settings_menu.get_item_text(index)
    match menu_item_text:
        "Customize Theme Colors":
            popup_menu_root.show_theme_editor()
    if index == 1:
        ANESettings.set_subtree_greedy_mode(not ANESettings.select_subtree_is_greedy)

func on_popup_menu_opened() -> void:
    for graph in graphs:
        if graph.has_focus():
            prints("popup menu opened, graph %s had focus" % [graph.get_path()])
            graph.release_focus()

# TODO: This should be outside the context of a single editor if multiple editors are supported
func on_files_dropped(dragged_files: PackedStringArray) -> void:
    var json_files: Array[String] = []
    for dragged_file in dragged_files:
        if dragged_file.get_extension() == "json":
            json_files.append(dragged_file)
    if json_files.size() == 0:
        return
    var json_file_path: String = json_files[0]
    prompt_and_load_file(json_file_path)

func _pre_serialize() -> void:
    for graph in graphs:
        graph.sort_all_an_connections()
    update_all_aux_positions()

func are_shortcuts_allowed() -> bool:
    return not popup_menu_root.is_menu_visible()

func update_all_aux_positions() -> void:
    for graph in graphs:
        update_graph_all_aux_positions(graph)

func update_graph_all_aux_positions(graph: CHANE_AssetNodeGraphEdit) -> void:
    for graph_node in graph.get_all_graph_nodes():
        graph_node.update_aux_positions(asset_node_aux_data)

func _on_new_file_type_chosen(workspace_id: String) -> void:
    prompt_and_make_new_file(workspace_id)

func prompt_and_make_new_file(workspace_id: String) -> void:
    if is_different_from_file_version() or all_asset_nodes.size() <= 1:
        _make_new_file_with_workspace_id(workspace_id)
    else:
        var prompt_text: = "Do you want to save the current file before creating a new file?"
        popup_menu_root.show_save_confirm(prompt_text, file_helper.has_cur_file(), _make_new_file_with_workspace_id.bind(workspace_id))

func _make_new_file_with_workspace_id(workspace_id: String) -> void:
    setup_new_graph(workspace_id)

func setup_new_graph(workspace_id: String = DEFAULT_HY_WORKSPACE_ID) -> void:
    clear_loaded_graph()
    hy_workspace_id = workspace_id
    # just set the normal raw metadata keys and the workspace id, everything else should be created on the fly
    raw_metadata = CHANE_HyAssetNodeSerializer.get_empty_editor_metadata()
    raw_metadata[CHANE_HyAssetNodeSerializer.MetadataKeys.WorkspaceId] = workspace_id

    var root_node_type: = SchemaManager.schema.resolve_root_asset_node_type(workspace_id, {}) as String
    var new_root_node: HyAssetNode = focused_graph.get_new_asset_node(root_node_type)
    set_root_node(new_root_node)
    var screen_center_pos: Vector2 = get_viewport_rect().size / 2
    var new_gn: CustomGraphNode = make_and_add_graph_node(focused_graph, new_root_node, screen_center_pos, true, true)
    focused_graph.scroll_to_graph_element(new_gn)
    #gn_lookup[new_root_node.an_node_id] = new_gn
    is_loaded = true
    file_helper.editing_new_file()
    
    undo_manager.clear()
    file_history_version = undo_manager.undo_redo.get_version()

func _on_requested_open_file(path: String) -> void:
    prompt_and_load_file(path)

func _on_requested_save_file(path: String) -> void:
    await get_tree().process_frame
    if not focused_graph:
        print_debug("No graphs to save")
        return
    file_helper.save_to_json_file(get_serialized_for_save(), path)

func resave_current_file() -> void:
    file_helper.resave_current_file(get_serialized_for_save())

func get_serialized_for_save() -> String:
    var serialized_data: Dictionary = serializer.serialize_entire_graph_as_asset(self)
    var json_str: = JSON.stringify(serialized_data, "  " if save_formatted_json else "", false)
    if not json_str:
        push_error("Error creating json string for node graph")
        return ""
    return json_str

func prompt_and_load_file(json_file_path: String) -> void:
    if is_different_from_file_version() or all_asset_nodes.size() <= 1:
        file_helper.load_json_file(json_file_path, on_got_loaded_data)
    else:
        var prompt_text: = "Do you want to save the current file before loading '%s'?" % json_file_path
        var has_cur: = file_helper.has_cur_file()
        popup_menu_root.show_save_confirm(prompt_text, has_cur, file_helper.load_json_file.bind(json_file_path))

func on_got_loaded_data(graph_data: Dictionary) -> void:
    if is_loaded:
        clear_loaded_graph()
    var parse_graph_result: = serializer.deserialize_entire_graph(graph_data) as CHANE_HyAssetNodeSerializer.EntireGraphParseResult
    if not parse_graph_result.success:
        push_error("Failed to deserialize graph")
        CHANE_HyAssetNodeSerializer.debug_dump_tree_results(parse_graph_result.root_tree_result)
        GlobalToaster.show_toast_message("Failed to setup node graph :(")
        return
    
    setup_edited_graph_from_parse_result(parse_graph_result)

func set_root_node(new_root_node: HyAssetNode) -> void:
    root_asset_node = new_root_node

func setup_edited_graph_from_parse_result(parse_graph_result: CHANE_HyAssetNodeSerializer.EntireGraphParseResult) -> void:
    prints("Setting up edited graph from parse result")
    is_loaded = true
    hy_workspace_id = parse_graph_result.hy_workspace_id
    use_json_positions = parse_graph_result.has_positions
    set_root_node(parse_graph_result.root_node)
    _register_asset_nodes_from_graph_result(parse_graph_result)

    raw_metadata = parse_graph_result.editor_metadata
    create_loaded_graph_elements(parse_graph_result)

func create_loaded_graph_elements(graph_result: CHANE_HyAssetNodeSerializer.EntireGraphParseResult) -> void:
    var an_roots: Array[HyAssetNode] = [root_asset_node]
    an_roots.append_array(graph_result.floating_tree_roots.values())
    prints("Creating loaded graph nodes, an roots: %s" % an_roots.size())
    add_graph_nodes_for_new_asset_node_trees(focused_graph, an_roots)
    focused_graph.make_json_groups(Array(graph_result.editor_metadata.get("$Groups", []), TYPE_DICTIONARY, &"", null))
    
    focused_graph.scroll_to_pos_offset(asset_node_aux_data[root_asset_node.an_node_id].position)

func _register_asset_nodes_from_graph_result(graph_result: CHANE_HyAssetNodeSerializer.EntireGraphParseResult) -> void:
    all_asset_nodes = graph_result.all_nodes
    asset_node_aux_data = graph_result.asset_node_aux_data.duplicate()
    update_aux_parents_for_tree(graph_result.root_node)
    for floating_root_an in graph_result.floating_tree_roots.values():
        update_aux_parents_for_tree(floating_root_an)

func update_aux_parents_for_tree(subtree_root: HyAssetNode) -> void:
    var child_ans: Array[HyAssetNode] = subtree_root.get_all_connected_nodes()
    for child_an in child_ans:
        var an_id: = child_an.an_node_id
        asset_node_aux_data[an_id].output_to_node_id = subtree_root.an_node_id
        update_aux_parents_for_tree(child_an)

func register_asset_node(asset_node: HyAssetNode, aux_data: HyAssetNode.AuxData = null) -> void:
    assert(asset_node.an_node_id, "Cannot register an asset node with no ID")
    if OS.has_feature("debug") and all_asset_nodes.has(asset_node.an_node_id):
        print_debug("Re-registering asset node with existing ID %s" % asset_node.an_node_id)
    _register_asset_node(asset_node, aux_data)

func _register_asset_node(asset_node: HyAssetNode, aux_data: HyAssetNode.AuxData = null) -> void:
    all_asset_nodes[asset_node.an_node_id] = asset_node
    if aux_data:
        asset_node_aux_data[asset_node.an_node_id] = aux_data
    else:
        asset_node_aux_data[asset_node.an_node_id] = HyAssetNode.AuxData.new()

func register_asset_nodes(asset_nodes: Array[HyAssetNode], aux_data: Array[HyAssetNode.AuxData]) -> void:
    for i in asset_nodes.size():
        _register_asset_node(asset_nodes[i], aux_data[i])

func register_asset_node_at(asset_node: HyAssetNode, node_pos: Vector2, with_parent_id: String = "") -> void:
    var aux_data: HyAssetNode.AuxData = HyAssetNode.AuxData.new()
    aux_data.position = node_pos
    aux_data.output_to_node_id = with_parent_id
    register_asset_node(asset_node, aux_data)

func register_duplicate_asset_node(new_asset_node: HyAssetNode, duplicated_from_id: String, with_parent_id: String = "") -> void:
    var duplicate_aux_data: = asset_node_aux_data[duplicated_from_id].duplicate_with_parent(with_parent_id)
    register_asset_node(new_asset_node, duplicate_aux_data)

func remove_asset_node_id(asset_node_id: String) -> void:
    all_asset_nodes.erase(asset_node_id)
    asset_node_aux_data.erase(asset_node_id)

func remove_asset_node(asset_node: HyAssetNode) -> void:
    assert(asset_node.an_node_id, "Cannot remove an asset node with no ID")
    remove_asset_node_id(asset_node.an_node_id)

func remove_asset_nodes(asset_nodes: Array[HyAssetNode]) -> void:
    for asset_node in asset_nodes:
        remove_asset_node_id(asset_node.an_node_id)

## Create duplicates of all nodes in the given set, maintaining connections between nodes within the set
## Returns the list of new subtree roots if return_roots = true, otherwise returns the list of all new asset nodes
## Also register the new asset nodes and add them to the current undo step if register = true
## If register = false, duplicate aux data will be created and added into out_aux
func create_duplicate_filtered_an_set(asset_node_set: Array[HyAssetNode], return_roots: bool, register: bool = true, out_aux: Dictionary[String, HyAssetNode.AuxData] = {}) -> Array[HyAssetNode]:
    var ret: Array[HyAssetNode] = []
    if asset_node_set.size() == 0:
        return ret
    var set_roots: Array[HyAssetNode] = get_an_roots_within_registered_set(asset_node_set)

    for set_root in set_roots:
        var new_duplicate_ans: = create_duplicate_filtered_an_tree(set_root, asset_node_set, register, out_aux)
        if return_roots:
            ret.append(new_duplicate_ans[0])
        else:
            ret.append_array(new_duplicate_ans)
    return ret

## Create duplicates of all nodes reachable from the given root node while only passing through nodes in the given set
## Maintains connections within the subtree
## Also register the new asset nodes and add them to the current undo step if register = true
## If register = false, duplicate aux data will be created and added into out_aux
## If asset_node_set is empty, no filter is applied, all nodes in the subtree are duplicated
func create_duplicate_filtered_an_tree(tree_root: HyAssetNode, asset_node_set: Array[HyAssetNode], register: bool = true, out_aux: Dictionary[String, HyAssetNode.AuxData] = {}) -> Array[HyAssetNode]:
    var new_root_an: HyAssetNode = get_duplicate_asset_node(tree_root)
    if register:
        register_duplicate_asset_node(new_root_an, tree_root.an_node_id)
    else:
        out_aux[new_root_an.an_node_id] = asset_node_aux_data[tree_root.an_node_id].duplicate(false)
    var all_new_ans: Array[HyAssetNode] = []
    _duplicate_filtered_an_tree_recurse(new_root_an, asset_node_set, register, all_new_ans, out_aux)
    return all_new_ans

func _duplicate_filtered_an_tree_recurse(current_an: HyAssetNode, asset_node_set: Array[HyAssetNode], register: bool, all_new_ans: Array[HyAssetNode], out_aux: Dictionary[String, HyAssetNode.AuxData]) -> void:
    all_new_ans.append(current_an)
    for conn_name in current_an.connection_list:
        for connected_an in current_an.get_all_connected_nodes(conn_name):
            if asset_node_set.size() > 0 and not connected_an in asset_node_set:
                continue
            var new_an: HyAssetNode = get_duplicate_asset_node(connected_an)
            current_an.append_node_to_connection(conn_name, new_an)
            if register:
                register_duplicate_asset_node(new_an, connected_an.an_node_id, current_an.an_node_id)
            else:
                out_aux[new_an.an_node_id] = asset_node_aux_data[connected_an.an_node_id].duplicate_with_parent(current_an.an_node_id)
            _duplicate_filtered_an_tree_recurse(new_an, asset_node_set, register, all_new_ans, out_aux)

func get_duplicate_asset_node(asset_node: HyAssetNode) -> HyAssetNode:
    var new_id: = CHANE_HyAssetNodeSerializer.reroll_an_id(asset_node.an_node_id)
    var new_asset_node: = asset_node.get_shallow_copy(new_id)
    return new_asset_node

func create_single_duplicate_asset_node(asset_node: HyAssetNode) -> HyAssetNode:
    var new_an: HyAssetNode = get_duplicate_asset_node(asset_node)
    register_duplicate_asset_node(new_an, asset_node.an_node_id)
    return new_an

func get_an_roots_within_registered_set(asset_node_set: Array[HyAssetNode]) -> Array[HyAssetNode]:
    return get_an_roots_within_set(asset_node_set, asset_node_aux_data)

static func get_an_roots_within_set(asset_node_set: Variant, associated_aux: Dictionary[String, HyAssetNode.AuxData]) -> Array[HyAssetNode]:
    var root_ans: Array[HyAssetNode] = []
    var asset_nodes: Array = []
    if typeof(asset_node_set) == TYPE_ARRAY:
        asset_nodes = asset_node_set
    elif typeof(asset_node_set) == TYPE_DICTIONARY:
        asset_nodes = asset_node_set.values()
    else:
        push_error("Invalid asset node set type: %s" % [type_string(typeof(asset_node_set))])

    for asset_node in asset_nodes:
        var parent_an_id: = associated_aux[asset_node.an_node_id].output_to_node_id
        if not parent_an_id or associated_aux[parent_an_id] not in asset_node_set:
            root_ans.append(asset_node)
    return root_ans

func clear_loaded_graph() -> void:
    focused_graph.clear_graph()

    all_asset_nodes.clear()
    asset_node_aux_data.clear()
    floating_an_tree_roots.clear()
    root_asset_node = null
    raw_metadata.clear()
    is_loaded = false

func get_new_asset_node(asset_node_type: String, id_prefix: String = "") -> HyAssetNode:
    asset_node_type = SchemaManager.schema.normalize_asset_node_type(asset_node_type)
    if id_prefix == "":
        id_prefix = SchemaManager.schema.get_id_prefix_for_node_type(asset_node_type)

    var new_asset_node: = HyAssetNode.new()
    new_asset_node.an_node_id = CHANE_HyAssetNodeSerializer.get_unique_an_id(id_prefix)
    new_asset_node.an_type = asset_node_type
    initial_asset_node_setup(new_asset_node)
    register_asset_node(new_asset_node)
    #floating_tree_roots.append(new_asset_node)

    return new_asset_node

func initial_asset_node_setup(asset_node: HyAssetNode) -> void:
    var type_schema: = SchemaManager.schema.node_schema.get(asset_node.an_type, {}) as Dictionary
    if not type_schema:
        print_debug("Warning: Asset node type is unknown or empty")

    asset_node.default_title = SchemaManager.schema.get_node_type_default_name(asset_node.an_type)
    asset_node.title = asset_node.default_title
    
    var connections_schema: Dictionary = type_schema.get("connections", {})
    for conn_name in connections_schema.keys():
        asset_node.connection_list.append(conn_name)
        asset_node.connected_node_counts[conn_name] = 0
    
    var settings_schema: Dictionary = type_schema.get("settings", {})
    for setting_name in settings_schema.keys():
        asset_node.settings[setting_name] = settings_schema[setting_name].get("default_value", null)
    asset_node.shallow = false

func _shortcut_input(event: InputEvent) -> void:
    if Input.is_action_just_pressed_by_event("open_file_shortcut", event, true):
        accept_event()
        if popup_menu_root.is_menu_visible():
            popup_menu_root.close_all()
        FileDialogHandler.show_open_file_dialog()
    elif Input.is_action_just_pressed_by_event("save_file_shortcut", event, true):
        accept_event()
        if file_helper.has_saved_to_cur_file:
            file_helper.resave_current_file(get_serialized_for_save())
        else:
            if popup_menu_root.is_menu_visible():
                popup_menu_root.close_all()
            FileDialogHandler.show_save_file_dialog(file_helper.has_cur_file())
    elif Input.is_action_just_pressed_by_event("save_as_shortcut", event, true):
        accept_event()
        if popup_menu_root.is_menu_visible():
            popup_menu_root.close_all()
        FileDialogHandler.show_save_file_dialog(false)
    elif Input.is_action_just_pressed_by_event("new_file_shortcut", event, true):
        accept_event()
        popup_menu_root.show_new_file_type_chooser()

    if not popup_menu_root.is_menu_visible():
        if Input.is_action_just_pressed_by_event("graph_select_all_nodes", event, true):
            accept_event()
            focused_graph.select_all()
        elif Input.is_action_just_pressed_by_event("graph_deselect_all_nodes", event, true):
            accept_event()
            focused_graph.deselect_all()
        elif Input.is_action_just_pressed_by_event("cut_inclusive_shortcut", event, true):
            accept_event()
            focused_graph.cut_selected_nodes_inclusive()
        elif Input.is_action_just_pressed_by_event("delete_inclusive_shortcut", event, true):
            accept_event()
            focused_graph.delete_selected_nodes_inclusive()

func _unhandled_key_input(event: InputEvent) -> void:
    # These shortcuts have priority even when a non-exclusive popup is open
    # but they will not be triggered if another control has keyboard focus and accepts the event (e.g. if space is show_new_node_menu, typing a space into a LineEdit will not trigger it)
    if Input.is_action_just_pressed_by_event("show_new_node_menu", event, true):
        if not popup_menu_root.is_menu_visible():
            accept_event()
            if is_loaded:
                show_new_asset_node_menu()
            else:
                popup_menu_root.show_new_file_type_chooser()

    if Input.is_action_just_pressed_by_event("ui_redo", event, true):
        accept_event()
        if undo_manager.has_redo():
            prints("Redoing:", undo_manager.get_redo_action_name())
            undo_manager.redo()
        else:
            GlobalToaster.show_toast_message("Nothing to Redo")
    elif Input.is_action_just_pressed_by_event("ui_undo", event, true):
        accept_event()
        if undo_manager.has_undo():
            prints("Undoing:", undo_manager.get_undo_action_name())
            # undoing could mean that the previously cut nodes are now back in the graph, assume we need to treat the cut like a copy now
            #if copied_nodes and clipboard_was_from_cut:
                #clipboard_was_from_cut = false
            undo_manager.undo()
            #if not undo_manager.has_undo():
                #unedited = true
        else:
            GlobalToaster.show_toast_message("Nothing to Undo")

func show_new_asset_node_menu() -> void:
    focused_graph.clear_next_drop()
    popup_menu_root.show_new_gn_menu()

func show_new_node_menu_for_pos(at_pos_offset: Vector2, from_graph: CHANE_AssetNodeGraphEdit, in_group: GraphFrame = null) -> void:
    from_graph.clear_next_drop()
    # TODO: we should really be storing the dropped pos as a position offset since that wont change if scroll or zoom somewhow changes in the meantime
    from_graph.dropping_new_node_at = from_graph.position_offset_to_global_pos(at_pos_offset)
    from_graph.next_drop_has_position = true
    if in_group:
        from_graph.next_drop_is_in_group = in_group
    popup_menu_root.show_new_gn_menu()

func get_gn_main_asset_node(graph_node: CustomGraphNode) -> HyAssetNode:
    if not graph_node or not graph_node.get_meta("hy_asset_node_id", ""):
        return null
    return all_asset_nodes.get(graph_node.get_meta("hy_asset_node_id", ""), null)

func _get_splice_left_conn(old_conn_info: Dictionary, insert_gn: CustomGraphNode) -> Dictionary:
    return {
        "from_node": old_conn_info["from_node"],
        "from_port": old_conn_info["from_port"],
        "to_node": insert_gn.name,
        "to_port": 0,
    }

func _get_splice_right_conn(old_conn_info: Dictionary, insert_gn: CustomGraphNode, in_idx: int) -> Dictionary:
    return {
        "from_node": insert_gn.name,
        "from_port": in_idx,
        "to_node": old_conn_info["to_node"],
        "to_port": old_conn_info["to_port"],
    }

func splice_graph_node_into_connection(graph: CHANE_AssetNodeGraphEdit, insert_gn: CustomGraphNode, conn_info: Dictionary) -> void:
    undo_manager.start_undo_step("Splice Node into Connection")
    
    var value_type: String = graph.get_conn_info_value_type(conn_info)
    if value_type == "":
        push_warning("Splice: Value type of connection is not known")
    
    connect_graph_nodes([_get_splice_left_conn(conn_info, insert_gn)], graph)
    
    var insert_an: = get_gn_main_asset_node(insert_gn)
    if not insert_an:
        push_error("Splice: Insert asset node not found")
        return

    var insert_on_input_idx: = SchemaManager.schema.get_input_conn_value_types_list(insert_an.an_type).find(value_type)
    var should_connect: bool = value_type == "" or insert_on_input_idx >= 0
    
    if should_connect:
        insert_on_input_idx = maxi(0, insert_on_input_idx)
        connect_graph_nodes([_get_splice_right_conn(conn_info, insert_gn, insert_on_input_idx)], graph)
    
    undo_manager.commit_current_undo_step()
    

func connect_graph_nodes(conn_infos: Array[Dictionary], graph: CHANE_AssetNodeGraphEdit) -> void:
    if conn_infos.size() == 0:
        return
    var undo_step: = undo_manager.start_or_continue_undo_step("Connect Nodes")
    var graph_undo_step: = undo_step.get_undo_for_graph(graph)
    var is_new_step: = undo_manager.is_new_step
    if not is_new_step and undo_step.action_name == "Add New Node":
        undo_manager.rename_current_undo_step("Add New Node to Connection")
    
    # Add all the raw connections even if there are missing asset nodes
    graph_undo_step.add_graph_node_conn_infos(conn_infos)

    for conn_info in conn_infos:
        var from_gn: = get_graph_gn(graph, conn_info["from_node"])
        var from_an: = get_gn_main_asset_node(from_gn)
        var to_gn: = get_graph_gn(graph, conn_info["to_node"])
        var to_an: = get_gn_main_asset_node(to_gn)
        
        # if outputting asset node found, only allow one output connection
        if to_an:
            disconnect_graph_nodes(graph.raw_out_connections(to_gn), graph)

        if not from_an or not to_an:
            push_warning("From or to asset node not found")
            print_debug("Warning: From or to asset node not found")
            continue

        var from_conn_name: String = SchemaManager.schema.get_input_conn_name_for_idx(from_an.an_type, conn_info["from_port"])
        var from_is_multi: bool = SchemaManager.schema.get_input_conn_is_multi(from_an.an_type, from_conn_name, true)
        # If asset nodes found and not a multi connection, only allow one input connection
        if not from_is_multi:
            var in_port_connections: = graph.raw_in_port_connections(from_gn, conn_info["from_port"])
            disconnect_graph_nodes(in_port_connections, graph)
        
        # Add the asset node connection to the undo step
        undo_step.add_asset_node_connection(from_an, from_conn_name, to_an)
    
    if is_new_step:
        undo_manager.commit_current_undo_step()

func disconnect_graph_nodes(conn_infos: Array[Dictionary], graph: CHANE_AssetNodeGraphEdit) -> void:
    if conn_infos.size() == 0:
        return
    var undo_step: = undo_manager.start_or_continue_undo_step("Disconnect Nodes")
    var graph_undo_step: = undo_step.get_undo_for_graph(graph)
    var is_new_step: = undo_manager.is_new_step
    
    # Remove all the raw connections even if there are missing asset nodes
    graph_undo_step.remove_graph_node_conn_infos(conn_infos)

    for conn_info in conn_infos:
        var from_an: = get_gn_main_asset_node(get_graph_gn(graph, conn_info["from_node"]))
        var to_an: = get_gn_main_asset_node(get_graph_gn(graph, conn_info["to_node"]))
        if not from_an or not to_an:
            push_warning("From or to asset node not found")
            print_debug("From or to asset node not found")
            continue
        
        var from_conn_name: String = SchemaManager.schema.get_input_conn_name_for_idx(from_an.an_type, conn_info["from_port"])
        undo_step.remove_asset_node_connection(from_an, from_conn_name, to_an)
    
    if is_new_step:
        undo_manager.commit_current_undo_step()

func _connect_asset_node_to(connecting_to_an_id: String, connecting_an_id: String, connection_name: String) -> void:
    var connecting_to_an: = all_asset_nodes[connecting_to_an_id]
    var connecting_an: = all_asset_nodes[connecting_an_id]
    connecting_to_an.append_node_to_connection(connection_name, connecting_an)
    var connection_aux: = asset_node_aux_data[connecting_an_id]
    connection_aux.output_to_node_id = connecting_to_an_id

func _disconnect_asset_node_from(disconnecting_from_an_id: String, disconnecting_an_id: String, connection_name: String) -> void:
    var disconnecting_from_an: = all_asset_nodes[disconnecting_from_an_id]
    var disconnecting_an: = all_asset_nodes[disconnecting_an_id]
    disconnecting_from_an.remove_node_from_connection(connection_name, disconnecting_an)
    var connection_aux: = asset_node_aux_data[disconnecting_an_id]
    connection_aux.output_to_node_id = ""

func _find_and_disconnect_asset_node_from(disconnecting_from_an: HyAssetNode, disconnecting_an: HyAssetNode) -> void:
    for conn_name in disconnecting_from_an.connection_list:
        var at_idx: = disconnecting_from_an.get_all_connected_nodes(conn_name).find(disconnecting_an)
        if at_idx >= 0:
            disconnecting_from_an.remove_node_from_connection_at(conn_name, at_idx)
            return

func _disconnect_all_asset_nodes_from_connection(disconnecting_from_an: HyAssetNode, connection_name: String) -> void:
    if connection_name not in disconnecting_from_an.connection_list:
        print_debug("Connection name %s not found in connection list" % connection_name)
        return
    for disconnected_an in disconnecting_from_an.get_all_connected_nodes(connection_name):
        var discon_id: = disconnected_an.an_node_id
        asset_node_aux_data[discon_id].output_to_node_id = ""
    disconnecting_from_an.clear_connection(connection_name)

func _disconnect_all_asset_nodes_from(disconnecting_from_an: HyAssetNode) -> void:
    for conn_name in disconnecting_from_an.connection_list:
        _disconnect_all_asset_nodes_from_connection(disconnecting_from_an, conn_name)

func _disconnect_all_asset_nodes_from_an_list(asset_nodes: Array[HyAssetNode]) -> void:
    for asset_node in asset_nodes:
        _disconnect_all_asset_nodes_from(asset_node)

func _disconnect_all_external_parent_asset_nodes_from_an_list(asset_nodes: Array[HyAssetNode]) -> void:
    for asset_node in asset_nodes:
        var parent_an: = get_parent_an(asset_node)
        if parent_an and parent_an not in asset_nodes:
            _find_and_disconnect_asset_node_from(parent_an, asset_node)

func get_graph_gn(graph: CHANE_AssetNodeGraphEdit, gn_name: String) -> CustomGraphNode:
    return graph.get_node(NodePath(gn_name)) as CustomGraphNode

func get_parent_an(asset_node: HyAssetNode) -> HyAssetNode:
    var parent_an_id: = get_parent_an_id(asset_node.an_node_id)
    if not parent_an_id or not all_asset_nodes.has(parent_an_id):
        return null
    return all_asset_nodes[parent_an_id]

func get_parent_an_id(asset_node_id: String) -> String:
    if not asset_node_aux_data.has(asset_node_id):
        print_debug("Asset node %s not found in aux data" % asset_node_id)
    return asset_node_aux_data[asset_node_id].output_to_node_id

func get_all_groups() -> Array[GraphFrame]:
    var all_groups: Array[GraphFrame] = []
    for graph in graphs:
        all_groups.append_array(graph.get_all_groups())
    return all_groups

func gn_is_special(graph_node: CustomGraphNode) -> bool:
    return graph_node.get_meta("is_special_gn", false)

func make_new_graph_node_for_an(asset_node: HyAssetNode, at_pos_offset: Vector2, centered: bool = false, aux_data_dict: Dictionary[String, HyAssetNode.AuxData] = {}) -> CustomGraphNode:
    if not aux_data_dict:
        aux_data_dict = asset_node_aux_data
    aux_data_dict[asset_node.an_node_id].position = at_pos_offset
    var new_gn: CustomGraphNode = graph_node_factory.make_new_graph_node_for_asset_node(asset_node, true, at_pos_offset, centered)
    return new_gn

func make_and_add_graph_node(in_graph: CHANE_AssetNodeGraphEdit, asset_node: HyAssetNode, at_pos_offset: Vector2, centered: bool = false, snap_now: bool = false) -> CustomGraphNode:
    var new_gn: CustomGraphNode = make_new_graph_node_for_an(asset_node, at_pos_offset, centered)
    in_graph.add_graph_node_child(new_gn, snap_now)
    return new_gn

func get_gn_own_asset_nodes(graph_node: CustomGraphNode) -> Array[HyAssetNode]:
    if gn_is_special(graph_node):
        return graph_node.get_own_asset_nodes()
    else:
        return [get_gn_main_asset_node(graph_node)]
    
func add_graph_nodes_for_new_asset_node_trees(graph: CHANE_AssetNodeGraphEdit, tree_roots: Array[HyAssetNode], offset_pos: Vector2 = Vector2.ZERO) -> Array[GraphElement]:
    if graph.snapping_enabled:
        offset_pos = offset_pos.snapped(Vector2.ONE * graph.snapping_distance)
    
    prints("Adding graph nodes to graph %s" % graph.get_path())

    var graph_undo_step: = undo_manager.start_or_continue_graph_undo_step("[Add] Nodes", graph)
    var is_new_step: = undo_manager.is_new_step
    
    var all_new_ges: Array[GraphElement] = []
    var all_new_connections: Array[Dictionary] = []
    for tree_root_node in tree_roots:
        prints("Adding graph nodes for new asset node tree %s" % tree_root_node.an_node_id)
        var new_ans_to_gns: = new_graph_nodes_for_tree(tree_root_node, offset_pos)
        prints("new ans to gns count: %s" % new_ans_to_gns.size())
        all_new_ges.append_array(new_ans_to_gns.values())

        all_new_connections.append_array(get_new_gn_connections(new_ans_to_gns[tree_root_node], new_ans_to_gns))
    
    prints("all new ges count: %s" % all_new_ges.size())
    graph_undo_step.add_new_graph_elements(all_new_ges, all_new_connections, [])
    if is_new_step:
        undo_manager.commit_current_undo_step()
    return all_new_ges
    
func get_new_gn_connections(cur_gn: CustomGraphNode, ans_to_gns: Dictionary) -> Array[Dictionary]:
    var connection_infos: Array[Dictionary] = []
    _get_new_gn_conn_recurse(cur_gn, ans_to_gns, connection_infos)
    return connection_infos

func _get_new_gn_conn_recurse(cur_gn: CustomGraphNode, ans_to_gns: Dictionary, connection_infos: Array[Dictionary]) -> void:
    var cur_an: = get_gn_main_asset_node(cur_gn)
    var excluded_conn_names: Array[String] = cur_gn.get_excluded_connection_names()
    var current_connection_names: Array[String] = cur_an.connection_list.filter(func(conn_name): return not conn_name in excluded_conn_names)
    for conn_idx in current_connection_names.size():
        var conn_name: = current_connection_names[conn_idx]
        var connected_ans: = cur_an.get_all_connected_nodes(conn_name)
        for connected_an in connected_ans:
            var connected_gn: = ans_to_gns.get(connected_an, null) as CustomGraphNode
            if not connected_gn:
                continue
            connection_infos.append({
                "from_node": cur_gn.name,
                "from_port": conn_idx,
                "to_node": connected_gn.name,
                "to_port": 0,
            })
            _get_new_gn_conn_recurse(connected_gn, ans_to_gns, connection_infos)

func new_graph_nodes_for_tree(tree_root_node: HyAssetNode, offset_pos: Vector2 = Vector2.ZERO, aux_data_dict: Dictionary[String, HyAssetNode.AuxData] = {}) -> Dictionary[HyAssetNode, CustomGraphNode]:
    if not aux_data_dict:
        aux_data_dict = asset_node_aux_data
    var new_gns_by_an: Dictionary[HyAssetNode, CustomGraphNode] = {}
    _recursive_new_graph_nodes(tree_root_node, offset_pos, new_gns_by_an, aux_data_dict)
    return new_gns_by_an

func _recursive_new_graph_nodes(at_asset_node: HyAssetNode, offset_pos: Vector2, new_gns_by_an: Dictionary[HyAssetNode, CustomGraphNode], aux_data_dict: Dictionary[String, HyAssetNode.AuxData]) -> void:
    var aux: = aux_data_dict[at_asset_node.an_node_id]
    var this_gn: = make_new_graph_node_for_an(at_asset_node, aux.position + offset_pos, false, aux_data_dict)
    new_gns_by_an[at_asset_node] = this_gn

    var modified_connections: = get_gn_modified_connections(this_gn, at_asset_node)
    for conn_name in modified_connections:
        for connected_asset_node in modified_connections[conn_name]:
            _recursive_new_graph_nodes(connected_asset_node, offset_pos, new_gns_by_an, aux_data_dict)

func get_gn_modified_connected_ans_for_connection(the_gn: CustomGraphNode, the_an: HyAssetNode, conn_name: String) -> Array[HyAssetNode]:
    if gn_is_special(the_gn):
        return the_gn.get_all_nodes_on_connection(conn_name)
    else:
        return the_an.get_all_connected_nodes(conn_name)

func get_gn_modified_connections(the_gn: CustomGraphNode, the_an: HyAssetNode) -> Dictionary[String, Array]:
    if gn_is_special(the_gn):
        return the_gn.get_all_connections()
    else:
        var mod_connections: Dictionary[String, Array] = {}
        for conn_name in the_an.connection_list:
            mod_connections[conn_name] = the_an.get_all_connected_nodes(conn_name)
        return mod_connections

func get_duplicate_ge_name(old_ge_name: String) -> String:
    var base_name: = old_ge_name.split("--")[0]
    return graph_node_factory.new_graph_node_name(base_name)

func get_all_asset_nodes() -> Array[HyAssetNode]:
    return Array(all_asset_nodes.values(), TYPE_OBJECT, &"HyAssetNode", null)

func is_workspace_id_compatible(workspace_id: String) -> bool:
    if not workspace_id:
        # Allow trying with unknown workspaces
        return true

    var possible_workspaces: = SchemaManager.schema.workspace_root_output_types.keys()
    possible_workspaces.append_array(SchemaManager.schema.workspace_no_output_types.keys())
    
    return possible_workspaces.has(workspace_id)

func get_gn_included_asset_nodes(gn: CustomGraphNode) -> Array[HyAssetNode]:
    if gn_is_special(gn):
        return gn.get_own_asset_nodes()
    else:
        return [get_gn_main_asset_node(gn)]

func get_included_asset_nodes_for_ges(ges: Array[GraphElement]) -> Array[HyAssetNode]:
    var included_asset_nodes: Array[HyAssetNode] = []
    for ge in ges:
        if ge is CustomGraphNode:
            included_asset_nodes.append_array(get_gn_included_asset_nodes(ge))
    return included_asset_nodes

func remove_graph_elements_from_graphs(ges: Array[GraphElement]) -> void:
    for ge in ges:
        ge.get_parent().remove_child(ge)

func get_new_group_name() -> String:
    return graph_node_factory.new_graph_node_name("Group")

func make_duplicate_group(group: GraphFrame) -> GraphFrame:
    var serialized_group: = serializer.serialize_group(group)
    var copy: = serializer.deserialize_group(serialized_group, get_new_group_name)
    copy.name = graph_node_factory.new_graph_node_name("Group")
    return copy

func get_duplicate_group_set(groups: Array) -> Array[GraphFrame]:
    var serialized_groups: = serializer.serialize_groups(groups)
    var groups_copy: = serializer.deserialize_groups(serialized_groups, get_new_group_name)
    for group in groups_copy:
        group.name = graph_node_factory.new_graph_node_name("Group")
    return groups_copy
