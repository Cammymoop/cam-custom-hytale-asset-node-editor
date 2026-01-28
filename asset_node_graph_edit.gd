extends GraphEdit
class_name AssetNodeGraphEdit

@export var save_formatted_json: = true
@export_file_path("*.json") var test_json_file: String = ""

@export var schema: AssetNodesSchema

var parsed_json_data: Dictionary = {}
var loaded: = false

var hy_workspace_id: String = ""

var all_asset_nodes: Array[HyAssetNode] = []
var all_asset_node_ids: Array[String] = []
var floating_tree_roots: Array[HyAssetNode] = []
var root_node: HyAssetNode = null

@onready var special_gn_factory: SpecialGNFactory = $SpecialGNFactory

var asset_node_meta: Dictionary[String, Dictionary] = {}

@export var no_left_types: Array[String] = [
    "BiomeRoot",
]


var gn_lookup: Dictionary[String, GraphNode] = {}
var an_lookup: Dictionary[String, HyAssetNode] = {}

var more_type_names: Array[String] = [
    "Single",
    "Multi",
]
var type_id_lookup: Dictionary[String, int] = {}

@export var use_json_positions: = true
@export var json_positions_scale: Vector2 = Vector2(0.5, 0.5)
var relative_root_position: Vector2 = Vector2(0, 0)

var temp_pos: Vector2 = Vector2(-2200, 600)
@onready var temp_origin: Vector2 = temp_pos
var temp_x_sep: = 200
var temp_y_sep: = 260
var temp_x_elements: = 10 

@export var gn_min_width: = 140
@export var text_field_def_characters: = 12

@export var verbose: = false

@onready var cur_zoom_level: = zoom
@onready var grid_logical_enabled: = show_grid

var copied_nodes: Array[GraphNode] = []

var special_handling_types: Array[String] = [
    "ManualCurve",
]

var undo_manager: UndoRedo = UndoRedo.new()
var multi_connection_change: bool = false
var cur_added_connections: Array[Dictionary] = []
var cur_removed_connections: Array[Dictionary] = []
var moved_nodes_positions: Dictionary[GraphNode, Vector2] = {}

func _ready() -> void:
    #add_valid_left_disconnect_type(1)
    begin_node_move.connect(on_begin_node_move)
    end_node_move.connect(on_end_node_move)
    
    connection_request.connect(_connection_request)
    disconnection_request.connect(_disconnection_request)

    duplicate_nodes_request.connect(_duplicate_request)
    copy_nodes_request.connect(_copy_nodes)
    cut_nodes_request.connect(_cut_nodes)
    paste_nodes_request.connect(_paste_request)
    delete_nodes_request.connect(_delete_request)
    
    var menu_hbox: = get_menu_hbox()
    var grid_toggle_btn: = menu_hbox.get_child(4) as Button
    grid_toggle_btn.toggled.connect(on_grid_toggled.bind(grid_toggle_btn))
    
    for val_type_name in schema.value_types:
        var val_type_idx: = type_names.size()
        type_names[val_type_idx] = val_type_name
        add_valid_connection_type(val_type_idx, val_type_idx)
        #add_valid_left_disconnect_type(val_type_idx)

    for extra_type_name in more_type_names:
        var type_idx: = type_names.size()
        type_names[type_idx] = extra_type_name
        #add_valid_left_disconnect_type(type_idx)

    for type_id in type_names.keys():
        type_id_lookup[type_names[type_id]] = type_id

    #cut_nodes_request.connect(_cut_nodes)
    if test_json_file:
        load_json_file(test_json_file)
    else:
        print("No test JSON file specified")

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("ui_undo"):
        print("Undo pressed")
        if undo_manager.has_undo():
            print("Undoing")
            undo_manager.undo()
    if Input.is_action_just_pressed("ui_redo"):
        print("Redo pressed")
        if undo_manager.has_redo():
            undo_manager.redo()
    
    if cur_zoom_level != zoom:
        on_zoom_changed()
    
func _input(event: InputEvent) -> void:
    if event is InputEventMouse:
        handle_mouse_event(event as InputEventMouse)

func _connection_request(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int) -> void:
    prints("Connection request:", from_gn_name, from_port, to_gn_name)
    _add_connection(from_gn_name, from_port, to_gn_name, to_port)

func add_multiple_connections(conns_to_add: Array[Dictionary], with_undo: bool = true) -> void:
    prints("adding multiple connections (%d) undoable: %s" % [conns_to_add.size(), with_undo])
    var self_multi: = not multi_connection_change
    multi_connection_change = true
    for conn_to_add in conns_to_add:
        add_connection(conn_to_add, with_undo)

    if self_multi:
        if with_undo:
            create_undo_connection_change_step()
        multi_connection_change = false

func add_connection(connection_info: Dictionary, with_undo: bool = true) -> void:
    _add_connection(connection_info["from_node"], connection_info["from_port"], connection_info["to_node"], connection_info["to_port"], with_undo)

func _add_connection(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int, with_undo: bool = true) -> void:
    prints("Adding connection:", from_gn_name, from_port, to_gn_name, "undoable:", with_undo)
    var from_gn: GraphNode = get_node(NodePath(from_gn_name))
    var to_gn: GraphNode = get_node(NodePath(to_gn_name))
    var from_an: HyAssetNode = an_lookup.get(from_gn.get_meta("hy_asset_node_id", ""))
    var to_an: HyAssetNode = an_lookup.get(to_gn.get_meta("hy_asset_node_id", ""))
    if from_an.an_type not in schema.node_schema:
        print_debug("Warning: From node type %s not found in schema" % from_an.an_type)
        connect_node(from_gn_name, from_port, to_gn_name, to_port)
        return

    var conn_name: String = from_an.connection_list[from_port]
    var connect_is_multi: bool = schema.node_schema[from_an.an_type]["connections"][conn_name].get("multi", false)
    if connect_is_multi or from_an.num_connected_asset_nodes(conn_name) == 0:
        from_an.append_node_to_connection(conn_name, to_an)
    else:
        var prev_connected_node: HyAssetNode = from_an.get_connected_node(conn_name, 0)
        if prev_connected_node and gn_lookup.has(prev_connected_node.an_node_id):
            _remove_connection(from_gn_name, from_port, prev_connected_node.an_node_id, 0)
        from_an.set_connection(conn_name, 0, to_an)
    
    if to_an in floating_tree_roots:
        floating_tree_roots.erase(to_an)

    if with_undo:
        cur_added_connections.append({
            "from_node": from_gn_name,
            "from_port": from_port,
            "to_node": to_gn_name,
            "to_port": to_port,
        })
    connect_node(from_gn_name, from_port, to_gn_name, to_port)
    if with_undo and not multi_connection_change:
        print("with undo and not multi_connection_change, now creating undo connection change step")
        create_undo_connection_change_step()

func _disconnection_request(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int) -> void:
    prints("Disconnection request:", from_gn_name, from_port, to_gn_name)
    _remove_connection(from_gn_name, from_port, to_gn_name, to_port)

func remove_multiple_connections(conns_to_remove: Array[Dictionary], with_undo: bool = true) -> void:
    var self_multi: = not multi_connection_change
    multi_connection_change = true
    for conn_to_remove in conns_to_remove:
        remove_connection(conn_to_remove, with_undo)

    if self_multi:
        if with_undo:
            create_undo_connection_change_step()
        multi_connection_change = false

func remove_connection(connection_info: Dictionary, with_undo: bool = true) -> void:
    _remove_connection(connection_info["from_node"], connection_info["from_port"], connection_info["to_node"], connection_info["to_port"], with_undo)

func _remove_connection(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int, with_undo: bool = true) -> void:
    prints("Removing connection:", from_gn_name, from_port, to_gn_name)
    disconnect_node(from_gn_name, from_port, to_gn_name, to_port)

    var from_gn: GraphNode = get_node(NodePath(from_gn_name))
    var to_gn: GraphNode = get_node(NodePath(to_gn_name))
    var from_an: HyAssetNode = an_lookup.get(from_gn.get_meta("hy_asset_node_id", ""))
    var from_connection_name: String = from_an.connection_list[from_port]
    var to_an: HyAssetNode = an_lookup.get(to_gn.get_meta("hy_asset_node_id", ""))
    from_an.remove_node_from_connection(from_connection_name, to_an)
    
    if with_undo:
        cur_removed_connections.append({
            "from_node": from_gn_name,
            "from_port": from_port,
            "to_node": to_gn_name,
            "to_port": to_port,
        })
    floating_tree_roots.append(to_an)
    if with_undo and not multi_connection_change:
        create_undo_connection_change_step()

func remove_asset_node(asset_node: HyAssetNode) -> void:
    all_asset_nodes.erase(asset_node)
    an_lookup.erase(asset_node.an_node_id)
    gn_lookup.erase(asset_node.an_node_id)
    asset_node.queue_free()

func _delete_request(delete_gn_names: Array[StringName]) -> void:
    for gn_name in delete_gn_names:
        var gn: GraphNode = get_node(NodePath(gn_name))
        if gn:
            if gn.get_meta("hy_asset_node_id", ""):
                var an_id: String = gn.get_meta("hy_asset_node_id")
                var asset_node: HyAssetNode = an_lookup.get(an_id, null)
                if asset_node:
                    asset_node.queue_free()
                an_lookup.erase(an_id)
                gn_lookup.erase(an_id)
            gn.queue_free()

func get_unique_id(id_prefix: String = "") -> String:
    return "%s-%s" % [id_prefix, Util.unique_id_string()]

func get_new_asset_node(asset_node_type: String, id_prefix: String = "") -> HyAssetNode:
    if id_prefix == "" and asset_node_type and asset_node_type != "Unknown":
        id_prefix = schema.get_id_prefix_for_node_type(asset_node_type)
    elif id_prefix == "":
        print_debug("New asset node: No ID prefix provided, and asset node type is unknown or empty")
        return null

    var new_asset_node: = HyAssetNode.new()
    new_asset_node.an_node_id = get_unique_id(id_prefix)
    new_asset_node.an_type = asset_node_type
    all_asset_nodes.append(new_asset_node)
    an_lookup[new_asset_node.an_node_id] = new_asset_node
    return new_asset_node

func get_selected_gns() -> Array[GraphNode]:
    var selected_gns: Array[GraphNode] = []
    for c in get_children():
        if c is GraphNode and c.selected:
            selected_gns.append(c)
    return selected_gns

func _duplicate_request() -> void:
    pass

func _cut_request() -> void:
    pass

func _cut_nodes() -> void:
    var selected_gns: Array[GraphNode] = get_selected_gns()
    copied_nodes = selected_gns
    for gn in selected_gns:
        remove_child(gn)

func _copy_request() -> void:
    pass

func _copy_nodes() -> void:
    copied_nodes = get_selected_gns()

func _paste_request() -> void:
    pass

func clear_graph() -> void:
    all_asset_nodes.clear()
    all_asset_node_ids.clear()
    floating_tree_roots.clear()
    root_node = null
    gn_lookup.clear()
    an_lookup.clear()
    asset_node_meta.clear()
    for child in get_children():
        if child is GraphNode:
            remove_child(child)
            child.queue_free()
    undo_manager.clear_history()

func create_graph_from_parsed_data() -> void:
    await get_tree().create_timer(0.1).timeout
    
    #print("Loaded asset nodes:")
    #print_asset_node_list()
    
    if use_json_positions:
        pass#relative_root_position = get_node_position_from_meta(root_node.an_node_id)
    
    make_graph_stuff()
    
    await get_tree().process_frame
    var root_gn: = gn_lookup[root_node.an_node_id]
    scroll_offset = root_gn.position_offset * zoom
    scroll_offset -= (get_viewport_rect().size / 2) 

func get_node_position_from_meta(node_id: String) -> Vector2:
    var node_meta: Dictionary = asset_node_meta.get(node_id, {}) as Dictionary
    var meta_pos: Dictionary = node_meta.get("$Position", {"$x": relative_root_position.x, "$y": relative_root_position.y - 560})
    return Vector2(meta_pos["$x"], meta_pos["$y"])
    
func print_asset_node_list() -> void:
    var more_than_ten: = all_asset_nodes.size() > 10
    for asset_node in all_asset_nodes.slice(0, 10):
        prints("Asset Node || '%s' (%s)" % [asset_node.an_name, asset_node.an_node_id])
    if more_than_ten:
        prints("... (Total: %d)" % all_asset_nodes.size())
    
func parse_asset_node_shallow(asset_node_data: Dictionary, output_value_type: String = "", known_node_type: String = "") -> HyAssetNode:
    if not asset_node_data:
        print_debug("Asset node data is empty")
        return null
    if not asset_node_data.has("$NodeId"):
        print_debug("Asset node data does not have a $NodeId, it is probably not an asset node")
        return null
    
    var asset_node = HyAssetNode.new()
    asset_node.an_node_id = asset_node_data["$NodeId"]
    
    if an_lookup.has(asset_node.an_node_id):
        print_debug("Warning: Asset node with ID %s already exists in lookup, overriding..." % asset_node.an_node_id)
    an_lookup[asset_node.an_node_id] = asset_node
    

    if known_node_type != "":
        asset_node.an_type = known_node_type
    elif output_value_type != "ROOT":
        asset_node.an_type = schema.resolve_asset_node_type(asset_node_data.get("Type", "NO_TYPE_KEY"), output_value_type, asset_node.an_node_id)
    
    var type_schema: = {}
    if asset_node.an_type and asset_node.an_type != "Unknown":
        type_schema = schema.node_schema[asset_node.an_type]

    asset_node.an_name = schema.get_node_type_default_name(asset_node.an_type)
    if asset_node_meta and asset_node_meta.has(asset_node.an_node_id) and asset_node_meta[asset_node.an_node_id].has("$Title"):
        asset_node.an_name = asset_node_meta[asset_node.an_node_id]["$Title"]
    asset_node.raw_tree_data = asset_node_data.duplicate(true)
    
    var connections_schema: Dictionary = type_schema.get("connections", {})
    for conn_name in connections_schema.keys():
        if connections_schema[conn_name].get("multi", false):
            asset_node.connections[conn_name] = []
        else:
            asset_node.connections[conn_name] = null
    
    var settings_schema: Dictionary = type_schema.get("settings", {})
    for setting_name in settings_schema.keys():
        asset_node.settings[setting_name] = settings_schema[setting_name].get("default_value", null)

    # fill out stuff in data even if it isn't in the schema
    for other_key in asset_node_data.keys():
        if other_key.begins_with("$") or HyAssetNode.special_keys.has(other_key):
            continue
        
        var connected_data = check_for_asset_nodes(asset_node_data[other_key])
        if connected_data != null:
            if verbose:
                var short_data: = str(connected_data).substr(0, 12) + "..."
                prints("Node '%s' (%s) Connection '%s' has connected nodes: %s" % [asset_node.an_name, asset_node.an_type, other_key, short_data])
            asset_node.connections[other_key] = connected_data
        else:
            if verbose:
                var short_data: = str(asset_node_data[other_key])
                short_data = short_data.substr(0, 50) + ("..." if short_data.length() > 50 else "")
                prints("Node '%s' (%s) Connection '%s' is just data: %s" % [asset_node.an_name, asset_node.an_type, other_key, short_data])
            asset_node.settings[other_key] = asset_node_data[other_key]
    
    return asset_node

func _inner_parse_asset_node_deep(asset_node_data: Dictionary, output_value_type: String = "", base_node_type: String = "") -> Dictionary:
    var parsed_node: = parse_asset_node_shallow(asset_node_data, output_value_type, base_node_type)
    var all_nodes: Array[HyAssetNode] = [parsed_node]
    for conn in parsed_node.connections.keys():
        if parsed_node.is_connection_empty(conn):
            continue
        
        var conn_nodes_data: = parsed_node.get_raw_connected_nodes(conn)
        for conn_node_idx in conn_nodes_data.size():
            var conn_value_type: = "Unknown"
            if parsed_node.an_type != "Unknown":
                conn_value_type = schema.node_schema[parsed_node.an_type]["connections"][conn]["value_type"]

            var sub_parse_result: = _inner_parse_asset_node_deep(conn_nodes_data[conn_node_idx], conn_value_type)
            all_nodes.append_array(sub_parse_result["all_nodes"])
            parsed_node.set_connection(conn, conn_node_idx, sub_parse_result["base"])
        parsed_node.set_connection_count(conn, conn_nodes_data.size())

    parsed_node.has_inner_asset_nodes = true
    
    return {"base": parsed_node, "all_nodes": all_nodes}

func parse_asset_node_deep(asset_node_data: Dictionary, output_value_type: String = "", base_node_type: String = "") -> Dictionary:
    var res: = _inner_parse_asset_node_deep(asset_node_data, output_value_type, base_node_type)
    return res

func parse_root_asset_node(base_node: Dictionary) -> void:
    hy_workspace_id = "NONE"
    var parsed_node_count: = 0
    if not base_node.has("$NodeEditorMetadata") or not base_node["$NodeEditorMetadata"] is Dictionary:
        print_debug("Root node does not have $NodeEditorMetadata")
    else:
        var meta_data: = base_node["$NodeEditorMetadata"] as Dictionary

        for node_id in meta_data.get("$Nodes", {}).keys():
            asset_node_meta[node_id] = meta_data["$Nodes"][node_id]

        for floating_tree in meta_data.get("$FloatingNodes", []):
            var floating_parse_result: = parse_asset_node_deep(floating_tree)
            floating_tree_roots.append(floating_parse_result["base"])
            parsed_node_count += floating_parse_result["all_nodes"].size()
            print("Floating tree parsed, %d nodes" % floating_parse_result["all_nodes"].size(), " (total: %d)" % parsed_node_count)
            all_asset_nodes.append_array(floating_parse_result["all_nodes"])
            for an in floating_parse_result["all_nodes"]:
                all_asset_node_ids.append(an.an_node_id)
        
        hy_workspace_id = meta_data.get("$WorkspaceID", "NONE")

    if hy_workspace_id == "NONE" and base_node.has("$WorkspaceID"):
        hy_workspace_id = base_node["$WorkspaceID"]

    var root_node_type: = "Unknown"
    if hy_workspace_id == "NONE":
        print_debug("No workspace ID found in root node or editor metadata")
    else:
        root_node_type = schema.resolve_asset_node_type(base_node.get("Type", "NO_TYPE_KEY"), "ROOT|%s" % hy_workspace_id, base_node.get("$NodeId", ""))
        print("Root node type: %s" % root_node_type)

    var parse_result: = parse_asset_node_deep(base_node, "", root_node_type)
    root_node = parse_result["base"]
    all_asset_nodes.append_array(parse_result["all_nodes"])
    parsed_node_count += parse_result["all_nodes"].size()
    print("Root node parsed, %d nodes" % parse_result["all_nodes"].size(), " (total: %d)" % parsed_node_count)
    for an in parse_result["all_nodes"]:
        all_asset_node_ids.append(an.an_node_id)
        
    
    loaded = true

func check_for_asset_nodes(val: Variant) -> Variant:
    if val is Dictionary:
        if val.is_empty() or val.has("$NodeId"):
            return val
    elif val is Array:
        if val.size() == 0 or val[0] is Dictionary and val[0].has("$NodeId"):
            return val
    return null


func make_graph_stuff() -> void:
    if not loaded or not root_node:
        print_debug("Make graph: Not loaded or no root node")
        return
    
    var all_root_nodes: Array[HyAssetNode] = [root_node]
    all_root_nodes.append_array(floating_tree_roots)
    
    var base_tree_pos: = Vector2(0, 100)
    for tree_root_node in all_root_nodes:
        var new_graph_nodes: Array[CustomGraphNode] = new_graph_nodes_for_tree(tree_root_node)
        for new_gn in new_graph_nodes:
            if not use_json_positions:
                new_gn.position_offset = Vector2(0, -500)
            add_child(new_gn, true)
            if new_gn.size.x < gn_min_width:
                new_gn.size.x = gn_min_width
        
        if use_json_positions:
            connect_children(new_graph_nodes[0])
        else:
            var last_y: int = move_and_connect_children(tree_root_node.an_node_id, base_tree_pos)
            base_tree_pos.y = last_y + 40
    
func connect_children(graph_node: CustomGraphNode) -> void:
    var connection_names: Array[String] = get_graph_connections_for(graph_node)
    for conn_idx in connection_names.size():
        var connected_graph_nodes: Array[GraphNode] = get_graph_connected_graph_nodes(graph_node, connection_names[conn_idx])
        for connected_gn in connected_graph_nodes:
            connect_node(graph_node.name, conn_idx, connected_gn.name, 0)
            connect_children(connected_gn)

func move_and_connect_children(asset_node_id: String, pos: Vector2) -> int:
    var graph_node: = gn_lookup[asset_node_id]
    var asset_node: = an_lookup[asset_node_id]
    graph_node.position_offset = pos

    var child_pos: = pos + (Vector2.RIGHT * (graph_node.size.x + 40))
    var connection_names: Array[String] = asset_node.connections.keys()

    for conn_idx in connection_names.size():
        var conn_name: = connection_names[conn_idx]
        for connected_node_idx in asset_node.num_connected_asset_nodes(conn_name):
            var conn_an: = asset_node.get_connected_node(conn_name, connected_node_idx)
            if not conn_an:
                continue
            var conn_gn: = gn_lookup[conn_an.an_node_id]
            if not conn_gn:
                print_debug("Warning: Graph Node for Asset Node %s not found" % conn_an.an_node_id)
                continue

            if conn_an.connections.size() > 0:
                child_pos.y = move_and_connect_children(conn_an.an_node_id, child_pos)
            else:
                conn_gn.position_offset = child_pos
                child_pos.y += conn_gn.size.y + 40
            connect_node(graph_node.name, conn_idx, conn_gn.name, 0)
    
    return int(child_pos.y)

func new_graph_nodes_for_tree(tree_root_node: HyAssetNode) -> Array[CustomGraphNode]:
    return _recursive_new_graph_nodes(tree_root_node, tree_root_node)

func _recursive_new_graph_nodes(at_asset_node: HyAssetNode, root_asset_node: HyAssetNode) -> Array[CustomGraphNode]:
    var new_graph_nodes: Array[CustomGraphNode] = []

    var this_gn: = new_graph_node(at_asset_node, root_asset_node)
    new_graph_nodes.append(this_gn)

    for conn_name in get_graph_connections_for(this_gn):
        var connected_nodes: Array[HyAssetNode] = get_graph_connected_asset_nodes(this_gn, conn_name)
        for connected_asset_node in connected_nodes:
            new_graph_nodes.append_array(_recursive_new_graph_nodes(connected_asset_node, root_asset_node))
    return new_graph_nodes

func get_graph_connections_for(graph_node: CustomGraphNode) -> Array[String]:
    if graph_node.get_meta("is_special_gn", false):
        return graph_node.get_current_connection_list()
    else:
        var asset_node: = an_lookup[graph_node.get_meta("hy_asset_node_id")]
        return asset_node.connection_list

func get_graph_connected_asset_nodes(graph_node: CustomGraphNode, conn_name: String) -> Array[HyAssetNode]:
    if graph_node.get_meta("is_special_gn", false):
        return graph_node.filter_child_connection_nodes(conn_name)
    else:
        var asset_node: = an_lookup[graph_node.get_meta("hy_asset_node_id")]
        return asset_node.get_all_connected_nodes(conn_name)

func get_graph_connected_graph_nodes(graph_node: CustomGraphNode, conn_name: String) -> Array[GraphNode]:
    var connected_asset_nodes: Array[HyAssetNode] = get_graph_connected_asset_nodes(graph_node, conn_name)
    var connected_graph_nodes: Array[GraphNode] = []
    for connected_asset_node in connected_asset_nodes:
        connected_graph_nodes.append(gn_lookup[connected_asset_node.an_node_id])
    return connected_graph_nodes


func should_be_special_gn(asset_node: HyAssetNode) -> bool:
    return special_gn_factory.types_with_special_nodes.has(asset_node.an_type)

func new_graph_node(asset_node: HyAssetNode, root_asset_node: HyAssetNode) -> CustomGraphNode:
    var graph_node: CustomGraphNode = null
    var is_special: = should_be_special_gn(asset_node)
    if is_special:
        graph_node = special_gn_factory.make_special_gn(root_asset_node, asset_node)
    else:
        graph_node = CustomGraphNode.new()
    
    var output_type: String = schema.node_schema[asset_node.an_type].get("output_value_type", "")
    var theme_var_color: String = TypeColors.get_color_for_type(output_type)
    if ThemeColorVariants.theme_colors.has(theme_var_color):
        graph_node.theme = ThemeColorVariants.get_theme_color_variant(theme_var_color)
    else:
        push_warning("No theme color variant found for color '%s'" % theme_var_color)
        print("No theme color variant found for color '%s'" % theme_var_color)

    graph_node.set_meta("hy_asset_node_id", asset_node.an_node_id)
    gn_lookup[asset_node.an_node_id] = graph_node
    
    graph_node.resizable = true
    if not output_type:
        graph_node.ignore_invalid_connection_type = true

    graph_node.title = asset_node.an_name
    
    if is_special:
        pass
    else:
        var num_inputs: = 1
        if asset_node.an_type in no_left_types:
            num_inputs = 0
        
        var node_schema: Dictionary = {}
        if asset_node.an_type and asset_node.an_type != "Unknown":
            node_schema = schema.node_schema[asset_node.an_type]
        
        var connection_names: Array
        var connection_types: Array[int]
        if node_schema:
            var type_connections: Dictionary = node_schema.get("connections", {})
            connection_names = type_connections.keys()
            for conn_name in connection_names:
                connection_types.append(type_id_lookup[type_connections[conn_name]["value_type"]])
        else:
            connection_names = asset_node.connections.keys()
            connection_types.resize(connection_names.size())
            connection_types.fill(type_id_lookup["Single"])
        var num_outputs: = connection_names.size()
        
        var setting_names: Array
        if node_schema:
            setting_names = node_schema.get("settings", {}).keys()
        else:
            setting_names = asset_node.settings.keys()
        var num_settings: = setting_names.size()
        
        var first_setting_slot: = maxi(num_inputs, num_outputs)
        
        for i in maxi(num_inputs, num_outputs) + num_settings:
            if i >= first_setting_slot:
                var setting_name: String = setting_names[i - first_setting_slot]

                var slot_node: = HBoxContainer.new()
                slot_node.name = "Slot%d" % i
                var s_name: = Label.new()
                s_name.name = "SettingName"
                s_name.text = "%s:" % setting_name
                s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                slot_node.add_child(s_name, true)

                var s_edit: Control
                var setting_value: Variant
                var setting_type: int
                if setting_name in asset_node.settings:
                    setting_value = asset_node.settings[setting_name]
                else:
                    setting_value = schema.node_schema[asset_node.an_type]["settings"][setting_name].get("default_value", 0)

                if setting_type == TYPE_BOOL:
                    s_edit = CheckBox.new()
                    s_edit.name = "SettingEdit"
                    s_edit.button_pressed = setting_value
                else:
                    s_edit = LineEdit.new()
                    s_edit.name = "SettingEdit"
                    s_edit.text = str(setting_value)
                    s_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                    s_name.size_flags_horizontal = Control.SIZE_FILL
                    if setting_type == TYPE_FLOAT or setting_type == TYPE_INT:
                        s_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
                slot_node.add_child(s_edit, true)
                
                graph_node.add_child(slot_node, true)
            else:
                var slot_node: = Label.new()
                slot_node.name = "Slot%d" % i
                graph_node.add_child(slot_node, true)
                if i < num_inputs:
                    graph_node.set_slot_enabled_left(i, true)
                    graph_node.set_slot_type_left(i, type_id_lookup[output_type])
                if i < num_outputs:
                    graph_node.set_slot_enabled_right(i, true)
                    graph_node.set_slot_type_right(i, connection_types[i])
                    slot_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
                    slot_node.text = connection_names[i]
    
    graph_node.update_port_colors(self, asset_node)
    
    if use_json_positions:
        var meta_pos: = get_node_position_from_meta(asset_node.an_node_id) * json_positions_scale
        graph_node.position_offset = meta_pos - relative_root_position
    
    return graph_node


var connection_cut_active: = false
var connection_cut_start_point: Vector2 = Vector2(0, 0)
var connection_cut_line: Line2D = null
var max_connection_cut_points: = 100000

func start_connection_cut(at_global_pos: Vector2) -> void:
    prints("Starting connection cut")
    connection_cut_active = true
    connection_cut_start_point = at_global_pos
    
    connection_cut_line = preload("res://ui/connection_cutting_line.tscn").instantiate() as Line2D
    connection_cut_line.clear_points()
    connection_cut_line.add_point(Vector2.ZERO)
    connection_cut_line.z_index = 10
    get_parent().add_child(connection_cut_line)
    connection_cut_line.global_position = at_global_pos

func add_connection_cut_point(at_global_pos: Vector2) -> void:
    if not connection_cut_line or connection_cut_line.points.size() >= max_connection_cut_points:
        return
    connection_cut_line.add_point(at_global_pos - connection_cut_start_point)

func cancel_connection_cut() -> void:
    connection_cut_active = false
    if connection_cut_line:
        get_parent().remove_child(connection_cut_line)
        connection_cut_line = null


func do_connection_cut() -> void:
    prints("cutting connections (%d points)" % connection_cut_line.points.size())
    const cut_radius: = 5.0
    const MAX_CUTS_PER_STEP: = 50
    
    #var check_point_visualizer: Control
    #if _first_cut_:
    #    check_point_visualizer = ColorRect.new()
    #    check_point_visualizer.color = Color.LAVENDER
    #    check_point_visualizer.z_index = 10
    #    check_point_visualizer.size = Vector2(4, 4)
    
    multi_connection_change = true
    
    var num_cut: = 0

    var vp_rect: = get_viewport_rect()
    var prev_cut_point: = connection_cut_start_point
    for cut_point in connection_cut_line.points:
        var cut_global_pos: = connection_cut_line.to_global(cut_point)
        var check_points: = [cut_global_pos]

        var iteration_dist: = (cut_global_pos - prev_cut_point).length()
        if iteration_dist > cut_radius:
            var interpolation_steps: = int(iteration_dist / cut_radius)
            
            for i in interpolation_steps:
                check_points.append(prev_cut_point.lerp(cut_global_pos, (i + 1) / float(interpolation_steps)))
        
        for check_point in check_points:
            if not vp_rect.has_point(check_point):
                continue
            #if _first_cut_:
            #    var copy: = check_point_visualizer.duplicate()
            #    get_parent().add_child(copy)
            #    copy.global_position = check_point
            for i in MAX_CUTS_PER_STEP:
                var connection_at_point: = get_closest_connection_at_point(check_point, cut_radius + 0.5)
                if not connection_at_point:
                    break
                num_cut += 1
                remove_connection(connection_at_point)
                #disconnect_node(connection_at_point.from_node, connection_at_point.from_port, connection_at_point.to_node, connection_at_point.to_port)
        prev_cut_point = cut_global_pos
    
    if num_cut > 0:
        create_undo_connection_change_step()
        multi_connection_change = false

    #if _first_cut_:
    #    _first_cut_ = false
    cancel_connection_cut()


var mouse_panning: = false

func handle_mouse_event(event: InputEventMouse) -> void:
    var mouse_btn_event: = event as InputEventMouseButton
    var mouse_motion_event: = event as InputEventMouseMotion
    
    if mouse_btn_event:
        if mouse_btn_event.button_index == MOUSE_BUTTON_RIGHT:
            if mouse_btn_event.is_pressed():
                if mouse_btn_event.ctrl_pressed:
                    start_connection_cut(mouse_btn_event.global_position)
                else:
                    mouse_panning = true
            elif mouse_panning:
                mouse_panning = false
            elif connection_cut_active:
                do_connection_cut()
        elif mouse_btn_event.button_index == MOUSE_BUTTON_LEFT:
            if connection_cut_active and mouse_btn_event.is_pressed():
                cancel_connection_cut()
                get_viewport().set_input_as_handled()
    if mouse_motion_event:
        if connection_cut_active:
            add_connection_cut_point(mouse_motion_event.global_position)
        elif mouse_panning:
            scroll_offset -= mouse_motion_event.relative

func on_zoom_changed() -> void:
    cur_zoom_level = zoom
    var menu_hbox: = get_menu_hbox()
    var grid_toggle_btn: = menu_hbox.get_child(4) as Button
    if zoom < 0.1:
        grid_toggle_btn.disabled = true
        show_grid = false
    else:
        grid_toggle_btn.disabled = false
        show_grid = grid_logical_enabled

func on_grid_toggled(grid_is_enabled: bool, grid_toggle_btn: Button) -> void:
    if grid_toggle_btn.disabled:
        return
    grid_logical_enabled = grid_is_enabled

#func _notification(what: int) -> void:
    #if what == NOTIFICATION_WM_MOUSE_EXIT:
        #mouse_panning = false

func load_json_file(file_path: String) -> void:
    var file = FileAccess.open(file_path, FileAccess.READ)
    if not file:
        print("Error opening JSON file %s" % file_path)
        return
    load_json(file.get_as_text())

func load_json(json_data: String) -> void:
    parsed_json_data = JSON.parse_string(json_data)
    if not parsed_json_data:
        print("Error parsing JSON")
        return

    prints("Loading JSON data")
    if loaded:
        clear_graph()
        loaded = false
    parse_root_asset_node(parsed_json_data)
    create_graph_from_parsed_data()
    loaded = true
    prints("New data loaded from json")
    if OS.has_feature("debug"):
        test_reserialize_to_file(parsed_json_data)

func _requested_open_file(path: String) -> void:
    prints("Requested open file:", path)
    load_json_file(path)

func on_begin_node_move() -> void:
    moved_nodes_positions.clear()
    var selected_nodes: Array[GraphNode] = get_selected_gns()
    for gn in selected_nodes:
        moved_nodes_positions[gn] = gn.position_offset

func on_end_node_move() -> void:
    create_move_nodes_undo_step(get_selected_gns())

func _set_gns_offsets(new_positions: Dictionary[GraphNode, Vector2]) -> void:
    for gn in new_positions.keys():
        gn.position_offset = new_positions[gn]

func create_move_nodes_undo_step(moved_nodes: Array[GraphNode]) -> void:
    prints("Creating move nodes (%d) undo step" % moved_nodes.size())
    if moved_nodes.size() == 0:
        return
    var new_positions: Dictionary[GraphNode, Vector2] = {}
    for gn in moved_nodes:
        new_positions[gn] = gn.position_offset
    undo_manager.create_action("Move Nodes")
    undo_manager.add_do_method(_set_gns_offsets.bind(new_positions))
    undo_manager.add_undo_method(_set_gns_offsets.bind(moved_nodes_positions.duplicate_deep()))
    undo_manager.commit_action(false)

func create_undo_connection_change_step() -> void:
    prints("Creating undo connection change step")
    print(cur_removed_connections)
    undo_manager.create_action("Connection Change")
    if cur_added_connections.size() > 0:
        undo_manager.add_do_method(add_multiple_connections.bind(cur_added_connections.duplicate_deep(), false))
    if cur_removed_connections.size() > 0:
        undo_manager.add_do_method(remove_multiple_connections.bind(cur_removed_connections.duplicate_deep(), false))
    
    if cur_added_connections.size() > 0:
        prints("Undo step removes %d connections" % cur_added_connections.size())
        undo_manager.add_undo_method(remove_multiple_connections.bind(cur_added_connections.duplicate_deep(), false))
    if cur_removed_connections.size() > 0:
        prints("Undo step adds back %d connections" % cur_removed_connections.size())
        undo_manager.add_undo_method(add_multiple_connections.bind(cur_removed_connections.duplicate_deep(), false))
    
    cur_added_connections.clear()
    cur_removed_connections.clear()
    
    undo_manager.commit_action(false)


func on_requested_save_file(file_path: String) -> void:
    save_to_json_file(file_path)

func save_to_json_file(file_path: String) -> void:
    var json_str: = get_asset_node_graph_json_str()
    var file: = FileAccess.open(file_path, FileAccess.WRITE)
    if not file:
        push_error("Error opening JSON file for writing: %s" % file_path)
        return
    file.store_string(json_str)
    file.close()
    prints("Saved asset node graph to JSON file: %s" % file_path)

func get_asset_node_graph_json_str() -> String:
    var serialized_data: Dictionary = serialize_asset_node_graph()
    var json_str: = JSON.stringify(serialized_data, "  " if save_formatted_json else "", false)
    if not json_str:
        push_error("Error serializing asset node graph")
        return ""
    return json_str

func serialize_asset_node_graph() -> Dictionary:
    var serialized_data: Dictionary = root_node.serialize_me(schema)
    serialized_data["$NodeEditorMetadata"] = serialize_node_editor_metadata()
    
    return serialized_data

func serialize_node_editor_metadata() -> Dictionary:
    var serialized_metadata: Dictionary = {}
    serialized_metadata["$Nodes"] = {}
    var root_gn: = gn_lookup.get(root_node.an_node_id, null) as GraphNode
    if not root_gn:
        push_error("Serialize Node Editor Metadata: Root node graph node not found")
        return {}
    var fallback_pos: = ((root_gn.position_offset - Vector2(200, 200)) / json_positions_scale).round()

    for an in all_asset_nodes:
        var gn: = gn_lookup.get(an.an_node_id, null) as GraphNode
        var gn_pos: Vector2 = (gn.position_offset / json_positions_scale).round() if gn else fallback_pos
        var node_meta_stuff: Dictionary = {
            "$Position": {
                "$x": gn_pos.x,
                "$y": gn_pos.y,
            },
        }
        if an.title:
            node_meta_stuff["$Title"] = an.title
        serialized_metadata["$Nodes"][an.an_node_id] = node_meta_stuff

    var floating_trees_serialized: Array[Dictionary] = []
    for floating_tree_root_an in floating_tree_roots:
        floating_trees_serialized.append(floating_tree_root_an.serialize_me(schema))
    serialized_metadata["$FloatingNodes"] = floating_trees_serialized
    serialized_metadata["$WorkspaceID"] = hy_workspace_id
    return serialized_metadata

func test_reserialize_to_file(data_from_json: Dictionary) -> void:
    var file_path: = "res://test_files/test_reserialize.json"
    var file: = FileAccess.open(file_path, FileAccess.WRITE)
    if not file:
        print_debug("Error opening JSON file for writing (test reserialize): %s" % file_path)
        return
    file.store_string(JSON.stringify(data_from_json, "  ", false))
    file.close()

