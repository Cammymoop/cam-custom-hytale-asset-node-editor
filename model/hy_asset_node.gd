class_name HyAssetNode
extends Resource

signal settings_changed()

@export var an_node_id: String = ""
@export var an_type: String = ""

@export var title: String = ""
@export var default_title: String = ""
@export var comment: String = ""

@export var connection_list: Array[String] = []
@export var shallow: bool = true
@export var connected_asset_nodes: Dictionary[String, HyAssetNode] = {}
@export var connected_node_counts: Dictionary[String, int] = {}

@export var settings: Dictionary = {}

@export var raw_tree_data: Dictionary = {}

@export var other_metadata: Dictionary = {}

static var special_keys: Array[String] = ["Type"]

func is_raw_connection_empty(conn_name: String) -> bool:
    if not connection_list.has(conn_name):
        print_debug("Connection name %s not found in connection list" % conn_name)
        return true
    if not raw_tree_data.has(conn_name):
        return true
    if typeof(raw_tree_data[conn_name]) == TYPE_DICTIONARY and raw_tree_data[conn_name].is_empty():
        return true
    elif typeof(raw_tree_data[conn_name]) == TYPE_ARRAY and raw_tree_data[conn_name].size() == 0:
        return true
    return false

func get_raw_connected_nodes(conn_name: String) -> Array:
    if not raw_tree_data.has(conn_name):
        return []

    if typeof(raw_tree_data[conn_name]) == TYPE_DICTIONARY:
        return [raw_tree_data[conn_name]]
    elif typeof(raw_tree_data[conn_name]) == TYPE_ARRAY:
        return raw_tree_data[conn_name]
    else:
        print_debug("get_raw_connected_nodes: Connection %s is of an unhandled type: %s" % [conn_name, type_string(typeof(raw_tree_data[conn_name]))])
        return []


func num_connected_asset_nodes(conn_name: String) -> int:
    if not connected_node_counts.has(conn_name):
        return 0
    return connected_node_counts[conn_name]

func update_setting_value(setting_name: String, value: Variant) -> void:
    settings[setting_name] = value
    settings_changed.emit()


func set_connection(conn_name: String, index: int, asset_node: HyAssetNode) -> void:
    if not connection_list.has(conn_name):
        connection_list.append(conn_name)
        connected_node_counts[conn_name] = 0
    var conn_key: String = "%s:%d" % [conn_name, index]
    var was_set: = connected_asset_nodes.has(conn_key)
    connected_asset_nodes[conn_key] = asset_node
    if not was_set:
        connected_node_counts[conn_name] += 1

func set_connection_count(conn_name: String, count: int) -> void:
    if not connection_list.has(conn_name):
        connection_list.append(conn_name)
    connected_node_counts[conn_name] = count


func append_node_to_connection(conn_name: String, asset_node: HyAssetNode) -> void:
    if shallow:
        print_debug("Trying to append node to a shallow asset node (%s)" % an_node_id)
        return
    if not connected_asset_nodes.has("%s:0" % conn_name):
        if not connection_list.has(conn_name):
            connection_list.append(conn_name)
        connected_asset_nodes["%s:0" % conn_name] = asset_node
        connected_node_counts[conn_name] = 1
    else:
        var next_index: int = connected_node_counts[conn_name]
        connected_asset_nodes["%s:%d" % [conn_name, next_index]] = asset_node
        connected_node_counts[conn_name] = next_index + 1

func append_nodes_to_connection(conn_name: String, asset_nodes: Array[HyAssetNode]) -> void:
    if shallow:
        print_debug("Trying to append nodes to a shallow asset node (%s)" % an_node_id)
        return
    if not connection_list.has(conn_name):
        connection_list.append(conn_name)
    for i in asset_nodes.size():
        connected_asset_nodes["%s:%d" % [conn_name, i]] = asset_nodes[i]
    connected_node_counts[conn_name] = asset_nodes.size()

func remove_node_from_connection(conn_name: String, asset_node: HyAssetNode) -> void:
    if shallow:
        print_debug("Trying to remove node from a shallow asset node (%s)" % an_node_id)
        return
    var found_at_idx: int = -1
    for i in range(connected_node_counts[conn_name]):
        if connected_asset_nodes["%s:%d" % [conn_name, i]] == asset_node:
            found_at_idx = i
            break
    if found_at_idx < 0:
        print_debug("Node %s not found in connection %s" % [asset_node.an_node_id, conn_name])
        return

    remove_node_from_connection_at(conn_name, found_at_idx)

func pop_node_from_connection(conn_name: String) -> HyAssetNode:
    if shallow:
        print_debug("Trying to pop node from a shallow asset node (%s)" % an_node_id)
        return null
    if not connection_list.has(conn_name):
        print_debug("Connection name %s not found in connection list" % conn_name)
        return null
    if connected_node_counts[conn_name] == 0:
        return null
    var popped_node: = get_connected_node(conn_name, connected_node_counts[conn_name] - 1)
    remove_node_from_connection_at(conn_name, connected_node_counts[conn_name] - 1)
    return popped_node

func remove_node_from_connection_at(conn_name: String, at_index: int) -> void:
    if shallow:
        print_debug("Trying to remove node from a shallow asset node (%s) at index %s" % [an_node_id, at_index])
        return
    if at_index < 0 or at_index >= connected_node_counts[conn_name]:
        print_debug("Index %s is out of range for connection %s" % [at_index, conn_name])
        return
    
    connected_asset_nodes.erase("%s:%d" % [conn_name, at_index])
    if at_index == connected_node_counts[conn_name] - 1:
        connected_node_counts[conn_name] -= 1
    else:
        _reindex_connection(conn_name)


func insert_node_into_connection_at(conn_name: String, at_index: int, asset_node: HyAssetNode) -> void:
    if at_index < 0 or at_index > connected_node_counts[conn_name]:
        print_debug("Index %s is out of range for connection %s" % [at_index, conn_name])
        return
    if connected_node_counts[conn_name] == at_index:
        append_node_to_connection(conn_name, asset_node)
    else:
        _reindex_connection(conn_name, -1, {at_index: asset_node})

func remove_indices_from_connection(conn_name: String, indices: Array[int]) -> void:
    for idx in indices:
        connected_asset_nodes.erase("%s:%d" % [conn_name, idx])
    _reindex_connection(conn_name)

func _reindex_connection(conn_name: String, max_index: int = -1, insert_nodes: Dictionary[int, HyAssetNode] = {}) -> void:
    if max_index < 0:
        max_index = connected_node_counts[conn_name]
    
    var new_list: Array[HyAssetNode] = []
    for old_index in range(max_index):
        if connected_asset_nodes.has("%s:%d" % [conn_name, old_index]):
            new_list.append(connected_asset_nodes["%s:%d" % [conn_name, old_index]])
    
    var insert_at_indices = insert_nodes.keys()
    insert_at_indices.sort()
    for insert_idx in insert_at_indices:
        new_list.insert(insert_idx, insert_nodes[insert_idx])
    
    connected_node_counts[conn_name] = new_list.size()
    for new_index in max_index:
        if new_index < new_list.size():
            connected_asset_nodes["%s:%d" % [conn_name, new_index]] = new_list[new_index]
        else:
            connected_asset_nodes.erase("%s:%d" % [conn_name, new_index])

## Given a new NodeID returns a new copy with all the same data but no connected asset nodes
func get_shallow_copy(new_id: String) -> HyAssetNode:
    var new_asset_node: = HyAssetNode.new()
    new_asset_node.an_node_id = new_id
    new_asset_node.an_type = an_type
    new_asset_node.title = title
    new_asset_node.default_title = default_title
    new_asset_node.comment = comment
    new_asset_node.settings = settings.duplicate_deep()
    new_asset_node.connection_list = connection_list.duplicate()
    for conn_name in connection_list:
        new_asset_node.connected_node_counts[conn_name] = 0
    # it's a shallow copy, but it doesn't have unpopulated connections
    new_asset_node.shallow = false
    return new_asset_node
    

func get_connected_node(conn_name: String, index: int) -> HyAssetNode:
    if shallow:
        print_debug("Trying to retrieve inner nodes of a shallow asset node (%s)" % an_node_id)
        return null
    if not connection_list.has(conn_name):
        print_debug("Connection name %s not found in connection list" % conn_name)
        return null
    return connected_asset_nodes["%s:%d" % [conn_name, index]]

func get_all_connected_nodes(conn_name: String) -> Array[HyAssetNode]:
    if shallow:
        print_debug("Trying to retrieve inner nodes of a shallow asset node (%s)" % an_node_id)
        return []
    if not connection_list.has(conn_name):
        print_debug("Connection name %s not found in connection list %s" % [conn_name, connection_list])
        return []

    return _get_connected_node_list(conn_name)

func _get_connected_node_list(conn_name: String) -> Array[HyAssetNode]:
    var node_list: Array[HyAssetNode] = []
    for i in range(connected_node_counts[conn_name]):
        node_list.append(connected_asset_nodes["%s:%d" % [conn_name, i]])
    return node_list

func sort_connections_by_gn_pos(gn_lookup: Dictionary[String, GraphNode]) -> void:
    var sort_by_gn_pos: = func (a: HyAssetNode, b: HyAssetNode) -> bool:
        var a_gn: = gn_lookup.get(a.an_node_id, null) as GraphNode
        var b_gn: = gn_lookup.get(b.an_node_id, null) as GraphNode
        if not a_gn or not b_gn:
            return a_gn != null
        elif a_gn.position_offset.y != b_gn.position_offset.y:
            return a_gn.position_offset.y < b_gn.position_offset.y
        else:
            return a_gn.position_offset.x < b_gn.position_offset.x
    
    var conn_names: Array[String] = connection_list
    for conn_name in conn_names:
        var sorted_nodes: Array[HyAssetNode] = get_all_connected_nodes(conn_name)
        if sorted_nodes.size() < 2:
            continue
        sorted_nodes.sort_custom(sort_by_gn_pos)
        for i in range(sorted_nodes.size()):
            connected_asset_nodes["%s:%d" % [conn_name, i]] = sorted_nodes[i]

func enumerate_connected_tree() -> Array[HyAssetNode]:
    var node_list: Array[HyAssetNode] = [self]
    for connected_node in connected_asset_nodes.values():
        node_list.append_array(connected_node.enumerate_connected_tree())
    return node_list