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

var selected_before: Array[GraphElement] = []

func register_action(undo_redo: UndoRedo, graph: CHANE_AssetNodeGraphEdit, _editor: CHANE_AssetNodeEditor) -> void:
    var moved_graph_elements_to: Dictionary[GraphElement, Vector2] = {}
    for moved_graph_element in moved_graph_elements_from.keys():
        moved_graph_elements_to[moved_graph_element] = moved_graph_element.position_offset
    var resized_graph_elements_to: Dictionary[GraphElement, Vector2] = {}
    for resized_graph_element in resized_graph_elements_from.keys():
        resized_graph_elements_to[resized_graph_element] = resized_graph_element.size
    var group_shrinkwrap_changed_to: Dictionary[GraphFrame, bool] = {}
    
    if removed_graph_elements.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_add_ges.bind(removed_graph_elements))
    if added_graph_elements.size() > 0:
        undo_redo.add_do_method(graph.undo_redo_add_ges.bind(added_graph_elements))

    if moved_graph_elements_from.size() > 0 or resized_graph_elements_from.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_set_offsets_and_sizes.bind(moved_graph_elements_from, resized_graph_elements_from))
        undo_redo.add_do_method(graph.undo_redo_set_offsets_and_sizes.bind(moved_graph_elements_to, resized_graph_elements_to))
    
    if removed_connections.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_add_connections.bind(removed_connections))
        undo_redo.add_do_method(graph.undo_redo_remove_connections.bind(removed_connections))
    if added_connections.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_remove_connections.bind(added_connections))
        undo_redo.add_do_method(graph.undo_redo_add_connections.bind(added_connections))
    
    if group_shrinkwrap_changed_from.size() > 0:
        undo_redo.add_undo_method(graph.undo_redo_set_groups_shrinkwrap.bind(group_shrinkwrap_changed_from))
        undo_redo.add_do_method(graph.undo_redo_set_groups_shrinkwrap.bind(group_shrinkwrap_changed_to))
    
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