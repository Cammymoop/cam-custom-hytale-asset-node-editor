extends Node
class_name CHANE_HyAssetNodeSerializer


class MetadataKeys:
    const NodeId: String = "$NodeId"
    
    const NodeEditorMetadata: String = "$NodeEditorMetadata"

    const NodeMetaPosition: String = "$Position"
    const NodeMetaPosX: String = "$x"
    const NodeMetaPosY: String = "$y"
    const NodeMetaTitle: String = "$Title"

    const NodeComment: String = "$Comment"

    const NodesMeta: String = "$Nodes"
    const WorkspaceId: String = "$WorkspaceID"
    const Groups: String = "$Groups"
    const Comments: String = "$Comments"
    const Links: String = "$Links"
    const FloatingRoots: String = "$FloatingNodes"
    
    const GroupName: String = "$name"
    const GroupPosition: String = "$Position"
    const GroupPosX: String = "$x"
    const GroupPosY: String = "$y"
    const GroupWidth: String = "$width"
    const GroupHeight: String = "$height"
    # CHANE custom
    const CHANEGroupAccentColor: String = "$AccentColor"
    
    const CHANE: String = "$CHANE"

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

var serialized_pos_scale: Vector2 = Vector2.ONE
var serialized_pos_offset: Vector2 = Vector2.ZERO

static func get_unique_an_id(prefix: String) -> String:
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

# Deserializing

func parse_asset_node_tree(old_style: bool, asset_node_data: Dictionary, external_metadata: Dictionary, inference_hints: Dictionary) -> TreeParseResult:
    # Note: external_metadata only needed currently for titles (non-old-style)
    var single_result: = parse_asset_node_shallow(old_style, asset_node_data, external_metadata, inference_hints)
    if not single_result.success:
        print_debug("Failed to parse asset node %s" % asset_node_data.get(MetadataKeys.NodeId, ""))
        push_error("Failed to parse asset node %s" % asset_node_data.get(MetadataKeys.NodeId, ""))
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
    # Note: external_metadata only needed currently for titles (non-old-style)
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
            asset_node_data[MetadataKeys.NodeId] = get_unique_an_id(SchemaManager.schema.get_id_prefix_for_node_type(inferred_node_type))
    
    var asset_node_type: String = inference_hints.get("asset_node_type", "")
    if not asset_node_type:
        if not asset_node_data.get(MetadataKeys.NodeId, ""):
            result.is_existing_node_id = false
            var type_key: String = asset_node_data.get("Type", "NO_TYPE_KEY")
            var output_value_type: String = inference_hints.get("output_value_type", "")
            asset_node_type = SchemaManager.schema.resolve_asset_node_type(type_key, output_value_type)
            if not asset_node_type or asset_node_type == "Unknown":
                push_warning("No %s from node data, fallback using output value type and 'Type' key also failed, the node will have an Unknown type" % MetadataKeys.NodeId)
                return parse_schemaless_asset_node(asset_node_data, external_metadata)

            asset_node_data[MetadataKeys.NodeId] = get_unique_an_id(SchemaManager.schema.get_id_prefix_for_node_type(asset_node_type))
        else:
            asset_node_type = SchemaManager.schema.infer_asset_node_type_from_id(asset_node_data[MetadataKeys.NodeId])

    if asset_node_type == "Unknown":
        return parse_schemaless_asset_node(asset_node_data, external_metadata)
    
    assert(asset_node_data.get(MetadataKeys.NodeId, ""), "NodeId is required (should have been implicitly set if is old-style)")
    
    result.asset_node = HyAssetNode.new()
    var asset_node: = result.asset_node
    asset_node.an_node_id = asset_node_data[MetadataKeys.NodeId]
    if asset_node_type:
        asset_node.an_type = asset_node_type
    else:
        asset_node.an_type = SchemaManager.schema.infer_asset_node_type_from_id(asset_node_data[MetadataKeys.NodeId])
    
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

    asset_node.an_node_id = asset_node_data.get(MetadataKeys.NodeId, "")
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

    if ext_meta.get(MetadataKeys.NodeMetaTitle, ""):
        asset_node.title = str(ext_meta[MetadataKeys.NodeMetaTitle])
    elif node_data.get(MetadataKeys.NodeMetaTitle, ""):
        # legacy spot for title
        asset_node.title = str(node_data[MetadataKeys.NodeMetaTitle])

    if not asset_node.title:
        asset_node.title = asset_node.default_title
    
    if node_data.get(MetadataKeys.NodeComment, ""):
        # note: yes comments are stored in the node data not editor metadata
        asset_node.comment = str(node_data[MetadataKeys.NodeComment])
    
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


# Serializing

func _node_meta_position(pos: Vector2) -> Dictionary:
    return { MetadataKeys.NodeMetaPosX: pos.x, MetadataKeys.NodeMetaPosY: pos.y, }

func get_serialize_scaled_pos(graph_pos: Vector2) -> Vector2:
    return (graph_pos / serialized_pos_scale).round()

func get_serialize_offset_scaled_pos(graph_pos: Vector2) -> Vector2:
    return get_serialize_scaled_pos(graph_pos - serialized_pos_offset)


func serialize_an_metadata_into(asset_node: HyAssetNode, graph_pos: Vector2, into_dict: Dictionary) -> void:
    into_dict[asset_node.an_node_id] = serialize_an_metadata(asset_node, graph_pos)

func serialize_an_metadata(asset_node: HyAssetNode, graph_pos: Vector2) -> Dictionary:
    var an_meta: = {
        MetadataKeys.NodeMetaPosition: _node_meta_position(get_serialize_offset_scaled_pos(graph_pos)),
    }
    if asset_node.title and asset_node.title != asset_node.default_title:
        an_meta[MetadataKeys.NodeMetaTitle] = asset_node.title
    return an_meta

## Creates plain dictionary data in the hytale asset json format, mimicking the format used by the official asset node editor
func serialize_entire_graph_as_asset(graph_edit: CHANE_AssetNodeGraphEdit) -> Dictionary:
    # Make the reference position and scale is set up
    serialized_pos_scale = graph_edit.json_positions_scale
    serialized_pos_offset = graph_edit.relative_root_position
    # The root asset node is also the root dictionary of the asset json format
    var serialized_data: Dictionary = serialize_asset_node_tree(graph_edit.root_node)
    # Floating trees are included in the node editor metadata
    serialized_data[MetadataKeys.NodeEditorMetadata] = serialize_node_editor_metadata(graph_edit)
    return serialized_data

func serialize_multiple_an_trees(an_trees: Array[HyAssetNode]) -> Array[Dictionary]:
    var serialized_an_trees: Array[Dictionary] = []
    for tree_root in an_trees:
        serialized_an_trees.append(serialize_asset_node_tree(tree_root))
    return serialized_an_trees


func serialize_node_editor_metadata(graph_edit: CHANE_AssetNodeGraphEdit) -> Dictionary:
    var serialized_node_meta: Dictionary = {}
    var root_gn: = graph_edit.get_root_graph_node()
    if not root_gn:
        push_error("Serialize Node Editor Metadata: Root node graph node not found")
        return {}
    var fallback_pos: = get_serialize_offset_scaled_pos(root_gn.position_offset - Vector2(200, 200))
    
    var an_owners: Dictionary[HyAssetNode, GraphNode] = {}
    for gn in get_children():
        if not gn is CustomGraphNode:
            continue
        if not gn.get_meta("is_special_gn", false):
            var an_id: String = gn.get_meta("hy_asset_node_id", "")
            assert(graph_edit.an_lookup.has(an_id), "Serialize Node Editor Metadata: Asset node not found for graph node %s with id %s" % [gn.name, an_id])
            if graph_edit.an_lookup.has(an_id):
                an_owners[graph_edit.an_lookup[an_id]] = gn
        else:
            for owned_an in gn.get_own_asset_nodes():
                an_owners[owned_an] = gn

    for an in graph_edit.all_asset_nodes:
        if OS.has_feature("debug"):
            if not an_owners.has(an):
                push_error("Serialize Node Editor Metadata: Asset node %s not found in an_owners" % an.an_node_id)
                print_debug("Serialize Node Editor Metadata: Asset node %s not found in an_owners" % an.an_node_id)

        var owner_gn: GraphNode = an_owners.get(an, null)
        if not owner_gn:
            # Fallback in-case no position can be determinded
            serialize_an_metadata_into(an, fallback_pos, serialized_node_meta)
            continue
        # Let the owning graph node determine the position to use
        owner_gn.add_an_metadata_into(an, self, serialized_node_meta)

    var serialized_metadata: Dictionary = {
        MetadataKeys.NodesMeta: serialized_node_meta,
    }

    serialized_metadata[MetadataKeys.FloatingRoots] = serialize_multiple_an_trees(graph_edit.floating_tree_roots)

    serialized_metadata[MetadataKeys.WorkspaceId] = graph_edit.hy_workspace_id
    
    serialized_metadata[MetadataKeys.Groups] = graph_edit.serialize_all_groups()
    
    # include other metadata we found in the file but don't do anything with
    for other_key in graph_edit.all_meta.keys():
        if serialized_metadata.has(other_key):
            continue
        serialized_metadata[other_key] = graph_edit.all_meta[other_key]
    return serialized_metadata

func serialize_graph_edit_groups(graph_edit: CHANE_AssetNodeGraphEdit) -> Array[Dictionary]:
    return serialize_groups(graph_edit.get_all_groups())

func serialize_groups(the_groups: Array[GraphFrame]) -> Array[Dictionary]:
    var serialized_groups: Array[Dictionary] = []
    for group in the_groups:
        serialized_groups.append(serialize_group(group))
    return serialized_groups

func serialize_group(group: GraphFrame) -> Dictionary:
    var adjusted_size: = get_serialize_scaled_pos(group.size)
    var adjusted_pos: = get_serialize_offset_scaled_pos(group.position_offset)

    var serialized_group: Dictionary = {
        MetadataKeys.GroupName: group.title,
        MetadataKeys.GroupPosition: {
            MetadataKeys.GroupPosX: adjusted_pos.x,
            MetadataKeys.GroupPosY: adjusted_pos.y,
        },
        MetadataKeys.GroupWidth: adjusted_size.x,
        MetadataKeys.GroupHeight: adjusted_size.y,
    }
    if group.get_meta("has_custom_color", false):
        serialized_group[MetadataKeys.CHANEGroupAccentColor] = group.get_meta("custom_color_name", "")
    return serialized_group

## Creates plain dictionary data for saving to json of the limited asset node tree from the given node passing through only nodes included in the included_asset_nodes set
## returns an empty dictionary if the given asset node is not in the set
func serialize_asset_node_tree_within_set(asset_node: HyAssetNode, included_asset_nodes: Array[HyAssetNode]) -> Dictionary:
    if asset_node not in included_asset_nodes:
        return {}
    
    return serialize_asset_node_tree(asset_node, included_asset_nodes)

## Creates plain dictionary data for saving to json including the entire asset node tree from the given node
## if included_asset_nodes is provided, the tree will stop at any nodes not included in the set and that subtree will be omitted
func serialize_asset_node_tree(asset_node: HyAssetNode, included_asset_nodes: Array[HyAssetNode] = []) -> Dictionary:
    if asset_node.shallow:
        push_warning("Serializing unpopulated asset node (%s)" % asset_node.an_node_id)
        print_debug("Serializing unpopulated asset node (%s)" % asset_node.an_node_id)
        return asset_node.raw_tree_data.duplicate(true)
    
    var serialized_data: Dictionary = {MetadataKeys.NodeId: asset_node.an_node_id}
    if asset_node.comment:
        serialized_data[MetadataKeys.NodeComment] = asset_node.comment
    
    for other_key in asset_node.other_metadata.keys():
        serialized_data[other_key] = asset_node.other_metadata[other_key]
    
    var an_type: String = asset_node.an_type
    
    if not an_type or an_type == "Unknown" or not SchemaManager.schema.node_schema.has(an_type):
        print_debug("Warning: Serializing an asset node with unknown type: %s (%s)" % [an_type, asset_node.an_node_id])
        push_warning("Warning: Serializing an asset node with unknown type: %s (%s)" % [an_type, asset_node.an_node_id])
        serialized_data[MetadataKeys.CHANE] = { "no_schema": true }
        # handling "Type" key
        if "Type" in asset_node.raw_tree_data:
            serialized_data["Type"] = asset_node.raw_tree_data["Type"]
        # settings
        for setting_key in asset_node.settings.keys():
            serialized_data[setting_key] = asset_node.settings[setting_key]
        # subtree
        for conn_name in asset_node.connection_list:
            var num_connected: = asset_node.num_connected_asset_nodes(conn_name)
            if num_connected == 0:
                continue

            if num_connected > 1:
                serialized_data[conn_name] = []
                for connected_an in asset_node.get_all_connected_nodes(conn_name):
                    if not included_asset_nodes or connected_an in included_asset_nodes:
                        serialized_data[conn_name].append(serialize_asset_node_tree(connected_an, included_asset_nodes))
            else:
                var connected_an: = asset_node.get_connected_node(conn_name, 0)
                if not included_asset_nodes or connected_an in included_asset_nodes:
                    serialized_data[conn_name] = serialize_asset_node_tree(connected_an, included_asset_nodes)
    else:
        var an_schema: = SchemaManager.schema.node_schema[an_type]
        
        # handling "Type" key
        var serialized_type_key: Variant = SchemaManager.schema.connection_type_node_type_lookup.find_key(an_type)
        if serialized_type_key and serialized_type_key.split("|", false).size() > 1:
            serialized_data["Type"] = serialized_type_key.split("|")[1]

        # settings
        var an_settings: = asset_node.settings
        for setting_key in an_schema.get("settings", {}).keys():
            var gd_type: int = an_schema["settings"][setting_key]["gd_type"]
            var sub_gd_type: int = an_schema["settings"][setting_key].get("array_gd_type", -1)
            var serialized_value: Variant = serialize_individual_setting_data(an_settings[setting_key], gd_type, sub_gd_type)
            if serialized_value != null:
                serialized_data[setting_key] = serialized_value

        # subtree
        for conn_name in an_schema.get("connections", {}).keys():
            var num_connected: = asset_node.num_connected_asset_nodes(conn_name)
            if num_connected == 0:
                # default behavior is to not include empty connections as keys
                continue
            var connected_nodes: Array[Dictionary] = []
            for connected_an in asset_node.get_all_connected_nodes(conn_name):
                if not included_asset_nodes or connected_an in included_asset_nodes:
                    connected_nodes.append(serialize_asset_node_tree(connected_an, included_asset_nodes))

            if an_schema["connections"][conn_name].get("multi", false):
                serialized_data[conn_name] = connected_nodes
            else:
                serialized_data[conn_name] = connected_nodes[0]

    return serialized_data

func serialize_individual_setting_data(raw_value: Variant, gd_type: int, sub_gd_type: int = -1) -> Variant:
    if gd_type == TYPE_STRING:
        if str(raw_value) == "":
            return null
    elif gd_type == TYPE_BOOL:
        return bool(raw_value)
    elif gd_type == TYPE_INT:
        if typeof(raw_value) == TYPE_FLOAT:
            return roundi(raw_value)
        elif typeof(raw_value) == TYPE_STRING:
            return roundi(float(raw_value))
    elif gd_type == TYPE_ARRAY:
        if sub_gd_type == TYPE_INT and typeof(raw_value) == TYPE_ARRAY:
            var arr: Array[int] = []
            for i in raw_value.size():
                if typeof(raw_value[i]) == TYPE_INT:
                    arr.append(raw_value[i])
                else:
                    arr.append(roundi(float(raw_value[i])))
            return arr

    return raw_value