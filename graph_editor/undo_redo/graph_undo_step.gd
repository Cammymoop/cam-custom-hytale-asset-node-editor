## GraphEdit-specific parts of an undo step
extends RefCounted

var created_graph_elements: Array[GraphElement] = []
var deleted_graph_elements: Array[GraphElement] = []

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

# When getting new GraphElements from a fragment, we only need to delete them (and remove asset nodes) on undo, the fragment can be used to recreate the action including connections, group membership etc
var pasted_fragment_infos: Array[Dictionary] = []
var pasted_fragment_ge_names: Array[String] = []

var delete_fragment_infos: Array[Dictionary] = []
var delete_fragment_ge_names: Array[String] = []

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

func set_paste_fragment(fragment_id: String, counter_start: int, num_ges: int, at_pos_offset: Vector2, with_snap: bool) -> void:
    pasted_fragment_infos.append({
        "fragment_id": fragment_id,
        "counter_start": counter_start,
        "num_ges": num_ges,
        "at_pos_offset": at_pos_offset,
        "with_snap": with_snap,
    })

func set_delete_fragment(fragment_id: String, counter_start: int, num_ges: int, at_pos_offset: Vector2) -> void:
    delete_fragment_infos.append({
        "fragment_id": fragment_id,
        "counter_start": counter_start,
        "num_ges": num_ges,
        "at_pos_offset": at_pos_offset,
    })

## Used by UndoStep, not to be called directly
func _delete_graph_elements(graph: CHANE_AssetNodeGraphEdit, ges_to_delete: Array[GraphElement]) -> void:
    deleted_graph_elements.append_array(ges_to_delete)
    removed_connections.append_array(graph.get_all_connections_for_graph_elements(ges_to_delete))
    removed_group_relations.append_array(graph.get_graph_elements_cur_group_relations(ges_to_delete))

func add_new_graph_elements(new_ges: Array[GraphElement], new_connections: Array[Dictionary], new_group_relations: Array[Dictionary] = []) -> void:
    prints("Adding new graph elements in graph undo step, new ges: %s" % new_ges.size())
    created_graph_elements.append_array(new_ges)
    added_connections.append_array(new_connections)
    added_group_relations.append_array(new_group_relations)
    prints("cur added graph elements: %s" % created_graph_elements.size())

func add_ges_into_group(ges_to_include: Array[GraphElement], group: GraphFrame) -> void:
    for ge in ges_to_include:
        added_group_relations.append({
            "group": group,
            "member": ge,
        })

func remove_ges_from_group(ges_to_remove: Array[GraphElement], group: GraphFrame) -> void:
    for ge in ges_to_remove:
        removed_group_relations.append({
            "group": group,
            "member": ge,
        })

func remove_group_relations(group_relations: Array[Dictionary]) -> void:
    removed_group_relations.append_array(group_relations)

func register_action(undo_redo: UndoRedo, graph: CHANE_AssetNodeGraphEdit, editor: CHANE_AssetNodeEditor) -> void:
    prints("Registering action for graph %s" % graph.get_path(), "cur added graph elements: %s" % created_graph_elements.size())
    var refresh_group_membership_and_colors: bool = false

    var moved_graph_elements_to: Dictionary[GraphElement, Vector2] = {}
    for moved_graph_element in moved_graph_elements_from.keys():
        moved_graph_elements_to[moved_graph_element] = moved_graph_element.position_offset
    var resized_graph_elements_to: Dictionary[GraphElement, Vector2] = {}
    for resized_graph_element in resized_graph_elements_from.keys():
        resized_graph_elements_to[resized_graph_element] = resized_graph_element.size
    
    # Note: adding nodes from fragments is already called ahead of time and skipped when called automatically during undo step commit
    if pasted_fragment_infos.size() > 0:
        for finfo in pasted_fragment_infos:
            undo_redo.add_do_method(editor._insert_fragment_into_graph.bind(finfo["fragment_id"], graph, finfo["at_pos_offset"], finfo["with_snap"], finfo["counter_start"]))
    if delete_fragment_infos.size() > 0:
        for finfo in delete_fragment_infos:
            undo_redo.add_undo_method(editor._insert_fragment_into_graph.bind(finfo["fragment_id"], graph, finfo["at_pos_offset"], false, finfo["counter_start"]))
    
    
    if deleted_graph_elements.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_add_ges.bind(deleted_graph_elements))
    if created_graph_elements.size() > 0:
        prints("Undo step is adding graph elements %s to graph %s" % [created_graph_elements.size(), graph.get_path()])
        undo_redo.add_do_method(prints.bind("do method for adding graph elements"))
        undo_redo.add_do_method(graph.undo_redo_add_ges.bind(created_graph_elements))
    
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
    
    if created_graph_elements.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_remove_ges.bind(created_graph_elements))
        # Also free the node from memory if the undo history action is discarded while "not redone"
        for created_ge in created_graph_elements:
            undo_redo.add_do_reference(created_ge)
    if deleted_graph_elements.size() > 0:
        undo_redo.add_do_method(graph.undo_redo_remove_ges.bind(deleted_graph_elements))
        # Also free the node from memory if the undo history action is discarded while "not undone"
        for deleted_ge in deleted_graph_elements:
            undo_redo.add_undo_reference(deleted_ge)
    
    if pasted_fragment_infos.size() > 0:
        for finfo in pasted_fragment_infos:
            undo_redo.add_undo_method(graph.undo_redo_delete_fragment_ges.bind(finfo["counter_start"], finfo["num_ges"]))
    if delete_fragment_infos.size() > 0:
        for finfo in delete_fragment_infos:
            undo_redo.add_do_method(graph.undo_redo_delete_fragment_ges.bind(finfo["counter_start"], finfo["num_ges"]))
    
    undo_redo.add_undo_method(graph.select_ges.bind(selected_before))

    var selected_after: Array[GraphElement] = []
    if created_graph_elements.size() > 0:
        selected_after = created_graph_elements
    else:
        selected_after = graph.get_selected_ges()
    undo_redo.add_do_method(graph.select_ges.bind(selected_after))
    
    if refresh_group_membership_and_colors:
        undo_redo.add_do_method(graph.refresh_graph_elements_in_frame_status)
        undo_redo.add_undo_method(graph.refresh_graph_elements_in_frame_status)