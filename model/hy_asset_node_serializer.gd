extends Node
class_name CHANE_HyAssetNodeSerializer


class SingleParseResult:
    var asset_node: HyAssetNode = null
    var success: bool = true
    var is_existing_node_id: bool = true

class TreeParseResult:
    var from_old_style_data: bool = false
    var root_node: HyAssetNode = null
    var first_failure_at: SingleParseResult = null
    var all_nodes_results: Array[SingleParseResult] = []
    var all_nodes: Array[HyAssetNode] = []
    var success: bool = true
    
    func add_root(parse_result: SingleParseResult) -> void:
        all_nodes_results.append(parse_result)
        all_nodes.append(parse_result.asset_node)
        root_node = parse_result.asset_node
        if not parse_result.success:
            success = false
    
    func merge_results(other_result: TreeParseResult) -> void:
        all_nodes_results.append_array(other_result.all_nodes_results)
        all_nodes.append_array(other_result.all_nodes)
        if not other_result.success:
            success = false
            if not first_failure_at and other_result.first_failure_at:
                first_failure_at = other_result.first_failure_at


func get_unique_an_id(prefix: String) -> String:
    return "%s-%s" % [prefix, Util.unique_id_string()]

func get_new_id_for_type(asset_node_type: String) -> String:
    return get_unique_an_id(SchemaManager.schema.get_id_prefix_for_node_type(asset_node_type))

func get_new_id_for_schemaless_node() -> String:
    return get_unique_an_id("GenericAssetNode")

func single_failed_result() -> SingleParseResult:
    var result: = SingleParseResult.new()
    result.success = false
    return result

func failed_leaf_result(single_result: SingleParseResult) -> TreeParseResult:
    var result: TreeParseResult = TreeParseResult.new()
    result.success = false
    if not single_result.asset_node:
        single_result.asset_node = HyAssetNode.new()
    result.add_root(single_result)
    result.first_failure_at = single_result
    return result

func parse_asset_node_tree(old_style: bool, asset_node_data: Dictionary, external_metadata: Dictionary, inference_hints: Dictionary) -> TreeParseResult:
    var single_result: = parse_asset_node_shallow(old_style, asset_node_data, external_metadata, inference_hints)
    if not single_result.success:
        print_debug("Failed to parse asset node %s" % asset_node_data.get("$NodeId", ""))
        push_error("Failed to parse asset node %s" % asset_node_data.get("$NodeId", ""))
        return failed_leaf_result(single_result)

    var cur_result: = TreeParseResult.new()
    cur_result.add_root(single_result)
    cur_result.root_node.shallow = false

    for conn_name in cur_result.root_node.connection_list:
        if cur_result.root_node.is_raw_connection_empty(conn_name):
            continue
        
        for conn_node_data in cur_result.root_node.get_raw_connected_nodes(conn_name):
            var conn_value_type: = SchemaManager.schema.get_an_connection_value_type(cur_result.root_node, conn_name)
            var infer_hints: Dictionary = { "output_value_type": conn_value_type }
            var branch_result: = parse_asset_node_tree(old_style, conn_node_data, external_metadata, infer_hints)

            cur_result.merge_results(branch_result)
            if branch_result.root_node:
                cur_result.root_node.append_node_to_connection(conn_name, branch_result.root_node)
    
    return cur_result

func parse_asset_node_shallow(old_style: bool, asset_node_data: Dictionary, external_metadata: Dictionary, inference_hints: Dictionary) -> SingleParseResult:
    if not asset_node_data:
        print_debug("Asset node data is empty")
        return single_failed_result()
    
    var result: SingleParseResult = SingleParseResult.new()
    result.is_existing_node_id = true

    if old_style and not inference_hints.get("asset_node_type", ""):
        var type_key_val: String = asset_node_data.get("Type", "NO_TYPE_KEY")
        var hinted_output_value_type: String = inference_hints.get("output_value_type", "")
        if not hinted_output_value_type:
            print_debug("Old-style inferring node, no hinted output type, cannot infer type")
            push_warning("Old-style inferring node, no hinted output type, cannot infer type")
            return single_failed_result()

        var inferred_node_type: String = SchemaManager.schema.resolve_asset_node_type(type_key_val, hinted_output_value_type)
        if not inferred_node_type or inferred_node_type == "Unknown":
            print_debug("Old-style inferring node type failed, returning null")
            push_error("Old-style inferring node type failed, returning null")
            return single_failed_result()
        else:
            result.is_existing_node_id = false
            asset_node_data["$NodeId"] = get_unique_an_id(SchemaManager.schema.get_id_prefix_for_node_type(inferred_node_type))
    
    var asset_node_type: String = inference_hints.get("asset_node_type", "")
    if not asset_node_type:
        if not asset_node_data.get("$NodeId", ""):
            result.is_existing_node_id = false
            var type_key: String = asset_node_data.get("Type", "NO_TYPE_KEY")
            var output_value_type: String = inference_hints.get("output_value_type", "")
            asset_node_type = SchemaManager.schema.resolve_asset_node_type(type_key, output_value_type)
            if not asset_node_type or asset_node_type == "Unknown":
                push_warning("No $NodeId from node data, fallback using output value type and 'Type' key also failed, the node will have an Unknown type")
                return parse_schemaless_asset_node(asset_node_data, external_metadata)

            asset_node_data["$NodeId"] = get_unique_an_id(SchemaManager.schema.get_id_prefix_for_node_type(asset_node_type))
        else:
            asset_node_type = SchemaManager.schema.infer_asset_node_type_from_id(asset_node_data["$NodeId"])

    if asset_node_type == "Unknown":
        return parse_schemaless_asset_node(asset_node_data, external_metadata)
    
    assert(asset_node_data.get("$NodeId", ""), "NodeId is required (should have been implicitly set if is old-style)")
    
    result.asset_node = HyAssetNode.new()
    var asset_node: = result.asset_node
    asset_node.an_node_id = asset_node_data["$NodeId"]
    if asset_node_type:
        asset_node.an_type = asset_node_type
    else:
        asset_node.an_type = SchemaManager.schema.infer_asset_node_type_from_id(asset_node_data["$NodeId"])
    
    var an_schema: Dictionary = {}
    if asset_node.an_type and asset_node.an_type != "Unknown":
        an_schema = SchemaManager.schema.node_schema.get(asset_node.an_type, {})
        if not an_schema:
            push_warning("Node schema not found for node type: %s" % asset_node.an_type)
            print_debug("Warning: Node schema not found for node type: %s" % asset_node.an_type)
    
    asset_node.raw_tree_data = asset_node_data.duplicate()
    
    setup_base_info_and_settings(asset_node, asset_node_data, an_schema, external_metadata)
    var connection_names: Array[String] = get_connection_like_keys(asset_node_data, an_schema)
    for setting_name in asset_node.settings.keys():
        if setting_name in connection_names:
            connection_names.erase(setting_name)
    # fill out stuff in the data as settings even if it isn't in the schema
    add_unknown_settings(asset_node, asset_node_data, connection_names, an_schema)
    
    for conn_name in connection_names:
        if not asset_node.connection_list.has(conn_name):
            asset_node.connection_list.append(conn_name)
            asset_node.connected_node_counts[conn_name] = 0
    
    result.success = true
    return result

func parse_schemaless_asset_node(asset_node_data: Dictionary, external_metadata: Dictionary) -> SingleParseResult:
    var result: SingleParseResult = SingleParseResult.new()
    var asset_node = HyAssetNode.new()
    asset_node.raw_tree_data = asset_node_data.duplicate()
    result.asset_node = asset_node

    asset_node.an_node_id = asset_node_data.get("$NodeId", "")
    if not asset_node.an_node_id:
        asset_node.an_node_id = get_new_id_for_schemaless_node()
        result.is_existing_node_id = false
    else:
        result.is_existing_node_id = true
    asset_node.an_type = "Unknown"
    
    setup_base_info_and_settings(asset_node, asset_node_data, {}, external_metadata)
    
    var connection_like_keys: Array[String] = get_connection_like_keys(asset_node_data, {})
    add_unknown_settings(asset_node, asset_node_data, connection_like_keys, {})
    
    for conn_name in connection_like_keys:
        asset_node.connection_list.append(conn_name)
        asset_node.connected_node_counts[conn_name] = 0
    
    return result


func setup_base_info_and_settings(asset_node: HyAssetNode, node_data: Dictionary, an_schema: Dictionary, external_metadata: Dictionary) -> void:
    var ext_meta: Dictionary = external_metadata.get(asset_node.an_node_id, {})

    if asset_node.an_type == "Unknown":
        asset_node.default_title = "Generic Node"
    else:
        asset_node.default_title = SchemaManager.schema.get_node_type_default_name(asset_node.an_type)

    if ext_meta.get("$Title", ""):
        asset_node.title = str(ext_meta["$Title"])
    elif node_data.get("$Title", ""):
        asset_node.title = str(node_data["$Title"])

    if not asset_node.title:
        asset_node.title = asset_node.default_title
    
    if node_data.get("$Comment", ""):
        asset_node.comment = str(node_data["$Comment"])
    
    var connections_schema: Dictionary = an_schema.get("connections", {})
    for conn_name in connections_schema.keys():
        asset_node.connection_list.append(conn_name)
        asset_node.connected_node_counts[conn_name] = 0
    
    var settings_schema: Dictionary = an_schema.get("settings", {})
    for setting_name in settings_schema.keys():
        asset_node.settings[setting_name] = settings_schema[setting_name].get("default_value", null)
        
        if node_data.has(setting_name):
            var gd_type: int = settings_schema[setting_name]["gd_type"]
            if gd_type == TYPE_ARRAY:
                var sub_gd_type: int = settings_schema[setting_name]["array_gd_type"]
                asset_node.settings[setting_name] = parse_individual_setting_data(node_data[setting_name], gd_type, sub_gd_type)
            else:
                asset_node.settings[setting_name] = parse_individual_setting_data(node_data[setting_name], gd_type)

func parse_individual_setting_data(raw_value: Variant, gd_type: int, sub_gd_type: int = -1) -> Variant:
    if gd_type == TYPE_INT:
        return roundi(float(raw_value))
    elif gd_type == TYPE_FLOAT:
        return float(raw_value)
    elif gd_type == TYPE_BOOL:
        return bool(raw_value)
    elif gd_type == TYPE_STRING:
        if not typeof(raw_value) == TYPE_STRING:
            print_debug("Warning: Setting is expected to be a string, but is not: %s" % [raw_value])
            push_warning("Setting is expected to be a string, but is not: %s" % [raw_value])
        return str(raw_value)
    elif gd_type == TYPE_ARRAY:
        if typeof(raw_value) != TYPE_ARRAY:
            push_error("Setting is expected to be an array, but is not: %s" % [raw_value])
            return []
        var array_val: Array = []
        for sub_raw_val in raw_value:
            array_val.append(parse_individual_setting_data(sub_raw_val, sub_gd_type))
        return array_val
    else:
        push_error("Unhandled setting gd type: %s" % [type_string(gd_type)])
        print_debug("Unhandled setting gd type: %s" % [type_string(gd_type)])
        return null

## Add other data that may be a setting but the node is schemaless or the setting isn't in the schema
func add_unknown_settings(asset_node: HyAssetNode, node_data: Dictionary, conn_keys: Array[String], an_schema: Dictionary) -> void:
    var settings_schema: Dictionary = an_schema.get("settings", {})
    
    for raw_key in node_data.keys():
        if raw_key.begins_with("$"):
            continue
        if asset_node.settings.has(raw_key) or settings_schema.has(raw_key) or conn_keys.has(raw_key):
            continue
        if an_schema.get("connections", {}).has(raw_key):
            continue

        asset_node.settings[raw_key] = node_data[raw_key]

func is_data_asset_node_like(data: Variant) -> bool:
    # TODO: do the proper checks here
    var data_type: int = typeof(data)
    if data_type == TYPE_DICTIONARY:
        return true
    elif data_type == TYPE_ARRAY:
        return true
    return false

func get_connection_like_keys(node_data: Dictionary, an_schema: Dictionary) -> Array[String]:
    var connection_like_keys: Array[String] = []
    connection_like_keys.append_array(an_schema.get("connections", {}).keys())
    
    for key in node_data.keys():
        if key.begins_with("$"):
            continue
        if is_data_asset_node_like(node_data[key]):
            connection_like_keys.append(key)
    return connection_like_keys

static func debug_dump_tree_results(tree_result: TreeParseResult) -> void:
    if not OS.has_feature("debug"):
        return
    if tree_result.success:
        print_debug("Tree results: All nodes succeeded")
        return
    
    print_debug("Failed parse asset node tree, results:")
    if tree_result.first_failure_at:
        print("  First failure at: %s (%s :: %s)" % [tree_result.first_failure_at.asset_node, tree_result.first_failure_at.asset_node.an_node_id, tree_result.first_failure_at.asset_node.an_type])
        print("    Is existing node ID: %s" % tree_result.first_failure_at.is_existing_node_id)

    var failure_count: int = 0
    for result in tree_result.all_nodes_results:
        if not result.success:
            failure_count += 1
    print("All Failures (%d):" % failure_count)
    for result in tree_result.all_nodes_results:
        if result.success:
            continue
        print("  Failed Node: %s (%s :: %s)" % [result.asset_node, result.asset_node.an_node_id, result.asset_node.an_type])
        print("    Is existing node ID: %s" % result.is_existing_node_id)