extends Node

var types_with_special_nodes: Array[String] = [
    "ManualCurve",
]

var editor: CHANE_AssetNodeEditor

func _enter_tree() -> void:
    editor = get_parent() as CHANE_AssetNodeEditor
    if not editor:
        editor = get_parent().get_parent() as CHANE_AssetNodeEditor

func make_duplicate_special_gn(special_gn: CustomGraphNode, asset_node_set: Array[HyAssetNode]) -> CustomGraphNode:
    var graph: CHANE_AssetNodeGraphEdit = special_gn.get_parent() as CHANE_AssetNodeGraphEdit
    var main_asset_node: HyAssetNode = graph.safe_get_an_from_gn(special_gn, asset_node_set)
    if not main_asset_node or not main_asset_node.an_type in types_with_special_nodes:
        print_debug("Main asset node not found or not in types_with_special_nodes, cannot make duplicate special GN")
        push_warning("Main asset node not found or not in types_with_special_nodes, cannot make duplicate special GN")
        return null

    if OS.has_feature("debug"):
        for owned_asset_node in special_gn.get_own_asset_nodes():
            assert(owned_asset_node in asset_node_set, "Owned asset node %s not in the set of duplicatable asset nodes" % owned_asset_node.an_node_id)

    var new_main_an = graph.duplicate_and_add_filtered_an_tree(main_asset_node, asset_node_set)
    var new_special_gn: CustomGraphNode = call("make_special_%s" % main_asset_node.an_type, new_main_an, false) as CustomGraphNode
    new_special_gn.position_offset = special_gn.position_offset
    new_special_gn.theme_color_output_type = special_gn.theme_color_output_type
    new_special_gn.set_meta("is_special_gn", true)
    return new_special_gn
    

func make_special_gn(target_asset_node: HyAssetNode, is_new: bool = false) -> CustomGraphNode:
    if not target_asset_node.an_type in types_with_special_nodes:
        print_debug("Target asset node type %s is not in types_with_special_nodes, cannot make special GN" % target_asset_node.an_type)
        return null
    
    var special_gn: = call("make_special_%s" % target_asset_node.an_type, target_asset_node, is_new) as CustomGraphNode
    special_gn.set_meta("is_special_gn", true)
    return special_gn

func make_special_ManualCurve(target_asset_node: HyAssetNode, is_new: bool) -> CustomGraphNode:
    var new_manual_curve_gn: ManualCurveSpecialGN = preload("res://custom_graph_nodes/manual_curve_special.tscn").instantiate()
    new_manual_curve_gn.set_meta("hy_asset_node_id", target_asset_node.an_node_id)
    new_manual_curve_gn.asset_node = target_asset_node
    new_manual_curve_gn.editor = editor

    if not is_new:
        new_manual_curve_gn.load_points_from_an_connection()
    else:
        new_manual_curve_gn.replace_points([Vector2(0, 1), Vector2(1, 0)])
        new_manual_curve_gn.load_points_from_an_connection()

    return new_manual_curve_gn as CustomGraphNode

func should_be_special_gn(asset_node: HyAssetNode) -> bool:
    return types_with_special_nodes.has(asset_node.an_type)