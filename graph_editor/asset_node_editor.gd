class_name CHANE_AssetNodeEditor
extends Control

const AssetNodeFileHelper = preload("./asset_node_file_helper.gd")

const SpecialGNFactory = preload("res://custom_graph_nodes/special_gn_factory.gd")
const GraphNodeFactory = preload("res://custom_graph_nodes/graph_node_factory.gd")

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

@onready var special_gn_factory: SpecialGNFactory = SpecialGNFactory.new()
@onready var graph_node_factory: GraphNodeFactory = GraphNodeFactory.new()

var undo_manager: UndoRedo = UndoRedo.new()

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
    
    add_child(special_gn_factory, true)
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
        dropping_in_graph.add_connection(connection_info)

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
        var owned_an_positions: Dictionary[String, Vector2] = graph_node.get_owned_an_positions()
        for an_id in owned_an_positions.keys():
            asset_node_aux_data[an_id].position = owned_an_positions[an_id]

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
    focused_graph.make_and_position_graph_nodes_for_trees(an_roots, true)
    focused_graph.make_json_groups(graph_result.editor_metadata.get("$Groups", []))
    
    focused_graph.scroll_to_pos_offset(asset_node_aux_data[root_asset_node.an_node_id].position)

func _register_asset_nodes_from_graph_result(graph_result: CHANE_HyAssetNodeSerializer.EntireGraphParseResult) -> void:
    all_asset_nodes = graph_result.all_nodes
    asset_node_aux_data = graph_result.asset_node_aux_data

func register_asset_node(asset_node: HyAssetNode, aux_data: HyAssetNode.AuxData = null) -> void:
    assert(asset_node.an_node_id, "Cannot register an asset node with no ID")
    if OS.has_feature("debug") and all_asset_nodes.has(asset_node.an_node_id):
        print_debug("Re-registering asset node with existing ID %s" % asset_node.an_node_id)
    all_asset_nodes[asset_node.an_node_id] = asset_node
    if aux_data:
        asset_node_aux_data[asset_node.an_node_id] = aux_data
    else:
        asset_node_aux_data[asset_node.an_node_id] = HyAssetNode.AuxData.new()

func register_asset_node_at(asset_node: HyAssetNode, node_pos: Vector2) -> void:
    var aux_data: HyAssetNode.AuxData = HyAssetNode.AuxData.new()
    aux_data.position = node_pos
    register_asset_node(asset_node, aux_data)

func remove_asset_node_id(asset_node_id: String) -> void:
    all_asset_nodes.erase(asset_node_id)
    asset_node_aux_data.erase(asset_node_id)

func remove_asset_node(asset_node: HyAssetNode) -> void:
    assert(asset_node.an_node_id, "Cannot remove an asset node with no ID")
    remove_asset_node_id(asset_node.an_node_id)

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
        if not is_loaded:
            popup_menu_root.show_new_file_type_chooser()
        elif not popup_menu_root.is_menu_visible():
            show_new_asset_node_menu()
            get_viewport().set_input_as_handled()

    if Input.is_action_just_pressed_by_event("ui_redo", event, true):
        if undo_manager.has_redo():
            print("Redoing")
            undo_manager.redo()
        else:
            GlobalToaster.show_toast_message("Nothing to Redo")
    elif Input.is_action_just_pressed_by_event("ui_undo", event, true):
        if undo_manager.has_undo():
            prints("Undoing", undo_manager.get_current_action_name())
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
    if not graph_node.get_meta("hy_asset_node_id", ""):
        return null
    return all_asset_nodes.get(graph_node.get_meta("hy_asset_node_id", ""), null)

func connect_graph_nodes(conn_info: Dictionary, graph: CHANE_AssetNodeGraphEdit) -> void:
    var from_gn: = graph.get_node(NodePath(conn_info["from_node"])) as CustomGraphNode
    var to_gn: = graph.get_node(NodePath(conn_info["to_node"])) as CustomGraphNode

    # disconnect any existing outputs (only allowing one output connection)
    var existing_output_conn_infos: = Util.out_connections(graph.raw_connections(to_gn), to_gn.name)
    for out_info in existing_output_conn_infos:
        remove_connection(out_info, graph)
    
    #if not from_an or not to_an:
        #print_debug("Warning: From or to asset node not found")
        #connect_node(from_gn_name, from_port, to_gn_name, to_port)
        #return

    #if from_an.an_type not in SchemaManager.schema.node_schema:
        #print_debug("Warning: From node type %s not found in schema" % from_an.an_type)
        #var conn_name: String = from_an.connection_list[from_port]
        #from_an.append_node_to_connection(conn_name, to_an)
    #else:
        #var conn_name: String = from_an.connection_list[from_port]
        #var connect_is_multi: bool = SchemaManager.schema.node_schema[from_an.an_type]["connections"][conn_name].get("multi", false)
        #sort_all_an_connections()
        #if connect_is_multi or from_an.num_connected_asset_nodes(conn_name) == 0:
            #from_an.append_node_to_connection(conn_name, to_an)
        #else:
            #var prev_connected_node: HyAssetNode = from_an.get_connected_node(conn_name, 0)
            #if prev_connected_node and editor.gn_lookup.has(prev_connected_node.an_node_id):
                #_remove_connection(from_gn_name, from_port, editor.gn_lookup[prev_connected_node.an_node_id].name, 0)
            #from_an.append_node_to_connection(conn_name, to_an)
    
    #if to_an in floating_tree_roots:
        #floating_tree_roots.erase(to_an)

func remove_connection(conn_info: Dictionary, graph: CHANE_AssetNodeGraphEdit, with_undo: bool = true) -> void:
    graph.remove_connection(conn_info, with_undo)

func get_all_groups() -> Array[GraphFrame]:
    var all_groups: Array[GraphFrame] = []
    for graph in graphs:
        all_groups.append_array(graph.get_all_groups())
    return all_groups

func gn_is_special(graph_node: CustomGraphNode) -> bool:
    return graph_node.get_meta("is_special_gn", false)

func make_new_graph_node_for_an(asset_node: HyAssetNode, at_pos_offset: Vector2, centered: bool = false) -> CustomGraphNode:
    asset_node_aux_data[asset_node.an_node_id].position = at_pos_offset
    var new_gn: CustomGraphNode = graph_node_factory.make_new_graph_node_for_asset_node(asset_node, true, at_pos_offset, centered)
    return new_gn

func make_and_add_graph_node(in_graph: CHANE_AssetNodeGraphEdit, asset_node: HyAssetNode, at_pos_offset: Vector2, centered: bool = false, snap_now: bool = false) -> CustomGraphNode:
    var new_gn: CustomGraphNode = make_new_graph_node_for_an(asset_node, at_pos_offset, centered)
    in_graph.add_graph_node_child(new_gn, snap_now)
    return new_gn