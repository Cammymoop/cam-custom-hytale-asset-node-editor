class_name CHANE_AssetNodeEditor
extends Control

const AssetNodeFileHelper = preload("./asset_node_file_helper.gd")

const DEFAULT_HY_WORKSPACE_ID: String = "HytaleGenerator - Biome"
var hy_workspace_id: String = ""

var graphs: Array[CHANE_AssetNodeGraphEdit] = []
var focused_graph: CHANE_AssetNodeGraphEdit = null

var serializer: CHANE_HyAssetNodeSerializer

@export var popup_menu_root: PopupMenuRoot

@export var save_formatted_json: = true

@export var use_json_positions: = true
@export var json_positions_scale: Vector2 = Vector2(0.6, 0.6)

var root_asset_node: HyAssetNode = null
var root_graph_node: CustomGraphNode = null
var all_asset_nodes: Dictionary[String, HyAssetNode] = {}
var asset_node_aux_data: Dictionary[String, HyAssetNode.AuxData] = {}

var floating_an_tree_roots: Array[String] = []

var gn_lookup: Dictionary[String, CustomGraphNode] = {}

var raw_metadata: Dictionary = {}

var is_loaded: = false

var file_helper: AssetNodeFileHelper
func _ready() -> void:
    file_helper = AssetNodeFileHelper.new()
    file_helper.name = "FileHelper"
    add_child(file_helper, true)

    get_window().files_dropped.connect(on_files_dropped)

    FileDialogHandler.requested_open_file.connect(_on_requested_open_file)
    FileDialogHandler.requested_save_file.connect(_on_requested_save_file)

    for child in get_children():
        if child is CHANE_AssetNodeGraphEdit:
            child.set_editor(self)
            graphs.append(child)
    if graphs.size() > 0:
        focused_graph = graphs[0]

    await get_tree().process_frame
    if not is_loaded:
        popup_menu_root.show_new_file_type_chooser()

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
    if not file_helper.has_unsaved_changes or all_asset_nodes.size() <= 1:
        _make_new_file_with_workspace_id(workspace_id)
    else:
        var prompt_text: = "Do you want to save the current file before creating a new file?"
        var has_cur: = file_helper.cur_file_name != ""
        popup_menu_root.show_save_confirm(prompt_text, has_cur, _make_new_file_with_workspace_id.bind(workspace_id))

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
    var new_gn: CustomGraphNode = focused_graph.make_and_add_graph_node(new_root_node, screen_center_pos, true, true)
    focused_graph.scroll_to_graph_element(new_gn)
    #gn_lookup[new_root_node.an_node_id] = new_gn
    is_loaded = true
    file_helper.editing_new_file()

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
    if not file_helper.has_unsaved_changes or all_asset_nodes.size() < 2:
        file_helper.load_json_file(json_file_path, on_got_loaded_data)
    else:
        var prompt_text: = "Do you want to save the current file before loading '%s'?" % json_file_path
        var has_cur: = file_helper.cur_file_name != ""
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
            FileDialogHandler.show_save_file_dialog(file_helper.cur_file_name != "")
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

func get_gn_main_asset_node(graph_node: CustomGraphNode) -> HyAssetNode:
    if not graph_node.get_meta("hy_asset_node_id", ""):
        return null
    return all_asset_nodes.get(graph_node.get_meta("hy_asset_node_id", ""), null)

func connect_graph_nodes(from_gn: CustomGraphNode, from_port: int, to_gn: CustomGraphNode, to_port: int, graph_edit: CHANE_AssetNodeGraphEdit) -> void:
    pass
    # disconnect any existing outputs (only allowing one output connection)
    #var existing_output_conn_infos: = raw_out_connections(to_gn)
    #for existing_output in existing_output_conn_infos:
        #remove_connection(existing_output)
    
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