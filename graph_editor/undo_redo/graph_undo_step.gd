## GraphEdit-specific parts of an undo step
extends RefCounted

var added_graph_elements: Array[GraphElement] = []
var removed_graph_elements: Array[GraphElement] = []

var added_connections: Array[Dictionary] = []
var removed_connections: Array[Dictionary] = []

var added_group_relations: Array[Dictionary] = []
var removed_group_relations: Array[Dictionary] = []

var moved_graph_elements_from: Dictionary[GraphElement, Vector2] = {}
var resized_graph_elements_from: Dictionary[GraphElement, Vector2] = {}

var group_shrinkwrap_changed_from: Dictionary[GraphFrame, bool] = {}
var group_shrinkwrap_changed_to: Dictionary[GraphFrame, bool] = {}

var group_accent_colors_changed_from: Dictionary[GraphFrame, String] = {}
var group_accent_colors_changed_to: Dictionary[GraphFrame, String] = {}

var ge_titles_changed_from: Dictionary[GraphElement, String] = {}
var ge_titles_changed_to: Dictionary[GraphElement, String] = {}

var selected_before: Array[GraphElement] = []

func add_graph_node_conn_infos(conn_infos: Array[Dictionary]) -> void:
    added_connections.append_array(conn_infos)

func remove_graph_node_conn_infos(conn_infos: Array[Dictionary]) -> void:
    removed_connections.append_array(conn_infos)

func add_graph_node_connection(from_gn_name: String, from_port: int, to_gn_name: String, to_port: int) -> void:
    added_connections.append({
        "from_node": from_gn_name,
        "from_port": from_port,
        "to_node": to_gn_name,
        "to_port": to_port,
    })

func remove_graph_node_connection(from_gn_name: String, from_port: int, to_gn_name: String, to_port: int) -> void:
    removed_connections.append({
        "from_node": from_gn_name,
        "from_port": from_port,
        "to_node": to_gn_name,
        "to_port": to_port,
    })

## Used by UndoStep, not to be called directly
func _delete_graph_elements(graph: CHANE_AssetNodeGraphEdit, ges_to_delete: Array[GraphElement]) -> void:
    removed_graph_elements.append_array(ges_to_delete)
    removed_connections.append_array(graph.get_all_connections_for_graph_elements(ges_to_delete))
    removed_group_relations.append_array(graph.get_graph_elements_cur_group_relations(ges_to_delete))

func add_new_graph_elements(new_ges: Array[GraphElement], new_connections: Array[Dictionary], new_group_relations: Array[Dictionary] = []) -> void:
    prints("Adding new graph elements in graph undo step, new ges: %s" % new_ges.size())
    added_graph_elements.append_array(new_ges)
    added_connections.append_array(new_connections)
    added_group_relations.append_array(new_group_relations)
    prints("cur added graph elements: %s" % added_graph_elements.size())

func add_ges_into_group(ges_to_include: Array[GraphElement], group: GraphFrame) -> void:
    for ge in ges_to_include:
        added_group_relations.append({
            "group": group,
            "member": ge,
        })

func register_action(undo_redo: UndoRedo, graph: CHANE_AssetNodeGraphEdit, _editor: CHANE_AssetNodeEditor) -> void:
    prints("Registering action for graph %s" % graph.get_path(), "cur added graph elements: %s" % added_graph_elements.size())
    var refresh_group_membership_and_colors: bool = false

    var moved_graph_elements_to: Dictionary[GraphElement, Vector2] = {}
    for moved_graph_element in moved_graph_elements_from.keys():
        moved_graph_elements_to[moved_graph_element] = moved_graph_element.position_offset
    var resized_graph_elements_to: Dictionary[GraphElement, Vector2] = {}
    for resized_graph_element in resized_graph_elements_from.keys():
        resized_graph_elements_to[resized_graph_element] = resized_graph_element.size
    
    if removed_graph_elements.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_add_ges.bind(removed_graph_elements))
    if added_graph_elements.size() > 0:
        prints("Undo step is adding graph elements %s to graph %s" % [added_graph_elements.size(), graph.get_path()])
        undo_redo.add_do_method(prints.bind("do method for adding graph elements"))
        undo_redo.add_do_method(graph.undo_redo_add_ges.bind(added_graph_elements))
    
    if removed_group_relations.size() > 0:
        refresh_group_membership_and_colors = true
        undo_redo.add_do_method(graph._break_group_relations.bind(removed_group_relations))
        undo_redo.add_undo_method(graph._assign_group_relations.bind(removed_group_relations))
    if added_group_relations.size() > 0:
        refresh_group_membership_and_colors = true
        undo_redo.add_undo_method(graph._break_group_relations.bind(added_group_relations))
        undo_redo.add_do_method(graph._assign_group_relations.bind(added_group_relations))

    if moved_graph_elements_from.size() > 0 or resized_graph_elements_from.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_set_offsets_and_sizes.bind(moved_graph_elements_from, resized_graph_elements_from))
        undo_redo.add_do_method(graph.undo_redo_set_offsets_and_sizes.bind(moved_graph_elements_to, resized_graph_elements_to))
    
    if removed_connections.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_add_connections.bind(removed_connections))
        undo_redo.add_do_method(graph.undo_redo_remove_connections.bind(removed_connections))
    if added_connections.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_remove_connections.bind(added_connections))
        undo_redo.add_do_method(graph.undo_redo_add_connections.bind(added_connections))
    
    if ge_titles_changed_from.size() > 0:
        undo_redo.add_undo_method(graph._set_ge_titles.bind(ge_titles_changed_from))
        undo_redo.add_do_method(graph._set_ge_titles.bind(ge_titles_changed_to))
    
    if group_shrinkwrap_changed_from.size() > 0:
        undo_redo.add_undo_method(graph._set_groups_shrinkwrap.bind(group_shrinkwrap_changed_from))
        undo_redo.add_do_method(graph._set_groups_shrinkwrap.bind(group_shrinkwrap_changed_to))
    
    if group_accent_colors_changed_from.size() > 0:
        refresh_group_membership_and_colors = true
        undo_redo.add_undo_method(graph._set_groups_accent_colors.bind(group_accent_colors_changed_from))
        undo_redo.add_do_method(graph._set_groups_accent_colors.bind(group_accent_colors_changed_to))
    
    if added_graph_elements.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_remove_ges.bind(added_graph_elements))
    if removed_graph_elements.size() > 0:
        undo_redo.add_do_method(graph.undo_redo_remove_ges.bind(removed_graph_elements))
    
    undo_redo.add_undo_method(graph.select_ges.bind(selected_before))

    var selected_after: Array[GraphElement] = []
    if added_graph_elements.size() > 0:
        selected_after = added_graph_elements
    else:
        selected_after = graph.get_selected_ges()
    undo_redo.add_do_method(graph.select_ges.bind(selected_after))
    
    if refresh_group_membership_and_colors:
        undo_redo.add_do_method(graph.refresh_graph_elements_in_frame_status)
        undo_redo.add_undo_method(graph.refresh_graph_elements_in_frame_status)