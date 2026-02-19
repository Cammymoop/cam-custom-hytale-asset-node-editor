## A class to hold all information needed to undo/redo actions in the Asset Node Editor
extends RefCounted

const GraphUndoStep = preload("res://graph_editor/undo_redo/graph_undo_step.gd")

var editor: CHANE_AssetNodeEditor

## For each affected graph, store the graph specific information here
var graph_undo_steps: Dictionary[CHANE_AssetNodeGraphEdit, GraphUndoStep] = {}

var created_asset_nodes: Array[HyAssetNode] = []
var created_asset_nodes_aux_data: Array[HyAssetNode.AuxData] = []
var deleted_asset_nodes: Array[HyAssetNode] = []
var deleted_asset_nodes_aux_data: Array[HyAssetNode.AuxData] = []

var added_asset_node_connections: Array[Dictionary] = []
var removed_asset_node_connections: Array[Dictionary] = []

var an_settings_changed: Dictionary[String, Dictionary] = {}

var custom_undo_callbacks: Array[Callable] = []
var custom_redo_callbacks: Array[Callable] = []

var has_existing_action: bool = false

var action_name: String = "Action"

func set_editor(the_editor: CHANE_AssetNodeEditor) -> void:
    editor = the_editor

func get_history_text() -> String:
    return action_name

func add_graph_undo(graph: CHANE_AssetNodeGraphEdit, undo_step: GraphUndoStep) -> void:
    graph_undo_steps[graph] = undo_step

func get_undo_for_graph(graph: CHANE_AssetNodeGraphEdit) -> GraphUndoStep:
    if not graph_undo_steps.has(graph):
        prints("Getting new graph undo step for graph %s" % graph.get_path())
        graph_undo_steps[graph] = GraphUndoStep.new()
        graph_undo_steps[graph].selected_before = graph.get_selected_ges()
    else:
        prints("Getting existing graph undo step for graph %s" % graph.get_path())
    return graph_undo_steps[graph]

func register_an_settings_before_change(an_id: String, settings: Dictionary) -> void:
    var setting_change_info: Dictionary[String, Dictionary] = {}
    for setting_name in settings.keys():
        setting_change_info[setting_name] = _before_setting_template(settings[setting_name])
    an_settings_changed[an_id] = setting_change_info

func _before_setting_template(before_value: Variant) -> Dictionary[String, Variant]:
    var before_info: Dictionary[String, Variant] = {
        "before": before_value,
        "after": before_value,
    }
    return before_info

func trim_unchanged_settings() -> void:
    for an_id in an_settings_changed.keys():
        var setting_change_info: Dictionary[String, Dictionary] = an_settings_changed[an_id]
        for setting_name in setting_change_info.keys():
            if setting_change_info[setting_name]["before"] == setting_change_info[setting_name]["after"]:
                setting_change_info.erase(setting_name)
        if setting_change_info.size() == 0:
            an_settings_changed.erase(an_id)

func get_settings_changed_for_an(an: HyAssetNode) -> Dictionary[String, Dictionary]:
    return an_settings_changed.get(an.an_node_id, Dictionary({}, TYPE_STRING, &"", null, TYPE_DICTIONARY, &"", null))

func delete_graph_elements(ges_to_delete: Array[GraphElement], in_graph: CHANE_AssetNodeGraphEdit) -> void:
    deleted_asset_nodes.append_array(editor.get_all_owned_asset_nodes(ges_to_delete))
    var graph_undo_step: = get_undo_for_graph(in_graph)
    graph_undo_step._delete_graph_elements(in_graph, ges_to_delete)

## Adds deleting asset nodes to the undo step, assumes associated graph elements being deleted are already added to the undo step
func _delete_asset_nodes(asset_nodes: Array[HyAssetNode]) -> void:
    # remove all in connections first, skipping all connections already accounted for because the an was previously added for deletion
    for asset_node in asset_nodes:
        _remove_all_asset_node_in_connections(asset_node)
    _add_deleted_ans(asset_nodes)
    # now remove parent connections if the parent is not in the set or already being deleted
    for asset_node in asset_nodes:
        var parent_an: = editor.get_parent_an(asset_node)
        if parent_an and parent_an not in deleted_asset_nodes:
            removed_asset_node_connections.append({
                "from_an": parent_an.an_node_id,
                "from_conn_name": asset_node.connection_list[0],
                "to_an": asset_node,
            })

func _add_deleted_ans(asset_nodes: Array[HyAssetNode]) -> void:
    for asset_node in asset_nodes:
        deleted_asset_nodes.append(asset_node)
        deleted_asset_nodes_aux_data.append(editor.asset_node_aux_data[asset_node.an_node_id])

func _remove_all_asset_node_in_connections(asset_node: HyAssetNode) -> void:
    for connection_name in asset_node.connection_list:
        var connected_ans: Array[HyAssetNode] = asset_node.get_all_connected_nodes(connection_name)
        for connected_an in connected_ans:
            if connected_an not in deleted_asset_nodes:
                removed_asset_node_connections.append({
                    "from_an": asset_node.an_node_id,
                    "from_conn_name": connection_name,
                    "to_an": connected_an.an_node_id,
                })

func _add_created_ans(asset_nodes: Array[HyAssetNode]) -> void:
    for asset_node in asset_nodes:
        created_asset_nodes.append(asset_node)
        created_asset_nodes_aux_data.append(editor.asset_node_aux_data[asset_node.an_node_id])

func commit(undo_redo: UndoRedo, merge_mode_override: int = -1) -> void:
    var merge_mode: = UndoRedo.MERGE_ENDS if has_existing_action else UndoRedo.MERGE_DISABLE
    if merge_mode_override >= 0:
        merge_mode = merge_mode_override as UndoRedo.MergeMode
    _make_action(undo_redo, merge_mode)

func _make_action(undo_redo: UndoRedo, merge_mode: UndoRedo.MergeMode) -> void:
    has_existing_action = true
    undo_redo.create_action(get_history_text(), merge_mode)
    
    for changed_an_id in an_settings_changed.keys():
        var an: = editor.all_asset_nodes[changed_an_id]
        var old_settings: = an.settings.duplicate_deep()
        var new_settings: = an.settings.duplicate_deep()
        for setting_name in an_settings_changed[changed_an_id].keys():
            var vals: = an_settings_changed[changed_an_id][setting_name] as Dictionary[String, Variant]
            old_settings[setting_name] = vals["before"]
            new_settings[setting_name] = vals["after"]
        undo_redo.add_undo_property(an, "settings", old_settings)
        undo_redo.add_do_property(an, "settings", new_settings)
    
    undo_redo.add_undo_method(editor.register_asset_nodes.bind(deleted_asset_nodes, deleted_asset_nodes_aux_data))
    undo_redo.add_do_method(editor.register_asset_nodes.bind(created_asset_nodes, created_asset_nodes_aux_data))
    
    for graph in graph_undo_steps.keys():
        graph_undo_steps[graph].register_action(undo_redo, graph, editor)
    
    for callback in custom_undo_callbacks:
        undo_redo.add_undo_method(callback)
    for callback in custom_redo_callbacks:
        undo_redo.add_do_method(callback)

    undo_redo.add_undo_method(editor.remove_asset_nodes.bind(created_asset_nodes))
    undo_redo.add_do_method(editor.remove_asset_nodes.bind(deleted_asset_nodes))
    
    prints("committing undo step with execute")
    
    undo_redo.commit_action(true)
    
func add_asset_node_connection(from_an: HyAssetNode, from_conn_name: String, to_an: HyAssetNode) -> void:
    added_asset_node_connections.append({
        "from_an": from_an,
        "from_conn_name": from_conn_name,
        "to_an": to_an,
    })

func remove_asset_node_connection(from_an: HyAssetNode, from_conn_name: String, to_an: HyAssetNode) -> void:
    removed_asset_node_connections.append({
        "from_an": from_an,
        "from_conn_name": from_conn_name,
        "to_an": to_an,
    })