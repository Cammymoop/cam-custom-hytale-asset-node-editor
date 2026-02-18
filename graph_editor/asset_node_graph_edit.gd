extends GraphEdit
class_name CHANE_AssetNodeGraphEdit

signal zoom_changed(new_zoom: float)

const SpecialGNFactory = preload("res://custom_graph_nodes/special_gn_factory.gd")

@export var save_formatted_json: = true
@export_file_path("*.json") var test_json_file: String = ""

var editor: CHANE_AssetNodeEditor = null
var serializer: CHANE_HyAssetNodeSerializer

var parsed_has_no_positions: = false
var loaded: = false

var cur_file_name: = ""
var cur_file_path: = ""
var has_saved_to_cur_file: = false

var global_gn_counter: int = 0

const DEFAULT_HY_WORKSPACE_ID: String = "HytaleGenerator - Biome"
var hy_workspace_id: String = ""

var all_asset_nodes: Array[HyAssetNode] = []
var all_asset_node_ids: Array[String] = []
var floating_tree_roots: Array[HyAssetNode] = []
var root_node: HyAssetNode = null

@export var popup_menu_root: PopupMenuRoot
@onready var special_gn_factory: SpecialGNFactory = $SpecialGNFactory

var asset_node_meta: Dictionary[String, Dictionary] = {}
var all_meta: Dictionary = {}


var an_lookup: Dictionary[String, HyAssetNode] = {}

var more_type_names: Array[String] = [
    "Single",
    "Multi",
]
var type_id_lookup: Dictionary[String, int] = {}

@export var use_json_positions: = true
@export var json_positions_scale: Vector2 = Vector2(0.5, 0.5)
var relative_root_position: Vector2 = Vector2(0, 0)

@export var text_field_def_characters: = 12

@export var verbose: = false

@onready var cur_zoom_level: = zoom
@onready var grid_logical_enabled: = show_grid

var copied_nodes: Array[GraphElement] = []
var copied_node_reference_offset: Vector2 = Vector2.ZERO
var copied_from_pos_offset: Vector2 = Vector2.ZERO
var copied_from_screen_center_pos_offset: Vector2 = Vector2.ZERO
var copied_nodes_internal_connections: Dictionary[int, Array]
var copied_nodes_ans: Array[HyAssetNode] = []
var clipboard_was_from_cut: bool = false
var clipboard_was_from_external: bool = false
var copied_external_ans: Array[HyAssetNode] = []
var copied_external_node_metadata: Dictionary = {}
var copied_external_groups: Array[Dictionary] = []
var in_graph_copy_id: String = ""

var context_menu_target_node: Node = null
var context_menu_pos_offset: Vector2 = Vector2.ZERO
var context_menu_movement_acc: = 0.0
var context_menu_ready: bool = false

var output_port_drop_offset: Vector2 = Vector2(2, -34)
var input_port_drop_first_offset: Vector2 = Vector2(-2, -34)
var input_port_drop_additional_offset: Vector2 = Vector2(0, -19)

var undo_manager: UndoRedo = UndoRedo.new()
var undo_tracked_nodes: Array[Node] = []
var multi_connection_change: bool = false
var cur_connection_added_ges: Array[GraphElement] = []
var cur_connection_removed_ges: Array[GraphElement] = []
var cur_added_connections: Array[Dictionary] = []
var cur_removed_connections: Array[Dictionary] = []
var cur_removed_group_relations: Array[Dictionary] = []
var cur_added_group_relations: Array[Dictionary] = []
var moved_nodes_old_positions: Dictionary[GraphElement, Vector2] = {}
var moved_groups_old_sizes: Dictionary[GraphFrame, Vector2] = {}
var cur_move_detached_nodes: = false

var file_menu_btn: MenuButton = null
var file_menu_menu: PopupMenu = null

var settings_menu_btn: MenuButton = null
var settings_menu_menu: PopupMenu = null

var unedited: = true

func get_unique_an_id(id_prefix: String = "") -> String:
    return CHANE_HyAssetNodeSerializer.get_unique_an_id(id_prefix)

func _ready() -> void:
    print("a sentence with spaces".replace(" ", "_"))
    serializer = CHANE_HyAssetNodeSerializer.new()
    serializer.name = "ANSerializer"
    add_child(serializer, true)

    assert(popup_menu_root != null, "Popup menu root is not set, please set it in the inspector")
    
    focus_exited.connect(on_focus_exited)
    
    setup_menus()

    #add_valid_left_disconnect_type(1)
    begin_node_move.connect(on_begin_node_move)
    end_node_move.connect(on_end_node_move)
    
    connection_request.connect(_connection_request)
    disconnection_request.connect(_disconnection_request)

    duplicate_nodes_request.connect(_duplicate_request)
    copy_nodes_request.connect(_copy_request)
    cut_nodes_request.connect(_cut_request)
    paste_nodes_request.connect(_paste_request)
    delete_nodes_request.connect(_delete_request)
    
    connection_to_empty.connect(_connect_right_request)
    connection_from_empty.connect(_connect_left_request)
    
    graph_elements_linked_to_frame_request.connect(_link_to_group_request)
    
    var menu_hbox: = get_menu_hbox()
    var grid_toggle_btn: = menu_hbox.get_child(4) as Button
    grid_toggle_btn.toggled.connect(on_grid_toggled.bind(grid_toggle_btn))
    
    var last_menu_hbox_item: = menu_hbox.get_child(menu_hbox.get_child_count() - 1)
    var version_label: = Label.new()
    version_label.text = ""
    version_label.add_theme_color_override("font_color", Color.WHITE.darkened(0.5))
    version_label.add_theme_font_size_override("font_size", 12)
    version_label.grow_horizontal = Control.GROW_DIRECTION_END
    version_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    version_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    version_label.text = "Cam Hytale ANE %s" % Util.get_version_number_string()
    last_menu_hbox_item.add_child(version_label)
    version_label.offset_left = 12
    
    setup_graph_edit_connection_types()

func set_editor(new_editor: CHANE_AssetNodeEditor) -> void:
    editor = new_editor
    
func setup_graph_edit_connection_types() -> void:
    for extra_type_name in more_type_names:
        var type_idx: = type_names.size()
        type_names[type_idx] = extra_type_name
        #add_valid_left_disconnect_type(type_idx)

    type_names[type_names.size()] = "Unknown"
    
    for val_type_name in SchemaManager.schema.value_types:
        var val_type_idx: = type_names.size()
        type_names[val_type_idx] = val_type_name
        add_valid_connection_type(val_type_idx, val_type_idx)
        #add_valid_left_disconnect_type(val_type_idx)

    for type_id in type_names.keys():
        type_id_lookup[type_names[type_id]] = type_id

func get_left_type_of_conn_info(connection_info: Dictionary) -> String:
    var unknown_connection_type: int = type_id_lookup["Unknown"]
    var left_gn: GraphNode = get_node(NodePath(connection_info["from_node"]))
    var raw_type: int = left_gn.get_slot_type_right(connection_info["from_port"])
    if raw_type <= unknown_connection_type:
        return ""
    return type_names[raw_type]

func get_right_type_of_conn_info(connection_info: Dictionary) -> String:
    var unknown_connection_type: int = type_id_lookup["Unknown"]
    var right_gn: GraphNode = get_node(NodePath(connection_info["to_node"]))
    var raw_type: int = right_gn.get_slot_type_left(connection_info["to_port"])
    if raw_type <= unknown_connection_type:
        return ""
    return type_names[raw_type]

func get_type_of_conn_info(connection_info: Dictionary) -> String:
    var left_type: String = get_left_type_of_conn_info(connection_info)
    var right_type: String = get_right_type_of_conn_info(connection_info)
    if left_type == "":
        return right_type
    elif right_type == "":
        return left_type
    elif left_type != right_type:
        return ""
    return left_type

func on_focus_exited() -> void:
    if connection_cut_active:
        cancel_connection_cut()
    mouse_panning = false

func _shortcut_input(event: InputEvent) -> void:
    if not editor.are_shortcuts_allowed():
        return

    if Input.is_action_just_pressed_by_event("graph_select_all_nodes", event, true):
        accept_event()
        select_all()
    elif Input.is_action_just_pressed_by_event("graph_deselect_all_nodes", event, true):
        accept_event()
        deselect_all()
    elif Input.is_action_just_pressed_by_event("cut_inclusive_shortcut", event, true):
        accept_event()
        cut_selected_nodes_inclusive()
    elif Input.is_action_just_pressed_by_event("delete_inclusive_shortcut", event, true):
        accept_event()
        delete_selected_nodes_inclusive()

func _process(_delta: float) -> void:
    if is_moving_nodes() and not cur_move_detached_nodes and Util.is_shift_pressed():
        change_current_node_move_to_detach_mode()
    if cur_zoom_level != zoom:
        on_zoom_changed()

func setup_menus() -> void:
    # reverse order so they can just move themselves to the start
    setup_settings_menu()
    setup_file_menu()

    var menu_hbox: = get_menu_hbox()
    var sep: = VSeparator.new()
    menu_hbox.add_child(sep)
    menu_hbox.move_child(sep, settings_menu_btn.get_index() + 1)
    
func setup_file_menu() -> void:
    file_menu_btn = preload("res://ui/file_menu.tscn").instantiate()
    file_menu_menu = file_menu_btn.get_popup()
    var menu_hbox: = get_menu_hbox()
    menu_hbox.add_child(file_menu_btn)
    menu_hbox.move_child(file_menu_btn, 0)
    
    file_menu_menu.id_pressed.connect(on_file_menu_id_pressed)

func on_file_menu_id_pressed(id: int) -> void:
    editor.on_file_menu_id_pressed(id, file_menu_menu)

func setup_settings_menu() -> void:
    settings_menu_btn = preload("res://ui/settings_menu.tscn").instantiate()
    settings_menu_menu = settings_menu_btn.get_popup()
    var menu_hbox: = get_menu_hbox()
    menu_hbox.add_child(settings_menu_btn)
    menu_hbox.move_child(settings_menu_btn, 0)
    settings_menu_menu.index_pressed.connect(on_settings_menu_index_pressed)
    settings_menu_menu.about_to_popup.connect(on_settings_menu_about_to_popup)

func on_settings_menu_about_to_popup() -> void:
    var dbl_click_is_greedy: = ANESettings.select_subtree_is_greedy
    settings_menu_menu.set_item_checked(1, dbl_click_is_greedy)

func on_settings_menu_index_pressed(index: int) -> void:
    editor.on_settings_menu_index_pressed(index, settings_menu_menu)

func snap_ge(ge: GraphElement) -> void:
    if snapping_enabled:
        ge.position_offset = ge.position_offset.snapped(Vector2.ONE * snapping_distance)

func snap_ges(ges: Array) -> void:
    if not snapping_enabled:
        return
    for ge in ges:
        snap_ge(ge)

func is_mouse_wheel_event(event: InputEvent) -> bool:
    return event is InputEventMouseButton and (
        event.button_index == MOUSE_BUTTON_WHEEL_UP
        or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
        or event.button_index == MOUSE_BUTTON_WHEEL_LEFT
        or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT
    )
    
func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouse:
        if is_mouse_wheel_event(event):
            return
        handle_mouse_event(event as InputEventMouse)
        return

func _connection_request(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int) -> void:
    _add_connection(from_gn_name, from_port, to_gn_name, to_port)

func add_multiple_connections(conns_to_add: Array[Dictionary], with_undo: bool = true) -> void:
    var self_multi: = not multi_connection_change
    multi_connection_change = true
    for conn_to_add in conns_to_add:
        add_connection(conn_to_add, with_undo)

    if self_multi:
        if with_undo:
            create_undo_connection_change_step()
        multi_connection_change = false

func get_an_set_for_graph_nodes(gns: Array[GraphNode]) -> Array[HyAssetNode]:
    var ans: Array[HyAssetNode] = []
    for gn in gns:
        ans.append_array(get_gn_own_asset_nodes(gn))
    return ans

func add_connection(connection_info: Dictionary, with_undo: bool = true) -> void:
    _add_connection(connection_info["from_node"], connection_info["from_port"], connection_info["to_node"], connection_info["to_port"], with_undo)

func _add_connection(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int, with_undo: bool = true) -> void:
    var old_multi_conn_change: = multi_connection_change
    # set multi_connection_change so removed connections get added as part of the same undo step
    multi_connection_change = true

    var from_gn: GraphNode = get_node(NodePath(from_gn_name))
    var to_gn: GraphNode = get_node(NodePath(to_gn_name))
    
    #editor.connect_graph_nodes(from_gn, from_port, to_gn, to_port, self)
    
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

    if with_undo:
        cur_added_connections.append({
            "from_node": from_gn_name,
            "from_port": from_port,
            "to_node": to_gn_name,
            "to_port": to_port,
        })

    # restore multi_connection_change to whatever it was in the outer context
    multi_connection_change = old_multi_conn_change
    connect_node(from_gn_name, from_port, to_gn_name, to_port)
    if with_undo and not multi_connection_change:
        create_undo_connection_change_step()

func _disconnection_request(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int) -> void:
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

func disconnect_connection_info(conn_info: Dictionary) -> void:
    disconnect_node(conn_info["from_node"], conn_info["from_port"], conn_info["to_node"], conn_info["to_port"])

func _remove_connection(from_gn_name: StringName, from_port: int, to_gn_name: StringName, to_port: int, with_undo: bool = true) -> void:
    disconnect_node(from_gn_name, from_port, to_gn_name, to_port)

    var from_gn: GraphNode = get_node(NodePath(from_gn_name))
    var to_gn: GraphNode = get_node(NodePath(to_gn_name))
    var from_an: HyAssetNode = an_lookup.get(from_gn.get_meta("hy_asset_node_id", ""))
    var from_connection_name: String = from_an.connection_list[from_port]
    var to_an: HyAssetNode = an_lookup.get(to_gn.get_meta("hy_asset_node_id", ""))

    if from_an and to_an:
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
    _erase_asset_node(asset_node)
    an_lookup.erase(asset_node.an_node_id)
    editor.gn_lookup.erase(asset_node.an_node_id)

func _erase_asset_node(asset_node: HyAssetNode) -> void:
    editor.remove_asset_node(asset_node)
    #all_asset_nodes.erase(asset_node)
    #all_asset_node_ids.erase(asset_node.an_node_id)
    #if asset_node in floating_tree_roots:
        #floating_tree_roots.erase(asset_node)

func duplicate_and_add_asset_node(asset_node: HyAssetNode, new_gn: GraphNode = null) -> HyAssetNode:
    var id_prefix: String = SchemaManager.schema.get_id_prefix_for_node_type(asset_node.an_type)
    if not asset_node.an_node_id:
        push_warning("The asset node being duplicated had no ID")
        asset_node.an_node_id = get_unique_an_id(id_prefix)
    
    var new_id_for_copy: = get_unique_an_id(id_prefix)
    var asset_node_copy: = asset_node.get_shallow_copy(new_id_for_copy)
    _register_asset_node(asset_node_copy)
    floating_tree_roots.append(asset_node_copy)
    if new_gn:
        editor.gn_lookup[asset_node_copy.an_node_id] = new_gn
        new_gn.set_meta("hy_asset_node_id", asset_node_copy.an_node_id)
    return asset_node_copy

func duplicate_and_add_filtered_an_tree(root_asset_node: HyAssetNode, asset_node_set: Array[HyAssetNode]) -> HyAssetNode:
    var new_root_an: HyAssetNode = duplicate_and_add_asset_node(root_asset_node)
    var conn_names: Array[String] = root_asset_node.connection_list.duplicate()
    for conn_name in conn_names:
        for connected_an in root_asset_node.get_all_connected_nodes(conn_name):
            if connected_an not in asset_node_set:
                continue
            var new_an: HyAssetNode = duplicate_and_add_filtered_an_tree(connected_an, asset_node_set)
            floating_tree_roots.erase(new_an)
            new_root_an.append_node_to_connection(conn_name, new_an)
    
    return new_root_an

func add_existing_asset_node(asset_node: HyAssetNode, gn: GraphNode = null) -> void:
    if gn:
        editor.register_asset_node_at(asset_node, gn.position_offset)
    else:
        editor.register_asset_node(asset_node)
    #all_asset_nodes.append(asset_node)
    #all_asset_node_ids.append(asset_node.an_node_id)
    if not asset_node.an_node_id:
        push_warning("Trying to add existing asset node with no ID")
    else:
        #an_lookup[asset_node.an_node_id] = asset_node
        if gn:
            editor.gn_lookup[asset_node.an_node_id] = gn

func _register_asset_node(asset_node: HyAssetNode) -> void:
    editor.register_asset_node(asset_node)
    #if asset_node in all_asset_nodes:
        #print_debug("Asset node %s already registered" % asset_node.an_node_id)
    #else:
        #all_asset_nodes.append(asset_node)
    #if asset_node.an_node_id in all_asset_node_ids:
        #print_debug("Asset node ID %s already registered" % asset_node.an_node_id)
    #else:
        #all_asset_node_ids.append(asset_node.an_node_id)
    #an_lookup[asset_node.an_node_id] = asset_node

func _delete_request(delete_ge_names: Array[StringName]) -> void:
    var ges_to_remove: Array[GraphElement] = []
    for ge_name in delete_ge_names:
        var ge: GraphElement = get_node_or_null(NodePath(ge_name))
        if ge:
            ges_to_remove.append(ge)
    _delete_request_refs(ges_to_remove)
    
func _delete_request_refs(delete_ges: Array[GraphElement]) -> void:
    var root_gn: GraphNode = editor.root_graph_node
    if root_gn in delete_ges:
        delete_ges.erase(root_gn)
    if delete_ges.size() == 0:
        return
    remove_ges_with_connections_and_undo(delete_ges)

func delete_selected_nodes_inclusive() -> void:
    var inclusive_selected: Array[GraphElement] = get_inclusive_selected_ges() 
    _delete_request_refs(inclusive_selected)

func get_drop_offset_for_output_port() -> Vector2:
    return output_port_drop_offset

func get_drop_offset_for_input_port(input_port_idx: int) -> Vector2:
    return input_port_drop_first_offset + (input_port_drop_additional_offset * input_port_idx)

func _connect_right_request(from_gn_name: StringName, from_port: int, dropped_local_pos: Vector2) -> void:
    var connection_info: = {
        "from_node": from_gn_name,
        "from_port": from_port,
    }
    _connect_new_request(true, dropped_local_pos, connection_info)

func _connect_left_request(to_gn_name: StringName, to_port: int, dropped_local_pos: Vector2) -> void:
    var connection_info: = {
        "to_node": to_gn_name,
        "to_port": to_port,
    }
    _connect_new_request(false, dropped_local_pos, connection_info)

func _connect_new_request(is_right: bool, at_local_pos: Vector2, connection_info: Dictionary) -> void:
    var connecting_from_gn: CustomGraphNode = get_node(NodePath(connection_info["from_node" if is_right else "to_node"]))
    var asset_node: HyAssetNode = editor.get_gn_main_asset_node(connecting_from_gn)

    var conn_value_type: String = ""
    if asset_node.an_type and asset_node.an_type != "Unknown":
        if is_right:
            conn_value_type = SchemaManager.schema.get_input_conn_value_type_for_idx(asset_node.an_type, connection_info["from_port"])
        else:
            conn_value_type = SchemaManager.schema.get_output_value_type(asset_node.an_type)

    var at_pos_offset: = local_pos_to_pos_offset(at_local_pos)
    var cur_drop_info: = {
        "dropping_in_graph": self,
        "at_pos_offset": at_pos_offset,
        "has_position": true,
        "connection_info": connection_info,
        "connection_value_type": conn_value_type,
    }
    
    # Add the new node to a group if dropped point is inside it (plus some margin)
    var all_groups: Array[GraphFrame] = get_all_groups()
    for group in all_groups:
        var group_rect: = get_pos_offset_rect(group).grow(8)
        if group_rect.has_point(at_pos_offset):
            cur_drop_info["into_group"] = group
            break

    editor.connect_new_request(cur_drop_info)


func get_all_graph_nodes() -> Array[CustomGraphNode]:
    var all_gns: Array[CustomGraphNode] = []
    for ge in get_children():
        if ge is CustomGraphNode:
            all_gns.append(ge)
    return all_gns

func get_selected_gns() -> Array[GraphNode]:
    var selected_gns: Array[GraphNode] = []
    for c in get_children():
        if c is GraphNode and c.selected:
            selected_gns.append(c)
    return selected_gns

func get_selected_ges() -> Array[GraphElement]:
    var selected_ges: Array[GraphElement] = []
    for ge in get_children():
        if ge is GraphElement and ge.selected:
            selected_ges.append(ge)
    return selected_ges

func get_selected_groups() -> Array[GraphFrame]:
    var selected_groups: Array[GraphFrame] = []
    for ge in get_children():
        if ge is GraphFrame and ge.selected:
            selected_groups.append(ge)
    return selected_groups

## Get all selected graph elements and group members of selected groups including recusively through sub-groups
func get_inclusive_selected_ges() -> Array[GraphElement]:
    var selected_ges: Array[GraphElement] = get_selected_ges()
    for ge in selected_ges:
        if ge is GraphFrame:
            selected_ges.append_array(get_recursive_group_members(ge))
    return selected_ges

func get_group_members(group: GraphFrame) -> Array[GraphElement]:
    var members: Array[GraphElement] = []
    for member_name in get_attached_nodes_of_frame(group.name):
        var ge: = get_node(NodePath(member_name)) as GraphElement
        if ge:
            members.append(ge)
    return members

func get_recursive_group_members(group: GraphFrame) -> Array[GraphElement]:
    var members: Array[GraphElement] = []
    var group_member_names: Array[StringName] = get_attached_nodes_of_frame(group.name)
    for member_name in group_member_names:
        var sub_group: = get_node(NodePath(member_name)) as GraphFrame
        if sub_group:
            members.append_array(get_recursive_group_members(sub_group))
        members.append(get_node(NodePath(member_name)) as GraphElement)
    return members

func get_all_ges() -> Array[GraphElement]:
    var all_ges: Array[GraphElement] = []
    for ge in get_children():
        if ge is GraphElement:
            all_ges.append(ge)
    return all_ges

func select_all() -> void:
    for c in get_children():
        if c is GraphElement:
            c.selected = true

func deselect_all() -> void:
    set_selected(null)

func invert_selection() -> void:
    var selected_ges: Array[GraphElement] = get_selected_ges()
    for ge in get_children():
        if not ge is GraphElement:
            continue
        ge.selected = ge not in selected_ges

func select_gns(gns: Array[CustomGraphNode]) -> void:
    var ges: Array[GraphElement] = []
    ges.assign(gns)
    select_ges(ges)

func select_ges(ges: Array[GraphElement]) -> void:
    deselect_all()
    for ge in ges:
        ge.selected = true

func select_nodes_in_group(group: GraphFrame, deep: bool = true) -> void:
    var member_ges: Array[GraphElement] = []
    if deep:
        member_ges.append_array(get_recursive_group_members(group))
    else:
        member_ges.append_array(get_attached_nodes_of_frame(group.name))
    for ge in member_ges:
        ge.selected = true

func _duplicate_request() -> void:
    duplicate_selected_ges()

func duplicate_selected_ges() -> void:
    # TODO: dont clobber the clipboard
    _copy_request()
    _paste_request()

func discard_copied_nodes() -> void:
    copied_nodes.clear()
    copied_nodes_ans.clear()
    copied_nodes_internal_connections.clear()
    clipboard_was_from_external = false

    for an in copied_external_ans:
        if an and an.an_node_id and an.an_node_id not in all_asset_node_ids:
            if an.an_node_id in asset_node_meta:
                asset_node_meta.erase(an.an_node_id)
    copied_external_ans.clear()
    copied_external_node_metadata.clear()
    copied_external_groups.clear()
    in_graph_copy_id = ""

func _cut_request() -> void:
    _cut_refs(get_selected_ges())

func cut_selected_nodes_inclusive() -> void:
    _cut_refs(get_inclusive_selected_ges())

func _cut_refs(nodes_to_cut: Array[GraphElement]) -> void:
    var root_gn: GraphNode = editor.root_graph_node
    if root_gn in nodes_to_cut:
        nodes_to_cut.erase(root_gn)
    if nodes_to_cut.size() == 0:
        return
    _copy_or_cut_ges(nodes_to_cut)
    # this gets set to false if we ever undo. so that we never try to re-use the cut nodes while they actually exist in the graph
    clipboard_was_from_cut = true
    # do the removal and create the undo step for removing them (separate from clipboard)
    remove_ges_with_connections_and_undo(nodes_to_cut)

func _copy_request() -> void:
    var selected_ges: Array[GraphElement] = get_selected_ges()
    var selected_ge_names: Array[String] = []
    for ge in selected_ges:
        selected_ge_names.append(ge.name)
    _copy_or_cut_ges(selected_ges)
    clipboard_was_from_cut = false

func _copy_or_cut_ges(ges: Array[GraphElement]) -> void:
    if ges.size() == 0:
        return
    if copied_nodes:
        discard_copied_nodes()
    copied_nodes = ges
    save_copied_nodes_internal_connections()
    save_copied_nodes_an_references()
    copied_from_pos_offset = get_leftmost_pos_offset_of_ges(ges)
    copied_from_screen_center_pos_offset = get_center_pos_offset()
    in_graph_copy_id = Util.random_str(16)
    sort_all_an_connections()
    #ClipboardManager.send_copied_nodes_to_clipboard(self)

func get_leftmost_pos_offset_of_ges(ges: Array[GraphElement]) -> Vector2:
    if ges.size() == 0:
        return get_center_pos_offset()
    var leftmost_pos_offset: Vector2 = ges[0].position_offset
    for ge in ges:
        var ge_pos: Vector2 = ge.position_offset
        if ge_pos.x < leftmost_pos_offset.x or (ge_pos.x == leftmost_pos_offset.x and ge_pos.y < leftmost_pos_offset.y):
            leftmost_pos_offset = ge_pos
    return leftmost_pos_offset

func save_copied_nodes_internal_connections() -> void:
    var copied_nodes_names: Array[String] = []
    for ge in copied_nodes:
        copied_nodes_names.append(ge.name)

    copied_nodes_internal_connections.clear()
    for ge_idx in copied_nodes.size():
        var graph_node: = copied_nodes[ge_idx] as CustomGraphNode
        if not graph_node:
            continue

        var this_internal_connections: Array[Dictionary] = []
        var gn_connections: = raw_connections(graph_node)
        for conn_info in gn_connections:
            if conn_info["from_node"] != graph_node.name:
                continue
            var index_of_to_node: int = copied_nodes_names.find(conn_info["to_node"])
            if index_of_to_node == -1:
                continue
            this_internal_connections.append({
                "from_port": conn_info["from_port"],
                "to_port": 0,
                "to_node": index_of_to_node,
            })
        copied_nodes_internal_connections[ge_idx] = this_internal_connections

func save_copied_nodes_an_references() -> void:
    copied_nodes_ans.clear()
    for ge in copied_nodes:
        if ge is CustomGraphNode:
            copied_nodes_ans.append_array(get_gn_own_asset_nodes(ge))

func _paste_request() -> void:
    var screen_center_pos: = get_viewport_rect().size / 2
    _paste_request_at(screen_center_pos, true)

func _paste_request_at(paste_local_pos: Vector2, paste_screen_relative: bool = false) -> void:
    ClipboardManager.load_copied_nodes_from_clipboard(self)
    
    if clipboard_was_from_external:
        prints("pasting from external")
        paste_from_external()

    if not copied_nodes:
        return
    deselect_all()
    
    var destination_offset: = Vector2.ZERO
    var paste_pos_offset: = local_pos_to_pos_offset(paste_local_pos)
    var delta_offset: = paste_pos_offset - copied_from_pos_offset
    if paste_screen_relative:
        delta_offset = paste_pos_offset - copied_from_screen_center_pos_offset

    if delta_offset.length() < 30:
        destination_offset = Vector2(4, 40)
        copied_from_pos_offset += destination_offset
        copied_from_screen_center_pos_offset += destination_offset
    else:
        destination_offset = delta_offset
    
    var pasted_nodes: = _add_pasted_nodes(copied_nodes, copied_nodes_ans, not clipboard_was_from_cut)
    var new_connections_needed: Array[Dictionary] = []
    for gn_idx in copied_nodes.size():
        if not copied_nodes_internal_connections.has(gn_idx):
            continue
        var copied_input_connections: Array[Dictionary] = copied_nodes_internal_connections[gn_idx]
        for input_conn_idx in copied_input_connections.size():
            var new_conn_info: Dictionary = copied_input_connections[input_conn_idx].duplicate()
            new_conn_info["from_node"] = pasted_nodes[gn_idx].name
            new_conn_info["to_node"] = pasted_nodes[new_conn_info["to_node"]].name
            new_connections_needed.append(new_conn_info)
    
    for pasted_gn in pasted_nodes:
        pasted_gn.position_offset += destination_offset
        snap_ge(pasted_gn)
        pasted_gn.selected = true
    add_multiple_connections(new_connections_needed, false)
    
    cur_added_connections = new_connections_needed
    cur_connection_added_ges = pasted_nodes
    create_undo_connection_change_step()

func paste_from_external() -> void:
    var old_json_scale: = json_positions_scale
    json_positions_scale = Vector2.ONE
    var screen_center_pos: Vector2 = get_center_pos_offset()
    prints("screen center pos offset: %s" % [screen_center_pos])
    var an_roots: Array[HyAssetNode] = get_an_roots_within_set(copied_external_ans)
    floating_tree_roots.append_array(an_roots)
    var added_gns: = make_and_position_graph_nodes_for_trees(an_roots, false, screen_center_pos)
    var added_ges: Array[GraphElement] = []
    added_ges.append_array(added_gns)
    json_positions_scale = old_json_scale
    
    var added_groups: Array[GraphFrame] = []
    for group_data in copied_external_groups:
        var new_group: = deserialize_and_add_group(group_data, false, true)
        added_groups.append(new_group)
        added_ges.append(new_group)
    add_nodes_inside_to_groups(added_groups, added_ges, true)

    select_ges(added_ges)
    
    cur_added_connections = get_internal_connections_for_gns(added_gns)
    cur_connection_added_ges.assign(added_ges)
    create_undo_connection_change_step()
    discard_copied_nodes()

func add_nodes_inside_to_groups(groups: Array[GraphFrame], ges: Array[GraphElement], with_undo: bool, empty_no_shrink: bool = true) -> void:
    var group_rects: Array[Rect2] = []
    for group in groups:
        group_rects.append(get_pos_offset_rect(group))
    
    # TODO: better detection in the case of nested groups
    var added_group_relations: Array[Dictionary] = []
    for graph_element in ges:
        var ge_rect: Rect2 = get_pos_offset_rect(graph_element)
        for group_idx in group_rects.size():
            var group_rect: Rect2 = group_rects[group_idx]
            var the_group: GraphFrame = groups[group_idx]
            if graph_element is GraphFrame:
                if graph_element == the_group:
                    continue
                if group_rect.encloses(ge_rect):
                    added_group_relations.append({
                        "group": the_group,
                        "member": graph_element,
                    })
                    break
            else:
                if group_rect.has_point(ge_rect.get_center()):
                    added_group_relations.append({
                        "group": the_group,
                        "member": graph_element,
                    })
                    break
    if empty_no_shrink:
        for the_group in groups:
            if get_attached_nodes_of_frame(the_group.name).size() == 0:
                the_group.autoshrink_enabled = false
    add_group_relations(added_group_relations, with_undo)

func _add_pasted_nodes(ges: Array[GraphElement], asset_node_set: Array[HyAssetNode], make_duplicates: bool) -> Array[GraphElement]:
    var pasted_ges: Array[GraphElement] = []
    if not make_duplicates:
        # TODO: Make a out of tree node set container helper thing to better handle keeping these around or just change functionality
        # so that any paste that isn't able to be duplicated from existing nodes goes through the serialization/deserialization process instead
        var pasted_an_roots: Array[HyAssetNode] = get_an_roots_within_set(asset_node_set)
        floating_tree_roots.append_array(pasted_an_roots)
        pasted_ges = ges
        for ge in ges:
            add_graph_element_child(ge)
            if ge is GraphFrame:
                bring_group_to_front(ge)
    else:
        for ge in ges:
            var duplicate_ge: = duplicate_graph_element(ge, asset_node_set)
            add_graph_element_child(duplicate_ge)
            pasted_ges.append(duplicate_ge)
            if duplicate_ge is GraphFrame:
                bring_group_to_front(duplicate_ge)
    return pasted_ges

func duplicate_graph_element(the_graph_element: GraphElement, allowed_an_list: Array[HyAssetNode] = []) -> GraphElement:
    if the_graph_element is GraphFrame:
        return the_graph_element.duplicate()
    else:
        return duplicate_graph_node(the_graph_element, allowed_an_list)

func duplicate_graph_node(gn: CustomGraphNode, allowed_an_list: Array[HyAssetNode] = []) -> CustomGraphNode:
    var duplicate_gn: CustomGraphNode
    if editor.gn_is_special(gn):
        if not allowed_an_list:
            allowed_an_list = get_gn_own_asset_nodes(gn)
        duplicate_gn = special_gn_factory.make_duplicate_special_gn(gn, allowed_an_list)
    else:
        if not gn.get_meta("hy_asset_node_id", ""):
            duplicate_gn = gn.duplicate()
        else:
            var old_an: HyAssetNode = safe_get_an_from_gn(gn, allowed_an_list)
            duplicate_gn = _duplicate_synced_graph_node(gn, old_an)

    init_duplicate_graph_node(duplicate_gn, gn)
    return duplicate_gn

func init_duplicate_graph_node(duplicate_gn: CustomGraphNode, original_gn: CustomGraphNode) -> void:
    if original_gn.theme:
        duplicate_gn.theme = original_gn.theme
    if original_gn.node_type_schema:
        duplicate_gn.set_node_type_schema(original_gn.node_type_schema)
    duplicate_gn.ignore_invalid_connection_type = original_gn.ignore_invalid_connection_type
    duplicate_gn.resizable = original_gn.resizable
    duplicate_gn.title = original_gn.title
    duplicate_gn.name = get_duplicate_gn_name(original_gn.name)

    #if not editor.gn_is_special(duplicate_gn) and duplicate_gn.get_meta("hy_asset_node_id", ""):
        #setup_synchers_for_duplicate_graph_node(duplicate_gn)

func _duplicate_synced_graph_node(gn: CustomGraphNode, old_an: HyAssetNode) -> CustomGraphNode:
    var duplicate_gn: CustomGraphNode = gn.duplicate()
    var new_an: = duplicate_and_add_asset_node(old_an, duplicate_gn)
    duplicate_gn.fix_duplicate_settings_syncer(new_an)
    return duplicate_gn

func safe_get_an_from_gn(gn: CustomGraphNode, extra_an_list: Array[HyAssetNode] = []) -> HyAssetNode:
    var an_id: String = gn.get_meta("hy_asset_node_id", "")
    if not an_id:
        return null
    if an_id in an_lookup:
        return an_lookup[an_id]
    for an in extra_an_list:
        if an.an_node_id == an_id:
            return an
    return null

func clear_graph() -> void:
    prints("clearing graph")
    all_asset_nodes.clear()
    all_asset_node_ids.clear()
    floating_tree_roots.clear()
    root_node = null
    an_lookup.clear()
    asset_node_meta.clear()
    all_meta.clear()
    _clear_ge_children()
    
    cancel_connection_cut()

    undo_manager.clear_history()
    discard_copied_nodes()

    global_gn_counter = 0

func _clear_ge_children() -> void:
    for child in get_children():
        if child is GraphElement:
            remove_child(child)
            child.queue_free()

func scroll_to_graph_element(graph_element: GraphElement) -> void:
    var ge_center: Vector2 = get_pos_offset_rect(graph_element).get_center()
    scroll_to_pos_offset(ge_center)

func scroll_to_pos_offset(pos_offset: Vector2) -> void:
    await get_tree().process_frame
    scroll_offset = get_scroll_of_pos_offset_centered(pos_offset)

func get_scroll_of_pos_offset_centered(pos_offset: Vector2) -> Vector2:
    return pos_offset * zoom - (size / 2) 

func get_node_position_from_aux(node_id: String) -> Vector2:
    if not editor.asset_node_aux_data.has(node_id):
        push_warning("Asset node %s not found in aux data" % node_id)
        return Vector2.ZERO
    return editor.asset_node_aux_data[node_id].position

func register_tree_result_ans(tree_result: CHANE_HyAssetNodeSerializer.TreeParseResult) -> void:
    for an in tree_result.all_nodes:
        _register_asset_node(an)


func make_json_groups(group_datas: Array[Dictionary]) -> void:
    for group_data in group_datas:
        deserialize_and_add_group_and_attach_graph_nodes(group_data)
    refresh_graph_elements_in_frame_status()
    
func make_and_position_graph_nodes_for_trees(an_roots: Array[HyAssetNode], from_loaded: bool, add_offset: Vector2 = Vector2.ZERO) -> Array[CustomGraphNode]:
    var manually_position: bool = from_loaded and not editor.use_json_positions
    var base_tree_pos: = Vector2(0, 100)
    var all_added_gns: Array[CustomGraphNode] = []
    for tree_root_node in an_roots:
        var new_graph_nodes: Array[CustomGraphNode] = new_graph_nodes_for_tree(tree_root_node)
        all_added_gns.append_array(new_graph_nodes)
        for new_gn in new_graph_nodes:
            add_graph_node_child(new_gn)
            if manually_position:
                new_gn.position_offset = Vector2(0, -500)
            if add_offset:
                new_gn.position_offset += add_offset
        
        if manually_position:
            var last_y: int = move_and_connect_children(tree_root_node.an_node_id, base_tree_pos)
            base_tree_pos.y = last_y + 40
        else:
            connect_children(new_graph_nodes[0])
        
        if not from_loaded:
            snap_ges(new_graph_nodes)
    return all_added_gns
    
func connect_children(graph_node: CustomGraphNode) -> void:
    var connection_names: Array[String] = get_graph_connections_for(graph_node)
    for conn_idx in connection_names.size():
        var connected_graph_nodes: Array[GraphNode] = get_graph_connected_graph_nodes(graph_node, connection_names[conn_idx])
        for connected_gn in connected_graph_nodes:
            connect_node(graph_node.name, conn_idx, connected_gn.name, 0)
            connect_children(connected_gn)

func move_and_connect_children(asset_node_id: String, pos: Vector2) -> int:
    var graph_node: = editor.gn_lookup[asset_node_id]
    var asset_node: = an_lookup[asset_node_id]
    graph_node.position_offset = pos

    var child_pos: = pos + (Vector2.RIGHT * (graph_node.size.x + 40))
    var connection_names: Array[String] = asset_node.connection_list.duplicate()

    for conn_idx in connection_names.size():
        var conn_name: = connection_names[conn_idx]
        for connected_node_idx in asset_node.num_connected_asset_nodes(conn_name):
            var conn_an: = asset_node.get_connected_node(conn_name, connected_node_idx)
            if not conn_an:
                continue
            var conn_gn: = editor.gn_lookup[conn_an.an_node_id]
            if not conn_gn:
                print_debug("Warning: Graph Node for Asset Node %s not found" % conn_an.an_node_id)
                continue

            if conn_an.connection_list.size() > 0:
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

    var aux: = editor.asset_node_aux_data[at_asset_node.an_node_id]
    var this_gn: = editor.make_new_graph_node_for_an(at_asset_node, aux.position)
    new_graph_nodes.append(this_gn)

    for conn_name in get_graph_connections_for(this_gn):
        var connected_nodes: Array[HyAssetNode] = get_graph_connected_asset_nodes(this_gn, conn_name)
        for connected_asset_node in connected_nodes:
            new_graph_nodes.append_array(_recursive_new_graph_nodes(connected_asset_node, root_asset_node))
    return new_graph_nodes

func get_graph_connections_for(graph_node: CustomGraphNode) -> Array[String]:
    if editor.gn_is_special(graph_node):
        return graph_node.get_current_connection_list()
    else:
        var asset_node: = editor.get_gn_main_asset_node(graph_node)
        return asset_node.connection_list

func get_graph_connected_asset_nodes(graph_node: CustomGraphNode, conn_name: String) -> Array[HyAssetNode]:
    if editor.gn_is_special(graph_node):
        return graph_node.filter_child_connection_nodes(conn_name)
    else:
        var asset_node: = editor.get_gn_main_asset_node(graph_node)
        return asset_node.get_all_connected_nodes(conn_name)

func get_gn_own_asset_nodes(graph_node: CustomGraphNode, extra_asset_nodes: Array[HyAssetNode] = []) -> Array[HyAssetNode]:
    if editor.gn_is_special(graph_node):
        return graph_node.get_own_asset_nodes()
    else:
        return [safe_get_an_from_gn(graph_node, extra_asset_nodes)]

func get_internal_connections_for_gns(gns: Array[CustomGraphNode]) -> Array[Dictionary]:
    var internal_connections: Array[Dictionary] = []
    for gn in gns:
        for conn_info in raw_connections(gn):
            if conn_info["from_node"] == gn.name:
                var to_gn: = get_node(NodePath(conn_info["to_node"])) as CustomGraphNode
                if to_gn in gns:
                    internal_connections.append(conn_info)
    return internal_connections


func get_an_roots_within_set(asset_node_set: Array[HyAssetNode]) -> Array[HyAssetNode]:
    var root_ans: Array[HyAssetNode] = asset_node_set.duplicate()
    for parent_an in asset_node_set:
        for child_an in parent_an.connected_asset_nodes.values():
            if child_an in root_ans:
                root_ans.erase(child_an)
    return root_ans

func get_graph_connected_graph_nodes(graph_node: CustomGraphNode, conn_name: String) -> Array[GraphNode]:
    var connected_asset_nodes: Array[HyAssetNode] = get_graph_connected_asset_nodes(graph_node, conn_name)
    var connected_graph_nodes: Array[GraphNode] = []
    for connected_asset_node in connected_asset_nodes:
        connected_graph_nodes.append(editor.gn_lookup[connected_asset_node.an_node_id])
    return connected_graph_nodes

func get_child_node_of_class(parent: Node, class_names: Array[String]) -> Node:
    if parent.get_class() in class_names:
        return parent
    
    for child in parent.get_children():
        var found_node: = get_child_node_of_class(child, class_names)
        if found_node:
            return found_node
    return null

func update_all_ges_themes() -> void:
    for child in get_children():
        if child is CustomGraphNode:
            update_custom_gn_theme(child)
            child.update_port_colors()
        elif child is GraphFrame:
            update_group_theme(child)

func update_custom_gn_theme(graph_node: CustomGraphNode) -> void:
    var output_type: String = graph_node.theme_color_output_type
    if not output_type:
        return
    
    var theme_var_color: String = TypeColors.get_color_for_type(output_type)
    if ThemeColorVariants.has_theme_color(theme_var_color):
        graph_node.theme = ThemeColorVariants.get_theme_color_variant(theme_var_color)

func update_group_theme(_group: GraphFrame) -> void:
    # for now groups dont change themes based on type -> color assignments
    # they just have specific color names set as their accent color
    pass

var connection_cut_active: = false
var connection_cut_start_point: Vector2 = Vector2(0, 0)
var connection_cut_line: Line2D = null
var max_connection_cut_points: = 100000

func start_connection_cut(at_global_pos: Vector2) -> void:
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
        if popup_menu_root.new_gn_menu.visible and mouse_btn_event.is_pressed():
            popup_menu_root.close_all()
            if mouse_btn_event.button_index == MOUSE_BUTTON_LEFT:
                return

        if mouse_btn_event.button_index == MOUSE_BUTTON_RIGHT:
            if context_menu_ready and not mouse_btn_event.is_pressed():
                if not context_menu_target_node:
                    actually_right_click_nothing()
                elif context_menu_target_node is CustomGraphNode:
                    actually_right_click_gn(context_menu_target_node)
                elif context_menu_target_node is GraphFrame:
                    actually_right_click_group(context_menu_target_node)

            if mouse_btn_event.is_pressed():
                if mouse_btn_event.ctrl_pressed:
                    start_connection_cut(mouse_btn_event.global_position)
                else:
                    mouse_panning = true
                    if not context_menu_ready:
                        check_for_group_context_menu_click_start(mouse_btn_event)
                        if not context_menu_ready:
                            ready_context_menu_for(null)
            elif mouse_panning:
                mouse_panning = false
            elif connection_cut_active:
                cancel_context_menu()
                do_connection_cut()
        elif mouse_btn_event.button_index == MOUSE_BUTTON_LEFT:
            if connection_cut_active and mouse_btn_event.is_pressed():
                cancel_connection_cut()
                get_viewport().set_input_as_handled()
    if mouse_motion_event:
        if context_menu_ready:
            context_menu_movement_acc -= mouse_motion_event.relative.length()
            if context_menu_movement_acc <= 0:
                cancel_context_menu()

        if connection_cut_active:
            add_connection_cut_point(mouse_motion_event.global_position)
        elif mouse_panning:
            scroll_offset -= mouse_motion_event.relative

func check_for_group_context_menu_click_start(mouse_btn_event: InputEventMouseButton) -> void:
    var mouse_pos_offset: = local_pos_to_pos_offset(mouse_btn_event.position)
    for group in get_all_groups():
        var group_rect: = get_pos_offset_rect(group)
        if group_rect.has_point(mouse_pos_offset):
            ready_context_menu_for(group)

func get_all_groups() -> Array[GraphFrame]:
    var groups: Array[GraphFrame] = []
    for child in get_children():
        if child is GraphFrame:
            groups.append(child)
    return groups

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
    zoom_changed.emit(zoom)

func on_grid_toggled(grid_is_enabled: bool, grid_toggle_btn: Button) -> void:
    if grid_toggle_btn.disabled:
        return
    grid_logical_enabled = grid_is_enabled
    

func on_begin_node_move() -> void:
    moved_nodes_old_positions.clear()
    moved_groups_old_sizes.clear()
    cur_move_detached_nodes = false
    var detach_from_groups: bool = Util.is_shift_pressed()
    # Get nodes inclusive recusively of selected group's members (they stay unselected but are moved)
    var selected_for_move: Array[GraphElement] = get_inclusive_selected_ges()
    var moved_nodes: Array[GraphElement] = []

    # Fetch the parent group of all groups because we may need to cascade upwards because moving children updates the parent group's size
    var sel_nodes_groups: Dictionary[GraphElement, GraphFrame] = get_graph_elements_cur_groups(selected_for_move, true)

    var get_all_ancestors_of: = func(base: bool, ge: GraphElement, recurse: Callable) -> Array[GraphElement]:
        if ge not in sel_nodes_groups:
            if base:
                return []
            else:
                return [ge]
        var ret: Array[GraphElement] = []
        if not base:
            ret.append(ge)
        ret.append_array(recurse.call(false, sel_nodes_groups[ge], recurse))
        return ret

    for ge in selected_for_move:
        if not ge in moved_nodes:
            moved_nodes.append(ge)
        # Parent groups count as moved nodes because they may move and change size to expand to accomodate the new arrangement or with autoshrink
        # if the nodes are being detached
        # This needs to include all ancestor groups for the same reason
        if sel_nodes_groups.has(ge):
            for ancestor in get_all_ancestors_of.call(true, ge, get_all_ancestors_of):
                if not ancestor in moved_nodes:
                    moved_nodes.append(ancestor)

    # remember positions and group sizes before breaking group membership, because autoshrink will change sizes immediately
    for ge in moved_nodes:
        moved_nodes_old_positions[ge] = ge.position_offset
        if ge is GraphFrame:
            moved_groups_old_sizes[ge as GraphFrame] = ge.size

    # Finally, detach nodes/groups from their direct parent if the direct parent is not included in the selection
    for ge in moved_nodes:
        if detach_from_groups and sel_nodes_groups.has(ge):
            var parent_group: GraphFrame = sel_nodes_groups[ge]
            if parent_group not in selected_for_move:
                remove_ge_from_group(ge, parent_group, true)

func change_current_node_move_to_detach_mode() -> void:
    if not is_moving_nodes():
        push_warning("change_current_node_move_to_detach_mode: called while not moving nodes")
        return
    cur_move_detached_nodes = true
    var selected_inclusive: Array[GraphElement] = get_inclusive_selected_ges()
    var sel_nodes_groups: Dictionary[GraphElement, GraphFrame] = get_graph_elements_cur_groups(selected_inclusive)
    
    var groups_to_reset_positions: Dictionary[GraphElement, Vector2] = {}
    for moved_ge in moved_nodes_old_positions.keys():
        if moved_ge is GraphFrame and not moved_ge in selected_inclusive:
            groups_to_reset_positions[moved_ge] = moved_nodes_old_positions[moved_ge]
        if sel_nodes_groups.has(moved_ge):
            var parent_group: GraphFrame = sel_nodes_groups[moved_ge]
            if parent_group not in selected_inclusive:
                remove_ge_from_group(moved_ge, parent_group, true)
    
    # reset the positions and sizes of any groups that had been moved and resized by the current move to what they were before
    _set_offsets_and_group_sizes(groups_to_reset_positions, moved_groups_old_sizes)

## Do not use this, currently broken
func cancel_current_node_move() -> void:
    # TODO: Vanilla GraphEdit doesn't allow cancelling the current move, in order for this to actually work
    # we might need to prevent vanilla movement entirely and re-implement it inclusing all the snapping behavior etc
    # look into cheating by releasing focus to see if that works
    _set_offsets_and_group_sizes(moved_nodes_old_positions, moved_groups_old_sizes)
    cur_move_detached_nodes = false
    moved_nodes_old_positions.clear()
    moved_groups_old_sizes.clear()

## Return true if currently dragging nodes around with the mouse
func is_moving_nodes() -> bool:
    return moved_nodes_old_positions.size() > 0

func get_graph_elements_cur_groups(ges: Array[GraphElement], include_all_groups: bool = false) -> Dictionary[GraphElement, GraphFrame]:
    var cur_groups: Dictionary[GraphElement, GraphFrame] = {}
    var reverse_lookup_name: Dictionary[StringName, StringName] = {}
    var named_groups: Dictionary[String, GraphFrame] = {}
    for group in get_all_groups():
        named_groups[group.name] = group
        var group_members: Array[StringName] = get_attached_nodes_of_frame(group.name)
        for member_name in group_members:
            reverse_lookup_name[member_name] = group.name
    
    if include_all_groups:
        ges = ges.duplicate()
        ges.append_array(get_all_groups())

    for ge in ges:
        if ge.name in reverse_lookup_name:
            cur_groups[ge] = named_groups[reverse_lookup_name[ge.name]]
    return cur_groups

func get_graph_elements_cur_group_relations(ges: Array[GraphElement]) -> Array[Dictionary]:
    var group_relations: Array[Dictionary] = []
    var cur_groups_of_ges: Dictionary[GraphElement, GraphFrame] = get_graph_elements_cur_groups(ges)
    var the_groups: Array[GraphFrame] = []
    for ge in ges:
        if ge is GraphFrame:
            the_groups.append(ge)
    group_relations.append_array(get_groups_cur_relations(the_groups))
    for ge in ges:
        if cur_groups_of_ges.has(ge):
            if cur_groups_of_ges[ge] in the_groups:
                # already added by adding all group relations above
                continue
            group_relations.append({
                "group": cur_groups_of_ges[ge],
                "member": ge,
            })
    return group_relations

func get_groups_cur_relations(groups: Array[GraphFrame]) -> Array[Dictionary]:
    var group_relations: Array[Dictionary] = []
    for group in groups:
        var group_member_names: Array[StringName] = get_attached_nodes_of_frame(group.name)
        for mem_name in group_member_names:
            var mem: = get_node(NodePath(mem_name)) as GraphElement
            if mem:
                group_relations.append({
                    "group": group,
                    "member": mem,
                })
    return group_relations

func on_end_node_move() -> void:
    _end_node_move_deferred.call_deferred()

func _end_node_move_deferred() -> void:
    var selected_nodes: Array[GraphElement] = get_selected_ges()
    # For now I'm keeping the undo step of moving and inserting into the connection separate
    create_move_nodes_undo_step(selected_nodes)
    if selected_nodes.size() == 1 and selected_nodes[0] is CustomGraphNode:
        var gn_rect: = selected_nodes[0].get_global_rect().grow(-8).abs()
        var connections_overlapped: = get_connections_intersecting_with_rect(gn_rect)
        if try_inserting_graph_node_into_connections(selected_nodes[0], connections_overlapped):
            return

func try_inserting_graph_node_into_connections(gn: CustomGraphNode, connections_overlapped: Array[Dictionary]) -> bool:
    if gn.node_type_schema.get("no_output", false):
        return false
    
    # Dont try to patch in if you already have an output connection
    if raw_out_connections(gn).size() > 0:
        return false

    var gn_output_type: String = gn.node_type_schema.get("output_value_type", "")
    var first_valid_input_port: int = -1

    var schema_connections: Dictionary = gn.node_type_schema.get("connections", {})

    for conn_idx in schema_connections.size():
        if schema_connections.values()[conn_idx]["value_type"] == gn_output_type:
            first_valid_input_port = conn_idx
            break
    if first_valid_input_port == -1:
        return false
    
    for conn_info in connections_overlapped:
        # ignore my own connections
        if conn_info["to_node"] == gn.name or conn_info["from_node"] == gn.name:
            continue
        var conn_value_type: String = get_conn_info_value_type(conn_info)
        if conn_value_type != gn_output_type:
            continue
        
        # Now actually do the connection change
        multi_connection_change = true
        remove_connection(conn_info)
        add_connection({"to_node": gn.name, "to_port": 0}.merged(conn_info))
        add_connection({"from_node": gn.name, "from_port": first_valid_input_port}.merged(conn_info))
        multi_connection_change = false
        create_undo_connection_change_step()
        return true
    return false
    
func get_conn_info_value_type(conn_info: Dictionary) -> String:
    var to_gn: = get_node(NodePath(conn_info["to_node"])) as CustomGraphNode
    if not to_gn:
        push_error("get_conn_info_value_type: to node %s not found or is not CustomGraphNode" % conn_info["to_node"])
    return to_gn.node_type_schema["output_value_type"]

func _set_ges_offsets(new_positions: Dictionary[GraphElement, Vector2]) -> void:
    for ge in new_positions.keys():
        ge.position_offset = new_positions[ge]

func _set_offsets_and_group_sizes(ge_positions: Dictionary[GraphElement, Vector2], group_sizes: Dictionary[GraphFrame, Vector2]) -> void:
    _set_ges_offsets(ge_positions)
    #var sorted_for_resize: = _sort_groups_by_heirarchy_reversed(group_sizes.keys())
    for group: GraphFrame in group_sizes.keys():
        if group not in ge_positions:
            continue
        group.position = ge_positions[group as GraphElement]
        group.size = group_sizes[group]
    for group: GraphFrame in group_sizes.keys():
        # This forces the native graph edit code to resize the graph frame inclusing covering group members and autoshrikning if enabled
        # it will still do this without emitting the signal but it will blink out of existence for a frame
        group.autoshrink_changed.emit(group.size)

func undo_redo_set_offsets_and_sizes(move_ges: Dictionary[GraphElement, Vector2], resize_ges: Dictionary[GraphElement, Vector2]) -> void:
    _set_ges_offsets(move_ges)
    #var sorted_for_resize: = _sort_groups_by_heirarchy_reversed(group_sizes.keys())
    for resized_ge in resize_ges.keys():
        resized_ge.size = resize_ges[resized_ge]

    for ge: GraphElement in resize_ges.keys():
        if not ge is GraphFrame:
            continue
        # This forces the native graph edit code to resize the graph frame inclusing covering group members and autoshrikning if enabled
        # it will still do this without emitting the signal but it will blink out of existence for a frame
        ge.autoshrink_changed.emit(ge.size)

func _sort_groups_by_heirarchy_reversed(group_list: Array) -> Array[GraphFrame]:
    var group_to_parent: = get_graph_elements_cur_groups(Array(group_list, TYPE_OBJECT, &"GraphElement", null))
    
    var safety = 100000
    var unsorted: = group_list.duplicate()
    var sorted_groups: Array[GraphFrame] = []
    while unsorted.size() > 0 and safety > 0:
        for group in unsorted.duplicate():
            if not group_to_parent.has(group) or group_to_parent[group] not in unsorted:
                sorted_groups.push_front(group)
                unsorted.erase(group)
        safety -= 1
    return sorted_groups

func _break_group_relations(group_relations: Array[Dictionary]) -> void:
    for group_relation in group_relations:
        _break_group_relation(group_relation)

func remove_ge_from_group(ge: GraphElement, group: GraphFrame, with_undo: bool) -> void:
    var group_relation: = {"group": group, "member": ge}
    _break_group_relation(group_relation)
    if with_undo:
        cur_removed_group_relations.append(group_relation)

func _break_group_relation(group_relation: Dictionary) -> void:
    var group: = group_relation["group"] as GraphFrame
    var member_elements: = get_attached_nodes_of_frame(group.name)
    var member_graph_element: = group_relation["member"] as GraphElement
    if member_graph_element.name in member_elements:
        detach_graph_element_from_frame(member_graph_element.name)
        if member_graph_element is CustomGraphNode:
            member_graph_element.update_is_in_graph_group(false)

func add_group_relations(group_relations: Array[Dictionary], with_undo: bool) -> void:
    _assign_group_relations(group_relations)
    if with_undo:
        cur_added_group_relations.append_array(group_relations)

func _assign_group_relations(group_relations: Array[Dictionary]) -> void:
    for group_relation in group_relations:
        _assign_group_relation(group_relation)

func add_ge_to_group(ge: GraphElement, group: GraphFrame, with_undo: bool) -> void:
    _assign_group_relation({"group": group, "member": ge})
    if with_undo:
        cur_added_group_relations.append({"group": group, "member": ge})

func add_ges_to_group(ges: Array[GraphElement], group: GraphFrame) -> void:
    var ge_names: Array = []
    for ge in ges:
        ge_names.append(ge.name)
    _attach_ge_names_to_group(ge_names, group.name)

func _attach_ge_names_to_group(ge_names: Array, group_name: StringName) -> void:
    var the_group: = get_node(NodePath(group_name)) as GraphFrame
    for ge_name in ge_names:
        attach_graph_element_to_frame(ge_name, group_name)
        var ge: = get_node(NodePath(ge_name)) as GraphElement
        if ge is CustomGraphNode:
            ge.update_is_in_graph_group(true, the_group.theme)

func _assign_group_relation(group_relation: Dictionary) -> void:
    var group: = group_relation["group"] as GraphFrame
    var member_graph_element: = group_relation["member"] as GraphElement
    attach_graph_element_to_frame(member_graph_element.name, group.name)
    if member_graph_element is CustomGraphNode:
        member_graph_element.update_is_in_graph_group(true, group.theme)

func refresh_graph_elements_in_frame_status() -> void:
    var all_ges: Array[GraphElement] = get_all_ges()
    var ges_groups: Dictionary[GraphElement, GraphFrame] = get_graph_elements_cur_groups(all_ges)
    for ge in all_ges:
        if ge is CustomGraphNode:
            var the_group: = ges_groups.get(ge, null) as GraphFrame
            var the_group_theme: = the_group.theme if the_group else null
            ge.update_is_in_graph_group(ges_groups.has(ge), the_group_theme)

## Undo/Redo registering for actions which add or remove nodes and connections between nodes
## This method does not do any adding or removing itself, so that still needs to be done before or after calling
## before calling, set cur_added_connections, cur_removed_connections, cur_connection_added_ges, and cur_connection_removed_ges
func create_undo_connection_change_step() -> void:
    unedited = false
    var added_ges: Array[GraphElement] = cur_connection_added_ges.duplicate()
    var removed_ges: Array[GraphElement] = cur_connection_removed_ges.duplicate()
    var added_conns: Array[Dictionary] = cur_added_connections.duplicate_deep()
    var removed_conns: Array[Dictionary] = cur_removed_connections.duplicate_deep()
    cur_connection_added_ges.clear()
    cur_connection_removed_ges.clear()
    cur_added_connections.clear()
    cur_removed_connections.clear()
    
    if added_ges.size() > 0 and removed_ges.size() > 0:
        print_debug("Trying to add and remove graph nodes in the same undo step")
        return
    
    var undo_step_name: = "Connection Change"
    if added_ges.size() > 0:
        undo_step_name = "Add Nodes With Connections"
    elif removed_ges.size() > 0:
        undo_step_name = "Remove Nodes (With Connections)"

    undo_manager.create_action(undo_step_name)
    
    # careful of the order of operations
    # we make sure to add relevant nodes before trying to connect them, and remove them after removing their connections
    # REDOS
    if added_ges.size() > 0:
        var the_ans: Dictionary[GraphElement, HyAssetNode] = {}
        for the_ge in added_ges:
            if the_ge.get_meta("hy_asset_node_id", ""):
                var the_an: HyAssetNode = an_lookup.get(the_ge.get_meta("hy_asset_node_id", ""))
                the_ans[the_ge] = the_an
        undo_manager.add_do_method(redo_add_ges.bind(added_ges, the_ans))

    if added_conns.size() > 0:
        undo_manager.add_do_method(add_multiple_connections.bind(added_conns, false))
    if removed_conns.size() > 0:
        undo_manager.add_do_method(remove_multiple_connections.bind(removed_conns, false))

    if removed_ges.size() > 0:
        undo_manager.add_do_method(redo_remove_ges.bind(removed_ges))
        
        cur_removed_group_relations = get_graph_elements_cur_group_relations(removed_ges)
    
    # UNDOS
    if removed_ges.size() > 0:
        var the_ans: Dictionary[GraphElement, HyAssetNode] = {}
        for the_ge in removed_ges:
            var an_id: String = the_ge.get_meta("hy_asset_node_id", "")
            if an_id:
                var the_an: HyAssetNode = an_lookup.get(an_id)
                the_ans[the_ge] = the_an
        undo_manager.add_undo_method(undo_remove_ges.bind(removed_ges, the_ans))

    if added_conns.size() > 0:
        undo_manager.add_undo_method(remove_multiple_connections.bind(added_conns, false))
    if removed_conns.size() > 0:
        undo_manager.add_undo_method(add_multiple_connections.bind(removed_conns, false))

    if added_ges.size() > 0:
        undo_manager.add_undo_method(undo_add_ges.bind(added_ges))
    
    # Add group membership changes from adding or removing nodes
    if removed_ges.size() > 0:
        add_group_membership_to_cur_undo_action(true, false)
    elif added_ges.size() > 0:
        add_group_membership_to_cur_undo_action(false, true)
    
    undo_manager.commit_action(false)

func remove_ges_with_connections_and_undo(ges_to_remove: Array[GraphElement]) -> void:
    if (cur_connection_added_ges.size() > 0 or
        cur_connection_removed_ges.size() > 0 or
        cur_added_connections.size() > 0 or
        cur_removed_connections.size() > 0):
            push_error("Trying to remove graph nodes during a pending undo step")
            return

    var connections_needing_removal: Array[Dictionary] = []
    for graph_element in ges_to_remove:
        var gn: = graph_element as CustomGraphNode
        if not gn:
            continue
        var gn_connections: Array[Dictionary] = raw_connections(gn)
        for conn_info in gn_connections:
            if conn_info["from_node"] == gn.name:
                # exclude outgoing connections to other removed nodes (they would be duplicates of the below case)
                var to_gn: = get_node(NodePath(conn_info["to_node"])) as GraphElement
                if to_gn in ges_to_remove:
                    continue
                connections_needing_removal.append(conn_info)
            elif conn_info["to_node"] == gn.name:
                connections_needing_removal.append(conn_info)
            else:
                print_debug("connection neither from nor to the node it was retreived by? node: %s, connection info: %s" % [gn.name, conn_info])

    if not connections_needing_removal:
        remove_unconnected_ges_with_undo(ges_to_remove)
    else:
        cur_connection_removed_ges.append_array(ges_to_remove)
        cur_removed_connections.append_array(connections_needing_removal)
        remove_multiple_connections(connections_needing_removal, false)
        create_undo_connection_change_step()
        remove_multiple_ges_without_undo(ges_to_remove)

func remove_multiple_ges_without_undo(ges_to_remove: Array[GraphElement]) -> void:
    for ge in ges_to_remove:
        remove_ge_without_undo(ge)

func remove_ge_without_undo(ge: GraphElement) -> void:
    var an_id: String = ge.get_meta("hy_asset_node_id", "")
    if an_id:
        var asset_node: HyAssetNode = an_lookup.get(an_id, null)
        if asset_node:
            remove_asset_node(asset_node)
    remove_graph_element_child(ge)

func remove_unconnected_ges_with_undo(ges_to_remove: Array[GraphElement]) -> void:
    unedited = false
    undo_manager.create_action("Remove Graph Nodes")

    var removed_asset_nodes: Dictionary[GraphElement, HyAssetNode] = {}
    for the_ge in ges_to_remove:
        if the_ge.get_meta("hy_asset_node_id", ""):
            removed_asset_nodes[the_ge] = an_lookup[the_ge.get_meta("hy_asset_node_id")]
    
    var removed_ge_list: = ges_to_remove.duplicate()

    undo_manager.add_do_method(redo_remove_ges.bind(removed_ge_list))
    
    undo_manager.add_undo_method(undo_remove_ges.bind(removed_ge_list, removed_asset_nodes))
    
    cur_removed_group_relations = get_graph_elements_cur_group_relations(ges_to_remove)
    add_group_membership_to_cur_undo_action(true)

    undo_manager.commit_action(false)
    remove_multiple_ges_without_undo(ges_to_remove)
    refresh_graph_elements_in_frame_status()

func remove_groups_only_with_undo(groups_to_remove: Array[GraphFrame]) -> void:
    unedited = false
    var removed_ge_list: Array[GraphElement] = []
    var group_relations: = get_groups_cur_relations(groups_to_remove)
    removed_ge_list.append_array(groups_to_remove)
    undo_manager.create_action("Remove Groups")

    undo_manager.add_do_method(redo_remove_ges.bind(removed_ge_list))

    # just because we need the typed version of the dictionary
    var rm_an: Dictionary[GraphElement, HyAssetNode] = {}
    undo_manager.add_undo_method(undo_remove_ges.bind(removed_ge_list, rm_an))
    
    cur_removed_group_relations = group_relations
    add_group_membership_to_cur_undo_action(true)

    undo_manager.commit_action(true)

func create_add_new_ge_undo_step(the_new_ge: GraphElement) -> void:
    create_add_new_ges_undo_step([the_new_ge])

func create_add_new_ges_undo_step(new_ges: Array[GraphElement]) -> void:
    unedited = false
    undo_manager.create_action("Add New Graph Nodes")
    var added_asset_nodes: Dictionary[GraphElement, HyAssetNode] = {}
    for the_ge in new_ges:
        var an_id: String = the_ge.get_meta("hy_asset_node_id", "")
        if an_id:
            added_asset_nodes[the_ge] = an_lookup[an_id]

    undo_manager.add_do_method(redo_add_ges.bind(new_ges, added_asset_nodes))
    
    undo_manager.add_undo_method(undo_add_ges.bind(new_ges))

    undo_manager.commit_action(false)

func create_move_nodes_undo_step(moved_nodes: Array[GraphElement]) -> void:
    unedited = false
    if moved_nodes.size() == 0:
        return
    
    var old_positions: Dictionary[GraphElement, Vector2] = moved_nodes_old_positions.duplicate()
    var old_group_sizes: Dictionary[GraphFrame, Vector2] = moved_groups_old_sizes.duplicate()
    moved_nodes_old_positions.clear()
    moved_groups_old_sizes.clear()
    cur_move_detached_nodes = false

    var new_positions: Dictionary[GraphElement, Vector2] = {}
    var new_group_sizes: Dictionary[GraphFrame, Vector2] = {}
    for ge in moved_nodes:
        new_positions[ge] = ge.position_offset
        if ge is GraphFrame:
            new_group_sizes[ge as GraphFrame] = ge.size
    undo_manager.create_action("Move Nodes")

    # TODO: Positions and group sizes needs to also be handled every time add_group_membership_to_cur_undo_action is called
    # instead of just here in move nodes undo step
    var removed_group_relations: Array[Dictionary] = cur_removed_group_relations.duplicate_deep()
    var added_group_relations: Array[Dictionary] = cur_added_group_relations.duplicate_deep()
    cur_removed_group_relations.clear()
    cur_added_group_relations.clear()
    add_group_membership_pre_move_undo_actions(removed_group_relations, added_group_relations)

    undo_manager.add_do_method(_set_offsets_and_group_sizes.bind(new_positions, new_group_sizes))

    undo_manager.add_undo_method(_set_offsets_and_group_sizes.bind(old_positions, old_group_sizes))
    
    add_group_membership_post_move_undo_actions(added_group_relations, removed_group_relations)

    undo_manager.commit_action(false)

## Add appropriate bindings for undoing/redoing group membership changes to an existing undo, call after all other steps are added
## If removing nodes entirely, set for_removal to true, for adding nodes, set for_adding to true
func add_group_membership_to_cur_undo_action(for_removal: bool = false, for_adding: bool = false) -> void:
    var removed_group_relations: Array[Dictionary] = cur_removed_group_relations.duplicate_deep()
    var added_group_relations: Array[Dictionary] = cur_added_group_relations.duplicate_deep()
    
    cur_removed_group_relations.clear()
    cur_added_group_relations.clear()
    
    # if graph relations are removed because a node is removed, it doesn't need to be explicitly redone,
    # since re-doing node removal will already remove the node from the group.
    # it actually makes the order of operations tougher, it will error if trying to remove an already removed node from a group, so I'm just skipping it
    if removed_group_relations.size() > 0 and not for_removal:
        undo_manager.add_do_method(_break_group_relations.bind(removed_group_relations))
    if added_group_relations.size() > 0:
        undo_manager.add_do_method(_assign_group_relations.bind(added_group_relations))
    undo_manager.add_do_method(refresh_graph_elements_in_frame_status)

    if added_group_relations.size() > 0:
        undo_manager.add_undo_method(_break_group_relations.bind(added_group_relations))
    if removed_group_relations.size() > 0 and not for_adding:
        undo_manager.add_undo_method(_assign_group_relations.bind(removed_group_relations))
    undo_manager.add_undo_method(refresh_graph_elements_in_frame_status)

func add_group_membership_pre_move_undo_actions(removed_relations: Array[Dictionary], added_relations: Array[Dictionary]) -> void:
    if removed_relations.size() > 0:
        undo_manager.add_do_method(_break_group_relations.bind(removed_relations))
    if added_relations.size() > 0:
        undo_manager.add_undo_method(_break_group_relations.bind(added_relations))

func add_group_membership_post_move_undo_actions(added_relations: Array[Dictionary], removed_relations: Array[Dictionary]) -> void:
    if added_relations.size() > 0:
        undo_manager.add_do_method(_assign_group_relations.bind(added_relations))
        undo_manager.add_do_method(refresh_graph_elements_in_frame_status)
    if removed_relations.size() > 0:
        undo_manager.add_undo_method(_assign_group_relations.bind(removed_relations))
        undo_manager.add_undo_method(refresh_graph_elements_in_frame_status)

func undo_remove_ges(the_ges: Array[GraphElement], the_ans: Dictionary[GraphElement, HyAssetNode]) -> void:
    for the_ge in the_ges:
        _undo_remove_ge(the_ge, the_ans.get(the_ge, null))

func _undo_remove_ge(the_graph_element: GraphElement, the_asset_node: HyAssetNode) -> void:
    if the_asset_node:
        assert(the_graph_element is GraphNode, "Graph element with asset node must be a GraphNode")
        _undo_redo_add_gn_and_an(the_graph_element, the_asset_node)
    else:
        _undo_redo_add_ge(the_graph_element)

func redo_add_ges(the_ges: Array[GraphElement], the_ans: Dictionary[GraphElement, HyAssetNode]) -> void:
    for the_ge in the_ges:
        _redo_add_graph_element(the_ge, the_ans.get(the_ge, null))

func _redo_add_graph_element(the_graph_element: GraphElement, the_asset_node: HyAssetNode) -> void:
    if the_asset_node:
        assert(the_graph_element is GraphNode, "Graph element with asset node must be a GraphNode")
        _undo_redo_add_gn_and_an(the_graph_element as GraphNode, the_asset_node)
    else:
        _undo_redo_add_ge(the_graph_element)

func _undo_redo_add_gn_and_an(the_graph_node: GraphNode, the_asset_node: HyAssetNode) -> void:
    _register_asset_node(the_asset_node)
    editor.gn_lookup[the_asset_node.an_node_id] = the_graph_node
    add_graph_node_child(the_graph_node)

func _undo_redo_add_ge(the_graph_element: GraphElement) -> void:
    add_graph_element_child(the_graph_element)
    if the_graph_element is GraphFrame:
        bring_group_to_front(the_graph_element)

func redo_remove_ges(the_ges: Array[GraphElement]) -> void:
    for the_ge in the_ges:
        _redo_remove_ge(the_ge)

func _redo_remove_ge(the_graph_element: GraphElement) -> void:
    _undo_redo_remove_ge(the_graph_element)

func undo_add_ges(the_ges: Array[GraphElement]) -> void:
    for the_ge in the_ges:
        undo_add_graph_element(the_ge)

func undo_add_graph_element(the_graph_element: GraphElement) -> void:
    _undo_redo_remove_ge(the_graph_element)

func _undo_redo_remove_ge(the_graph_element: GraphElement) -> void:
    if the_graph_element.get_meta("hy_asset_node_id", ""):
        var an_id: String = the_graph_element.get_meta("hy_asset_node_id", "")
        var the_asset_node: HyAssetNode = an_lookup[an_id]
        remove_asset_node(the_asset_node)
    remove_graph_element_child(the_graph_element)

func undo_redo_add_ges(the_ges: Array[GraphElement]) -> void:
    for adding_ge in the_ges:
        add_graph_element_child(adding_ge)

func undo_redo_remove_ges(the_ges: Array[GraphElement]) -> void:
    for removing_ge in the_ges:
        remove_graph_element_child(removing_ge)

func sort_all_an_connections() -> void:
    for an in all_asset_nodes:
        an.sort_connections_by_gn_pos(editor.gn_lookup)
    
func get_dissolve_info(graph_node: GraphNode) -> Dictionary:
    var in_ports_connected: Array[int] = []
    var in_port_connection_count: Dictionary[int, int] = {}
    var dissolve_info: Dictionary = {
        "has_output_connection": false,
        "output_to_gn_name": "",
        "output_to_port_idx": -1,
        "in_ports_connected": in_ports_connected,
        "in_port_connection_count": in_port_connection_count,
    }

    var all_gn_connections: Array[Dictionary] = raw_connections(graph_node)
    for conn_info in all_gn_connections:
        if conn_info["from_node"] == graph_node.name:
            if not in_ports_connected.has(conn_info["from_port"]):
                in_ports_connected.append(conn_info["from_port"])
                in_port_connection_count[conn_info["from_port"]] = 1
            else:
                in_port_connection_count[conn_info["from_port"]] += 1
        elif conn_info["to_node"] == graph_node.name:
            dissolve_info["has_output_connection"] = true
            dissolve_info["output_to_gn_name"] = conn_info["from_node"]
            dissolve_info["output_to_port_idx"] = conn_info["from_port"]
    return dissolve_info

func can_dissolve_gn(graph_node: CustomGraphNode) -> bool:
    if not graph_node.get_meta("hy_asset_node_id", ""):
        return false
    
    var dissolve_info: = get_dissolve_info(graph_node)
    if not dissolve_info["has_output_connection"] or dissolve_info["in_ports_connected"].size() == 0:
        return false
    
    var output_value_type: String = graph_node.node_type_schema.get("output_value_type", "")
    if not output_value_type:
        return true
    
    var connected_connections_types: Array[String] = []
    for conn_idx in dissolve_info["in_ports_connected"]:
        var conn_type: String = graph_node.node_type_schema["connections"].values()[conn_idx].get("value_type", "")
        connected_connections_types.append(conn_type)
    
    return output_value_type in connected_connections_types

func dissolve_gn_with_undo(graph_node: CustomGraphNode) -> void:
    var dissolve_info: = get_dissolve_info(graph_node)
    if not graph_node.get_meta("hy_asset_node_id", "") or not dissolve_info["has_output_connection"]:
        print_debug("Dissolve: node %s is not an asset node or has no output connection" % graph_node.name)
        _delete_request([graph_node.name])
        return
    
    var cur_schema: = graph_node.node_type_schema
    var val_type: String = cur_schema.get("output_value_type", "")
    var output_to_gn: = get_node(NodePath(dissolve_info["output_to_gn_name"])) as CustomGraphNode
    if not output_to_gn:
        push_error("Dissolve: output to node %s not found or is not CustomGraphNode" % dissolve_info["output_to_gn_name"])
        _delete_request([graph_node.name])
        return
    
    assert(output_to_gn.node_type_schema, "Dissolve: output to node %s has no schema set" % output_to_gn.name)
    
    var out_to_connection_schema: Dictionary = output_to_gn.node_type_schema.get("connections", {})
    var out_conn_idx: int = dissolve_info["output_to_port_idx"]
    var is_multi: bool = out_to_connection_schema.values()[out_conn_idx].get("multi", false)
    
    var cur_asset_node: HyAssetNode = an_lookup.get(graph_node.get_meta("hy_asset_node_id", ""), null)
    assert(cur_asset_node, "Dissolve: current asset node not found")
    # Sort asset node connections so the first one found if the out target isn't a multi connect is deterministic
    cur_asset_node.sort_connections_by_gn_pos(editor.gn_lookup)
    
    multi_connection_change = true
    for in_port_idx in dissolve_info["in_ports_connected"]:
        var conn_schema: Dictionary = cur_schema.get("connections", {}).values()[in_port_idx]
        var in_val_type: String = conn_schema["value_type"]
        if val_type and in_val_type != val_type:
            continue
        
        var conn_name: = cur_asset_node.connection_list[in_port_idx]
        var connected_graph_nodes: Array[GraphNode] = get_graph_connected_graph_nodes(graph_node, conn_name)
        var connected_one: bool = false
        for in_gn in connected_graph_nodes:
            connected_one = true
            _remove_connection(graph_node.name, in_port_idx, in_gn.name, 0)
            _add_connection(output_to_gn.name, out_conn_idx, in_gn.name, 0)
            if not is_multi:
                break
        if not is_multi and connected_one:
            break
    
    var leftover_connections: = raw_connections(graph_node)
    remove_multiple_connections(leftover_connections)
    
    multi_connection_change = false

    cur_connection_removed_ges.append(graph_node)
    create_undo_connection_change_step()
    remove_ge_without_undo(graph_node)

func cut_all_connections_with_undo(graph_node: CustomGraphNode) -> void:
    var all_connections: Array[Dictionary] = raw_connections(graph_node)
    remove_multiple_connections(all_connections)

func _on_graph_node_right_clicked(graph_node: CustomGraphNode) -> void:
    if connection_cut_active:
        return
    if not graph_node.selectable:
        return
    ready_context_menu_for(graph_node)

func ready_context_menu_for(for_node: Node) -> void:
    context_menu_movement_acc = 24
    context_menu_target_node = for_node
    context_menu_ready = true

func _on_graph_node_titlebar_double_clicked(graph_node: CustomGraphNode) -> void:
    select_subtree(graph_node, ANESettings.select_subtree_is_greedy)

## Select all nodes connected to the input side of this graph node
## If greedy = false (default) will only select groups if all of it's members were also selected
## If greedy = true will select any group that contains at least one of the nodes in the subtree and will also select all nodes in that group
## Never selects outer groups of the group the root node is in,
## the group the root node is in is only selected if all of it's members (inclusive) are selected even if greedy is true
func select_subtree(root_gn: CustomGraphNode, greedy: bool = false) -> void:
    deselect_all()
    var subtree_gns: Array[CustomGraphNode] = get_subtree_gns(root_gn)
    select_gns(subtree_gns)
    
    # Select any groups that you've selected all the members of
    var all_groups: = get_all_groups()
    var group_of_tree_root: GraphFrame = get_element_frame(root_gn.name)
    for group in all_groups:
        var inclusive_group_members: Array[GraphElement] = get_recursive_group_members(group)
        if inclusive_group_members.size() == 0:
            continue
        var is_outer_group_of_root: bool = false
        for member in inclusive_group_members:
            if member == group_of_tree_root:
                is_outer_group_of_root = true
                break
        if is_outer_group_of_root:
            continue

        var all_selected: bool = true
        var any_selected: bool = false
        for member in inclusive_group_members:
            if member is GraphFrame:
                continue
            if not member.selected:
                all_selected = false
                if not greedy:
                    break
            else:
                any_selected = true
        if group == group_of_tree_root:
            if all_selected:
                group.selected = true
        else:
            if (greedy and any_selected) or (not greedy and all_selected):
                group.selected = true
    
    if greedy:
        for selected_group in get_selected_groups():
            var inclusive_selected_members: Array[GraphElement] = get_recursive_group_members(selected_group)
            for member in inclusive_selected_members:
                if not member.selected:
                    member.selected = true

func get_subtree_gns(graph_node: CustomGraphNode) -> Array[CustomGraphNode]:
    var subtree_gns: Array[CustomGraphNode] = [graph_node]
    var in_connections: Array[Dictionary] = raw_in_connections(graph_node)
    var safety: int = 100000
    while in_connections.size() > 0:
        var old_conns: = in_connections.duplicate()
        in_connections.clear()
        for conn_info in old_conns:
            var subtree_gn: = get_node(NodePath(conn_info["to_node"])) as CustomGraphNode
            if not subtree_gn or subtree_gns.has(subtree_gn):
                continue
            subtree_gns.append(subtree_gn)
            in_connections.append_array(raw_in_connections(subtree_gn))
        
        safety -= 1
        if safety <= 0:
            push_error("get_subtree_gns: Safety limit reached, aborting")
            break
    return subtree_gns


func cancel_context_menu() -> void:
    reset_context_menu_target()

func reset_context_menu_target() -> void:
    context_menu_target_node = null
    context_menu_ready = false

func actually_right_click_gn(graph_node: CustomGraphNode) -> void:
    reset_context_menu_target()
    if not graph_node.selected:
        deselect_all()
        set_selected(graph_node)
    
    var is_asset_node: bool = graph_node.get_meta("hy_asset_node_id", "") != ""

    var context_menu: PopupMenu = PopupMenu.new()
    context_menu.id_pressed.connect(on_node_context_menu_id_pressed.bind(graph_node))

    context_menu.name = "NodeContextMenu"
    
    context_menu.add_item("Edit Title", CHANE_AssetNodeEditor.ContextMenuItems.EDIT_TITLE)
    context_menu.add_separator()
    
    set_context_menu_common_options(context_menu)
    
    if is_asset_node:
        context_menu.add_item("Dissolve Node", CHANE_AssetNodeEditor.ContextMenuItems.DISSOLVE_NODES)
        if not can_dissolve_gn(graph_node):
            var dissolve_idx: int = context_menu.get_item_index(CHANE_AssetNodeEditor.ContextMenuItems.DISSOLVE_NODES)
            context_menu.set_item_disabled(dissolve_idx, true)
        
        context_menu.add_item("Cut All Connections", CHANE_AssetNodeEditor.ContextMenuItems.BREAK_CONNECTIONS)
    
    context_menu.add_separator()
    set_context_menu_select_options(context_menu, true, false)

    add_child(context_menu, true)

    context_menu.position = get_popup_pos_at_mouse()
    context_menu_pos_offset = get_mouse_pos_offset()
    context_menu.popup()

func actually_right_click_group(group: GraphFrame) -> void:
    reset_context_menu_target()
    if not group.selected:
        deselect_all()
        group.selected = true
    var context_menu: PopupMenu = PopupMenu.new()
    context_menu.id_pressed.connect(on_node_context_menu_id_pressed.bind(group))
    context_menu.name = "GroupContextMenu"
    
    context_menu.add_item("Edit Group Title", CHANE_AssetNodeEditor.ContextMenuItems.EDIT_GROUP_TITLE)
    var change_group_color_submenu: PopupMenu = get_color_name_menu()
    change_group_color_submenu.index_pressed.connect(on_change_group_color_name_index_pressed.bind(change_group_color_submenu, group))
    context_menu.add_submenu_node_item("Change Group Accent Color", change_group_color_submenu, CHANE_AssetNodeEditor.ContextMenuItems.CHANGE_GROUP_COLOR)

    context_menu.add_separator()
    
    set_context_menu_new_node_options(context_menu)
    var new_group_idx: int = context_menu.get_item_index(CHANE_AssetNodeEditor.ContextMenuItems.CREATE_NEW_GROUP)
    context_menu.set_item_text(new_group_idx, "Create New Inner Group")
    context_menu.add_separator()
    
    set_context_menu_common_options(context_menu)
    
    context_menu.add_separator()
    set_context_menu_select_options(context_menu, false, true)
    
    var multiple_groups_selected: bool = get_selected_groups().size() > 1
    if not multiple_groups_selected:
        var is_shrinkwrap_enabled: bool = group.autoshrink_enabled
        if is_shrinkwrap_enabled:
            context_menu.add_item("Disable Shrinkwrap", CHANE_AssetNodeEditor.ContextMenuItems.SET_GROUP_NO_SHRINKWRAP)
        else:
            context_menu.add_item("Enable Shrinkwrap", CHANE_AssetNodeEditor.ContextMenuItems.SET_GROUP_SHRINKWRAP)
    else:
        context_menu.add_item("Enable Shrinkwrap for Selected Groups", CHANE_AssetNodeEditor.ContextMenuItems.SET_GROUP_SHRINKWRAP)
        context_menu.add_item("Disable Shrinkwrap for Selected Groups", CHANE_AssetNodeEditor.ContextMenuItems.SET_GROUP_NO_SHRINKWRAP)
    
    add_child(context_menu, true)
    
    context_menu.position = get_popup_pos_at_mouse()
    context_menu_pos_offset = get_mouse_pos_offset()
    context_menu.popup()

func actually_right_click_nothing() -> void:
    reset_context_menu_target()
    var context_menu: PopupMenu = PopupMenu.new()
    context_menu.id_pressed.connect(on_node_context_menu_id_pressed.bind(null))
    context_menu.name = "NothingContextMenu"
    
    if not loaded:
        context_menu.add_item("New File", CHANE_AssetNodeEditor.ContextMenuItems.NEW_FILE)
        return
    
    set_context_menu_new_node_options(context_menu)
    context_menu.add_separator()
    
    var paste_plural_s: = "s" if copied_nodes.size() > 1 else ""
    context_menu.add_item("Paste Nodes" + paste_plural_s, CHANE_AssetNodeEditor.ContextMenuItems.PASTE_NODES)
    if not check_if_can_paste():
        var paste_idx: int = context_menu.get_item_index(CHANE_AssetNodeEditor.ContextMenuItems.PASTE_NODES)
        context_menu.set_item_disabled(paste_idx, true)
    
    add_child(context_menu, true)
    
    context_menu.add_separator()
    set_context_menu_select_options(context_menu, false, false)
    
    context_menu.position = get_popup_pos_at_mouse()
    context_menu_pos_offset = get_mouse_pos_offset()
    context_menu.popup()

func set_context_menu_common_options(context_menu: PopupMenu) -> void:
    var selected_nodes: Array[GraphElement] = get_selected_ges()

    var multiple_selected: bool = selected_nodes.size() > 1
    
    var num_selected_groups: int = get_selected_groups().size()
    var plural_s: = "s" if multiple_selected else ""

    context_menu.add_item("Copy Node" + plural_s, CHANE_AssetNodeEditor.ContextMenuItems.COPY_NODES)
    context_menu.add_item("Cut Node" + plural_s, CHANE_AssetNodeEditor.ContextMenuItems.CUT_NODES)

    
    var paste_plural_s: = "s" if copied_nodes.size() > 1 else ""
    context_menu.add_item("Paste Node" + paste_plural_s, CHANE_AssetNodeEditor.ContextMenuItems.PASTE_NODES)
    if not check_if_can_paste():
        var paste_idx: int = context_menu.get_item_index(CHANE_AssetNodeEditor.ContextMenuItems.PASTE_NODES)
        context_menu.set_item_disabled(paste_idx, true)

    context_menu.add_item("Delete Node" + plural_s, CHANE_AssetNodeEditor.ContextMenuItems.DELETE_NODES)
    if not multiple_selected and not can_delete_ge(selected_nodes[0]):
        var delete_idx: int = context_menu.get_item_index(CHANE_AssetNodeEditor.ContextMenuItems.DELETE_NODES)
        context_menu.set_item_disabled(delete_idx, true)
    
    if num_selected_groups > 0:
        context_menu.add_item("Delete Nodes (Including All Inside Selected Groups)", CHANE_AssetNodeEditor.ContextMenuItems.DELETE_NODES_DEEP)
        context_menu.add_item("Remove Selected Groups (Keeping Nodes Inside)", CHANE_AssetNodeEditor.ContextMenuItems.DELETE_GROUPS_ONLY)
    
    context_menu.add_item("Duplicate Node" + plural_s, CHANE_AssetNodeEditor.ContextMenuItems.DUPLICATE_NODES)

func set_context_menu_select_options(context_menu: PopupMenu, over_graph_node: bool, over_group: bool) -> void:
    context_menu.add_item("Select All", CHANE_AssetNodeEditor.ContextMenuItems.SELECT_ALL)
    context_menu.add_item("Deselect All", CHANE_AssetNodeEditor.ContextMenuItems.DESELECT_ALL)
    context_menu.add_item("Invert Selection", CHANE_AssetNodeEditor.ContextMenuItems.INVERT_SELECTION)
    
    if over_graph_node:
        context_menu.add_item("Select Subtree", CHANE_AssetNodeEditor.ContextMenuItems.SELECT_SUBTREE)
        context_menu.add_item("Select Subtree (Greedy)", CHANE_AssetNodeEditor.ContextMenuItems.SELECT_SUBTREE_GREEDY)
    
    var num_selected_groups: int = get_selected_groups().size()
    if num_selected_groups > 0:
        if over_group:
            context_menu.add_item("Select All Nodes In This Group", CHANE_AssetNodeEditor.ContextMenuItems.SELECT_GROUP_NODES)
        if not over_group or num_selected_groups > 1:
            context_menu.add_item("Select All Nodes In Selected Groups", CHANE_AssetNodeEditor.ContextMenuItems.SELECT_GROUPS_NODES)

func set_context_menu_new_node_options(context_menu: PopupMenu) -> void:
    context_menu.add_item("Create New Node", CHANE_AssetNodeEditor.ContextMenuItems.CREATE_NEW_NODE)
    context_menu.add_item("Create New Group", CHANE_AssetNodeEditor.ContextMenuItems.CREATE_NEW_GROUP)

func check_if_can_paste() -> bool:
    if copied_nodes.size() > 0:
        return true
    if ClipboardManager.load_copied_nodes_from_clipboard(self):
        return true
    return false

func on_node_context_menu_id_pressed(node_context_menu_id: CHANE_AssetNodeEditor.ContextMenuItems, on_ge: GraphElement) -> void:
    var is_graph_node: bool = on_ge and on_ge is CustomGraphNode
    var is_group: bool = on_ge and on_ge is GraphFrame

    match node_context_menu_id:
        CHANE_AssetNodeEditor.ContextMenuItems.COPY_NODES:
            _copy_request()
        CHANE_AssetNodeEditor.ContextMenuItems.CUT_NODES:
            _cut_request()
        CHANE_AssetNodeEditor.ContextMenuItems.CUT_NODES_DEEP:
            cut_selected_nodes_inclusive()
        CHANE_AssetNodeEditor.ContextMenuItems.PASTE_NODES:
            _paste_request()
        CHANE_AssetNodeEditor.ContextMenuItems.DELETE_NODES:
            _delete_request_refs(get_selected_ges())
        CHANE_AssetNodeEditor.ContextMenuItems.DELETE_NODES_DEEP:
            delete_selected_nodes_inclusive()
        CHANE_AssetNodeEditor.ContextMenuItems.DELETE_GROUPS_ONLY:
            var selected_groups: = get_selected_groups()
            remove_groups_only_with_undo(selected_groups)
        CHANE_AssetNodeEditor.ContextMenuItems.DISSOLVE_NODES:
            if is_graph_node:
                dissolve_gn_with_undo(on_ge)
        CHANE_AssetNodeEditor.ContextMenuItems.BREAK_CONNECTIONS:
            if is_graph_node:
                cut_all_connections_with_undo(on_ge)
        CHANE_AssetNodeEditor.ContextMenuItems.DUPLICATE_NODES:
            duplicate_selected_ges()
        
        CHANE_AssetNodeEditor.ContextMenuItems.EDIT_TITLE:
            if is_graph_node:
                open_gn_title_edit(on_ge)
        CHANE_AssetNodeEditor.ContextMenuItems.EDIT_GROUP_TITLE:
            if is_group:
                open_group_title_edit(on_ge)
        
        CHANE_AssetNodeEditor.ContextMenuItems.SELECT_SUBTREE:
            if is_graph_node:
                select_subtree(on_ge, false)
        CHANE_AssetNodeEditor.ContextMenuItems.SELECT_SUBTREE_GREEDY:
            if is_graph_node:
                select_subtree(on_ge, true)
        CHANE_AssetNodeEditor.ContextMenuItems.SELECT_GROUP_NODES:
            if is_group:
                deselect_all()
                select_nodes_in_group(on_ge)
        CHANE_AssetNodeEditor.ContextMenuItems.SELECT_GROUPS_NODES:
            var selected_groups: Array[GraphFrame] = get_selected_groups()
            deselect_all()
            for group in selected_groups:
                select_nodes_in_group(group)
        CHANE_AssetNodeEditor.ContextMenuItems.SELECT_ALL:
            select_all()
        CHANE_AssetNodeEditor.ContextMenuItems.DESELECT_ALL:
            deselect_all()
        CHANE_AssetNodeEditor.ContextMenuItems.INVERT_SELECTION:
            invert_selection()
        
        CHANE_AssetNodeEditor.ContextMenuItems.SET_GROUP_SHRINKWRAP:
            var selected_groups: Array[GraphFrame] = get_selected_groups()
            set_groups_shrinkwrap_with_undo(selected_groups, true)
        CHANE_AssetNodeEditor.ContextMenuItems.SET_GROUP_NO_SHRINKWRAP:
            var selected_groups: Array[GraphFrame] = get_selected_groups()
            set_groups_shrinkwrap_with_undo(selected_groups, false)
        CHANE_AssetNodeEditor.ContextMenuItems.CREATE_NEW_NODE:
            var into_group: = on_ge if is_group else null
            editor.show_new_node_menu_for_pos(context_menu_pos_offset, self, into_group)
        CHANE_AssetNodeEditor.ContextMenuItems.CREATE_NEW_GROUP:
            var into_group: = on_ge if is_group else null
            add_new_group_pending_title_undo_step(context_menu_pos_offset, into_group)
        
        CHANE_AssetNodeEditor.ContextMenuItems.NEW_FILE:
            popup_menu_root.show_new_file_type_chooser()

func on_change_group_color_name_index_pressed(index: int, color_name_menu: PopupMenu, group: GraphFrame) -> void:
    var color_name: String = color_name_menu.get_item_text(index)
    if not ThemeColorVariants.has_theme_color(color_name):
        return
    set_group_color_with_undo(group, color_name)

func get_title_edit_popup(current_title: String) -> PopupPanel:
    var title_edit_popup: = preload("res://ui/node_title_edit_popup.tscn").instantiate() as PopupPanel
    title_edit_popup.current_title = current_title
    return title_edit_popup

func open_gn_title_edit(graph_node: CustomGraphNode) -> PopupPanel:
    var title_edit_popup = get_title_edit_popup(graph_node.title)
    title_edit_popup.new_title_submitted.connect(change_gn_title.bind(graph_node))
    add_child(title_edit_popup, true)
    title_edit_popup.position = Util.get_popup_window_pos(graph_node.get_global_position())
    title_edit_popup.position -= Vector2i.ONE * 10
    show_exclusive_clamped_popup(title_edit_popup)
    return title_edit_popup

func open_group_title_edit(group: GraphFrame) -> PopupPanel:
    var title_edit_popup = get_title_edit_popup(group.title)
    title_edit_popup.new_title_submitted.connect(change_group_title.bind(group))
    add_child(title_edit_popup, true)
    var group_title_rect: = group.get_titlebar_hbox().get_global_rect()
    var group_title_center: = Vector2(group_title_rect.get_center().x, group_title_rect.position.y)
    title_edit_popup.position = Util.get_popup_window_pos(group_title_center)
    title_edit_popup.position.x -= (title_edit_popup.size / 2.0).x
    show_exclusive_clamped_popup(title_edit_popup)
    return title_edit_popup

func show_exclusive_clamped_popup(the_popup: PopupPanel) -> void:
    the_popup.position = clamp_window_pos_for_popup(the_popup.position, the_popup.size)
    the_popup.exclusive = true
    the_popup.popup()

func clamp_window_pos_for_popup(window_pos: Vector2i, popup_size: Vector2) -> Vector2i:
    return Util.clamp_popup_pos_inside_window(window_pos, popup_size, get_window())

func change_gn_title(new_title: String, graph_node: CustomGraphNode) -> void:
    unedited = false
    var old_title: String = graph_node.title
    _set_gn_title(graph_node, new_title)
    create_change_title_undo_step(graph_node, old_title)

func _set_gn_title(graph_node: CustomGraphNode, new_title: String) -> void:
    graph_node.title = new_title
    if graph_node.get_meta("hy_asset_node_id", ""):
        var an: HyAssetNode = an_lookup.get(graph_node.get_meta("hy_asset_node_id", ""), null)
        if an:
            an.title = new_title

func change_group_title(new_title: String, group: GraphFrame) -> void:
    unedited = false
    var old_title: String = group.title
    _set_group_title(group, new_title)
    create_change_title_undo_step(group, old_title)

func _set_group_title(group: GraphFrame, new_title: String) -> void:
    group.title = new_title
    group.tooltip_text = new_title

func create_change_title_undo_step(graph_element: GraphElement, old_title: String) -> void:
    if not (graph_element is CustomGraphNode or graph_element is GraphFrame):
        return
    unedited = false
    var new_title: String = graph_element.title
    undo_manager.create_action("Change Node Title")
    
    if graph_element is CustomGraphNode:
        undo_manager.add_do_method(_set_gn_title.bind(graph_element, new_title))
        undo_manager.add_undo_method(_set_gn_title.bind(graph_element, old_title))
    else:
        undo_manager.add_do_method(_set_group_title.bind(graph_element, new_title))
        undo_manager.add_undo_method(_set_group_title.bind(graph_element, old_title))

    undo_manager.commit_action(false)



func get_duplicate_gn_name(old_gn_name: String) -> String:
    var base_name: = old_gn_name.split("--")[0]
    return new_graph_node_name(base_name)

func new_graph_node_name(base_name: String) -> String:
    global_gn_counter += 1
    return "%s--%d" % [base_name, global_gn_counter]

func raw_connections(graph_node: CustomGraphNode) -> Array[Dictionary]:
    assert(is_same(graph_node.get_parent(), self), "raw_connections: Graph node %s is not a direct child of the graph edit" % graph_node.name)

    # Workaround to avoid erronious error from trying to get connection list of nodes whose connections have never been touched yet
    # this triggers the connection_map having an entry for this node name
    is_node_connected(graph_node.name, 0, graph_node.name, 0)

    return get_connection_list_from_node(graph_node.name)

func raw_out_connections(graph_node: CustomGraphNode) -> Array[Dictionary]:
    return Util.out_connections(raw_connections(graph_node), graph_node.name)

func raw_in_connections(graph_node: CustomGraphNode) -> Array[Dictionary]:
    return Util.in_connections(raw_connections(graph_node), graph_node.name)

func typed_conn_infos_for_gn(graph_node: CustomGraphNode) -> Array[Dictionary]:
    var conn_infos: = raw_connections(graph_node)
    for i in conn_infos.size():
        conn_infos[i]["value_type"] = get_type_of_conn_info(conn_infos[i])
    return conn_infos

func can_delete_gn(graph_node: CustomGraphNode) -> bool:
    if graph_node == editor.root_graph_node:
        return false
    return true

func can_delete_ge(graph_element: GraphElement) -> bool:
    if graph_element is CustomGraphNode:
        return can_delete_gn(graph_element)
    elif graph_element is GraphFrame:
        return true
    return false

func deserialize_and_add_group_and_attach_graph_nodes(group_data: Dictionary) -> GraphFrame:
    var new_group: = deserialize_and_add_group(group_data, true, false)
    var ges_to_attach: Array[GraphElement] = []
    var new_group_rect: = new_group.get_rect()
    new_group_rect.position = new_group.position_offset
    var num_added: int = 0
    for child in get_children():
        if child == new_group:
            continue
        if not child is GraphElement:
            continue
        if child is GraphFrame:
            var child_rect: Rect2 = child.get_rect().grow(-8)
            child_rect.position = child.position_offset
            if new_group_rect.encloses(child_rect):
                num_added += 1
                ges_to_attach.append(child)
        elif child is CustomGraphNode:
            var child_hbox_rect: Rect2 = child.get_titlebar_hbox().get_rect()
            child_hbox_rect.position = child.position_offset
            var child_titlebar_center: Vector2 = child_hbox_rect.get_center()
            if new_group_rect.has_point(child_titlebar_center):
                num_added += 1
                ges_to_attach.append(child)
    if num_added == 0:
        new_group.autoshrink_enabled = false
    add_ges_to_group(ges_to_attach, new_group)
    return new_group

func _get_deserialized_group(group_data: Dictionary, use_json_pos_scale: bool, relative_to_screen_center: bool) -> GraphFrame:
    serializer.serialized_pos_scale = json_positions_scale if use_json_pos_scale else Vector2.ONE
    serializer.serialized_pos_offset = relative_root_position
    if relative_to_screen_center:
        serializer.serialized_pos_offset = local_pos_to_pos_offset(get_viewport().get_visible_rect().size / 2)
    return serializer.deserialize_group(group_data)
            
func deserialize_and_add_group(group_data: Dictionary, use_json_pos_scale: bool, relative_to_screen_center: bool) -> GraphFrame:
    var new_group: = _get_deserialized_group(group_data, use_json_pos_scale, relative_to_screen_center)
    add_existing_group(new_group)
    return new_group

func set_group_color_with_undo(group: GraphFrame, group_color_name: String) -> void:
    if not group.get_meta("has_custom_color", false):
        add_group_color_with_undo(group, group_color_name)
        return

    var old_color_name: String = group.get_meta("custom_color_name", "")
    undo_manager.create_action("Change Group Accent Color")
    
    undo_manager.add_do_method(set_group_custom_accent_color.bind(group, group_color_name))
    undo_manager.add_undo_method(set_group_custom_accent_color.bind(group, old_color_name))

    undo_manager.commit_action(true)
    refresh_graph_elements_in_frame_status()

func add_group_color_with_undo(group: GraphFrame, group_color_name: String) -> void:
    undo_manager.create_action("Add Group Accent Color")
    undo_manager.add_do_method(set_group_custom_accent_color.bind(group, group_color_name))
    undo_manager.add_undo_method(remove_group_accent_color.bind(group))
    undo_manager.commit_action(true)
    refresh_graph_elements_in_frame_status()

func get_default_group_color_name() -> String:
    if ThemeColorVariants.has_theme_color(ANESettings.default_group_color):
        return ANESettings.default_group_color
    return TypeColors.fallback_color

func set_group_custom_accent_color(the_group: GraphFrame, group_color_name: String, as_custom: bool = true) -> void:
    if not as_custom:
        remove_group_accent_color(the_group)
        return
    if not group_color_name or not ThemeColorVariants.has_theme_color(group_color_name):
        group_color_name = get_default_group_color_name()

    the_group.set_meta("has_custom_color", true)
    the_group.set_meta("custom_color_name", group_color_name)
    the_group.theme = ThemeColorVariants.get_theme_color_variant(group_color_name)

func remove_group_accent_color(group: GraphFrame) -> void:
    group.set_meta("has_custom_color", false)
    group.set_meta("custom_color_name", "")
    group.theme = ThemeColorVariants.get_theme_color_variant(get_default_group_color_name())

func _make_new_group(group_title: String = "Group", group_size: Vector2 = Vector2(100, 100)) -> GraphFrame:
    var new_group: = GraphFrame.new()
    new_group.name = new_graph_node_name("Group")
    new_group.resizable = true
    new_group.autoshrink_enabled = ANESettings.default_is_group_shrinkwrap
    new_group.size = group_size
    _set_group_title(new_group, group_title)
    
    return new_group

func add_existing_group(the_group: GraphFrame) -> void:
    var custom_color_name: String = the_group.get_meta("custom_color_name", "")
    var has_custom_color: bool = the_group.get_meta("has_custom_color", false)
    set_group_custom_accent_color(the_group, custom_color_name, has_custom_color)

    add_graph_element_child(the_group)
    bring_group_to_front(the_group)

func add_new_group(at_pos_offset: Vector2, with_title: String = "Group", with_size: Vector2 = Vector2.ZERO) -> GraphFrame:
    if with_size == Vector2.ZERO:
        with_size = ANESettings.default_group_size
    var new_group: = _make_new_group(with_title, with_size)

    add_graph_element_child(new_group)
    new_group.position_offset = at_pos_offset
    new_group.set_meta("has_custom_color", false)
    new_group.theme = ThemeColorVariants.get_theme_color_variant(ANESettings.default_group_color)
    new_group.raise_request.emit()
    return new_group

func add_new_colored_group(with_color: String, at_pos_offset: Vector2, with_title: String = "Group", with_size: Vector2 = Vector2.ZERO) -> GraphFrame:
    var new_group: = add_new_group(at_pos_offset, with_title, with_size)
    
    set_group_custom_accent_color(new_group, with_color)
    return new_group

func add_new_group_title_centered(at_pos_offset: Vector2) -> GraphFrame:
    var new_group_size: = ANESettings.default_group_size
    at_pos_offset.x -= new_group_size.x / 2
    at_pos_offset.y -= 6
    return add_new_group(at_pos_offset)

func add_new_group_pending_title_undo_step(at_pos_offset: Vector2, into_group: GraphFrame) -> void:
    var new_group: = add_new_group_title_centered(at_pos_offset)
    await get_tree().process_frame
    if into_group:
        # This adds the group relation to the undo action that should always be committed as soon as the edit title popup is closed
        # regardless of if the default title is changed or not
        add_ge_to_group(new_group, into_group, true)
    var title_edit_popup: = open_group_title_edit(new_group)
    title_edit_popup.tree_exiting.connect(create_new_group_undo_step.bind(new_group, into_group))

func create_new_group_undo_step(new_group: GraphFrame, into_group: GraphFrame) -> void:
    undo_manager.create_action("Add New Group")
    var new_group_pos_offset: = new_group.position_offset
    var new_group_title: = new_group.title
    var new_group_size: = new_group.size
    var add_new_group_callback: = add_new_group.bind(new_group_pos_offset, new_group_title, new_group_size)
    if new_group.get_meta("has_custom_color", false):
        var new_group_accent_color: String = new_group.get_meta("custom_color_name", "")
        add_new_group_callback = add_new_colored_group.bind(new_group_accent_color, new_group_pos_offset, new_group_title, new_group_size)

    undo_manager.add_do_method(add_new_group_callback)
    
    undo_manager.add_undo_method(_undo_redo_remove_ge.bind(new_group))
    
    if into_group:
        add_group_membership_to_cur_undo_action(false, true)

    undo_manager.commit_action(false)

func set_groups_shrinkwrap_with_undo(groups: Array[GraphFrame], shrinkwrap: bool) -> void:
    var old_group_shrinkwrap: Dictionary[GraphFrame, bool] = {}
    var new_group_shrinkwrap: Dictionary[GraphFrame, bool] = {}
    var old_group_positions: Dictionary[GraphElement, Vector2] = {}
    var new_group_positions: Dictionary[GraphElement, Vector2] = {}
    var old_group_sizes: Dictionary[GraphFrame, Vector2] = {}
    var new_group_sizes: Dictionary[GraphFrame, Vector2] = {}
    for group in get_all_groups():
        if group in groups:
            old_group_shrinkwrap[group] = group.autoshrink_enabled
            new_group_shrinkwrap[group] = shrinkwrap
        old_group_positions[group] = group.position_offset
        old_group_sizes[group] = group.size
    
    _set_groups_shrinkwrap(new_group_shrinkwrap)
    
    for group in groups:
        new_group_positions[group] = group.position_offset
        new_group_sizes[group] = group.size
    
    undo_manager.create_action("Change Group Shrinkwrap")

    undo_manager.add_do_method(_set_groups_shrinkwrap.bind(new_group_shrinkwrap))
    undo_manager.add_do_method(_set_offsets_and_group_sizes.bind(new_group_positions, new_group_sizes))

    undo_manager.add_undo_method(_set_groups_shrinkwrap.bind(old_group_shrinkwrap))
    undo_manager.add_undo_method(_set_offsets_and_group_sizes.bind(old_group_positions, old_group_sizes))
    undo_manager.commit_action(false)

func _set_groups_shrinkwrap(group_shrinkwraps: Dictionary[GraphFrame, bool]) -> void:
    for group in group_shrinkwraps.keys():
        group.autoshrink_enabled = group_shrinkwraps[group]

func _link_to_group_request(graph_element_names: Array, group_name: StringName) -> void:
    _attach_ge_names_to_group(graph_element_names, group_name)
    cur_added_group_relations.append({
        "group": get_node(NodePath(group_name)) as GraphFrame,
        "member": get_node(NodePath(graph_element_names[0])) as GraphElement,
    })

func bring_group_to_front(group: GraphFrame) -> void:
    group.raise_request.emit()

func get_color_name_menu() -> PopupMenu:
    var color_name_menu: PopupMenu = PopupMenu.new()
    for color_name in ThemeColorVariants.get_theme_colors():
        var theme_color: Color = ThemeColorVariants.get_theme_color(color_name)
        color_name_menu.add_icon_item(Util.get_icon_for_color(theme_color), color_name)
    return color_name_menu

func get_pos_offset_rect(graph_element: GraphElement) -> Rect2:
    return Rect2(graph_element.position_offset, graph_element.size)

func get_popup_pos_at_mouse() -> Vector2i:
    return Util.get_popup_window_pos(get_global_mouse_position())

func add_graph_element_child(graph_element: GraphElement, with_snap: bool = false) -> void:
    if graph_element is CustomGraphNode:
        add_graph_node_child(graph_element, with_snap)
    else:
        add_child(graph_element, true)
        if with_snap:
            snap_ge(graph_element)

func add_graph_node_child(graph_node: CustomGraphNode, with_snap: bool = false) -> void:
    add_child(graph_node, true)
    if with_snap:
        snap_ge(graph_node)

    var an_id: String = graph_node.get_meta("hy_asset_node_id", "")
    if an_id:
        editor.gn_lookup[an_id] = graph_node
    graph_node.update_slot_types(type_id_lookup)
    graph_node.was_right_clicked.connect(_on_graph_node_right_clicked)
    graph_node.titlebar_double_clicked.connect(_on_graph_node_titlebar_double_clicked)

func remove_graph_node_child(graph_node: CustomGraphNode) -> void:
    remove_graph_element_child(graph_node)
    if graph_node.was_right_clicked.is_connected(_on_graph_node_right_clicked):
        graph_node.was_right_clicked.disconnect(_on_graph_node_right_clicked)
    if graph_node.titlebar_double_clicked.is_connected(_on_graph_node_titlebar_double_clicked):
        graph_node.titlebar_double_clicked.disconnect(_on_graph_node_titlebar_double_clicked)

func remove_graph_element_child(graph_element: GraphElement) -> void:
    if graph_element is CustomGraphNode:
        remove_graph_node_child(graph_element)
    else:
        remove_child(graph_element)

## Get's the position_offset coordinate under the mouse cursor's current position
func get_mouse_pos_offset() -> Vector2:
    return local_pos_to_pos_offset(get_local_mouse_position())

## Get's the position_offset coordinate at the center of the graph edit's current view into the graph
func get_center_pos_offset() -> Vector2:
    return local_pos_to_pos_offset(size / 2)

## Get's the position_offset coordinate that coincides with a given global (godot 2d space) position
func global_pos_to_pos_offset(the_global_pos: Vector2) -> Vector2:
    var local_pos: = get_global_transform().affine_inverse() * the_global_pos
    return local_pos_to_pos_offset(local_pos)

func local_pos_to_pos_offset(the_pos: Vector2) -> Vector2:
    return (scroll_offset + the_pos) / zoom

func position_offset_to_global_pos(the_position_offset: Vector2) -> Vector2:
    return (the_position_offset * zoom) - scroll_offset