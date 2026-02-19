extends Node

var all_asset_nodes: Dictionary[String, HyAssetNode] = {}
var asset_node_aux_data: Dictionary[String, HyAssetNode.AuxData] = {}

func take_asset_nodes_from_editor(editor: CHANE_AssetNodeEditor, take_ans: Array[HyAssetNode], append: bool = false) -> void:
    if not append:
        all_asset_nodes = {}
        asset_node_aux_data = {}

    for an in take_ans:
        all_asset_nodes[an.an_node_id] = an
        asset_node_aux_data[an.an_node_id] = editor.asset_node_aux_data[an.an_node_id]
        editor.remove_asset_node_id(an.an_node_id)

func get_duplicate_an_set_from_editor(editor: CHANE_AssetNodeEditor, asset_node_set: Array[HyAssetNode], append: bool = false) -> void:
    if not append:
        all_asset_nodes = {}
        asset_node_aux_data = {}

    # create_duplicate_filtered_an_set will set the aux data for the duplicates into asset_node_aux_data
    var duplicate_ans: = editor.create_duplicate_filtered_an_set(asset_node_set, false, false, asset_node_aux_data)
    
    for an in duplicate_ans:
        all_asset_nodes[an.an_node_id] = an

func asset_nodes_from_graph_parse_result(graph_result: CHANE_HyAssetNodeSerializer.EntireGraphParseResult) -> void:
    asset_node_aux_data = graph_result.asset_node_aux_data.duplicate()
    all_asset_nodes = {}
    for floating_root_result in graph_result.floating_tree_results.values():
        append_tree_parse_result_asset_nodes(floating_root_result)

func append_tree_parse_result_asset_nodes(parse_result: CHANE_HyAssetNodeSerializer.TreeParseResult) -> void:
    for node in parse_result.all_nodes:
        all_asset_nodes[node.an_node_id] = node


func get_an_tree_roots() -> Array[HyAssetNode]:
    return CHANE_AssetNodeEditor.get_an_roots_within_set(all_asset_nodes, asset_node_aux_data)

func get_all_asset_nodes() -> Array[HyAssetNode]:
    return Array(all_asset_nodes.values(), TYPE_OBJECT, &"HyAssetNode", null)

func num_asset_nodes() -> int:
    return all_asset_nodes.size()

func get_all_graph_elements() -> Array[GraphElement]:
    var all_graph_elements: Array[GraphElement] = []
    _collect_graph_elements_recurse(self, all_graph_elements)
    return all_graph_elements

func _collect_graph_elements_recurse(at_node: Node, all_graph_elements: Array[GraphElement]) -> void:
    if at_node is GraphElement:
        all_graph_elements.append(at_node)
    for child in at_node.get_children():
        _collect_graph_elements_recurse(child, all_graph_elements)