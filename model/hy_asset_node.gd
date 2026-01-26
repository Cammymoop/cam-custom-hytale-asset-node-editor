class_name HyAssetNode
extends Resource

@export var an_node_id: String = ""
@export var an_name: String = ""
@export var an_type: String = ""

@export var connections: Dictionary[String, Variant] = {}
@export var connection_list: Array[String] = []
@export var has_inner_asset_nodes: bool = false
@export var connected_asset_nodes: Dictionary[String, HyAssetNode] = {}
@export var connected_node_counts: Dictionary[String, int] = {}

@export var settings: Dictionary = {}

@export var raw_tree_data: Dictionary = {}

static var special_keys: Array[String] = ["Type"]

func is_connection_empty(conn_name: String) -> bool:
    if has_inner_asset_nodes:
        if not connection_list.has(conn_name):
            print_debug("Connection name %s not found in connection list" % conn_name)
            return true
        return connected_node_counts[conn_name] == 0

    if not connections.has(conn_name):
        print_debug("Connection name %s not found in connection names" % conn_name)
        return true
    if connections[conn_name] == null:
        return true
    var conn_type: = typeof(connections[conn_name])
    if conn_type == TYPE_DICTIONARY and connections[conn_name].is_empty():
        return true
    if conn_type == TYPE_ARRAY and connections[conn_name].size() == 0:
        return true
    return false

func num_connected_asset_nodes(conn_name: String) -> int:
    if has_inner_asset_nodes:
        return _num_connected_asset_nodes_full(conn_name)

    var conn_type: = typeof(connections[conn_name])
    if conn_type == TYPE_DICTIONARY:
        return 1
    if conn_type == TYPE_ARRAY:
        return connections[conn_name].size()
    return 0

func _num_connected_asset_nodes_full(conn_name: String) -> int:
    if not connected_node_counts.has(conn_name):
        return 0
    return connected_node_counts[conn_name]

func get_raw_connected_nodes(conn_name: String) -> Array[Dictionary]:
    var conn_data: Array[Dictionary] = []
    if typeof(connections[conn_name]) == TYPE_DICTIONARY:
        conn_data.append(connections[conn_name])
    else:
        conn_data.append_array(connections[conn_name])
    return conn_data


func set_connection(conn_name: String, index: int, asset_node: HyAssetNode) -> void:
    if not connection_list.has(conn_name):
        connection_list.append(conn_name)
        connected_node_counts[conn_name] = 1
    var conn_key: String = "%s:%d" % [conn_name, index]
    if connections.has(conn_name) and typeof(connections[conn_name]) == TYPE_DICTIONARY:
        if index > 0:
            print_debug("Index %s is greater than 0 on a single connection! (%s)" % [index, conn_name])
            return
    connected_asset_nodes[conn_key] = asset_node

func set_connection_count(conn_name: String, count: int) -> void:
    if not connection_list.has(conn_name):
        connection_list.append(conn_name)
    connected_node_counts[conn_name] = count


func append_node_to_connection(conn_name: String, asset_node: HyAssetNode) -> void:
    if not has_inner_asset_nodes:
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
    if not has_inner_asset_nodes:
        print_debug("Trying to append nodes to a shallow asset node (%s)" % an_node_id)
        return
    if not connection_list.has(conn_name):
        connection_list.append(conn_name)
    for i in asset_nodes.size():
        connected_asset_nodes["%s:%d" % [conn_name, i]] = asset_nodes[i]
    connected_node_counts[conn_name] = asset_nodes.size()

func remove_node_from_connection(conn_name: String, asset_node: HyAssetNode) -> void:
    if not has_inner_asset_nodes:
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

func remove_node_from_connection_at(conn_name: String, at_index: int) -> void:
    if not has_inner_asset_nodes:
        print_debug("Trying to remove node from a shallow asset node (%s) at index %s" % [an_node_id, at_index])
        return
    if at_index < 0 or at_index >= connected_node_counts[conn_name]:
        print_debug("Index %s is out of range for connection %s" % [at_index, conn_name])
        return

    connected_asset_nodes.erase("%s:%d" % [conn_name, at_index])
    _reindex_connection(conn_name)

func insert_node_into_connection_at(conn_name: String, at_index: int, asset_node: HyAssetNode) -> void:
    if at_index < 0 or at_index > connected_node_counts[conn_name]:
        print_debug("Index %s is out of range for connection %s" % [at_index, conn_name])
        return
    if connected_node_counts[conn_name] == at_index:
        append_node_to_connection(conn_name, asset_node)
    else:
        _reindex_connection(conn_name, -1, {at_index: asset_node})

func _reindex_connection(conn_name: String, max_index: int = -1, insert_nodes: Dictionary[int, HyAssetNode] = {}) -> void:
    if max_index < 0:
        max_index = connected_node_counts[conn_name]
    
    var new_list: Array[HyAssetNode] = []
    for i in range(max_index + 1):
        if connected_asset_nodes.has("%s:%d" % [conn_name, i]):
            new_list.append(connected_asset_nodes["%s:%d" % [conn_name, i]])
    
    var insert_at_indices = insert_nodes.keys()
    insert_at_indices.sort()
    for insert_idx in insert_at_indices:
        new_list.insert(insert_idx, insert_nodes[insert_idx])
    
    connected_node_counts[conn_name] = new_list.size()
    for i in range(new_list.size()):
        connected_asset_nodes["%s:%d" % [conn_name, i]] = new_list[i]

    

func get_connected_node(conn_name: String, index: int) -> HyAssetNode:
    if not has_inner_asset_nodes:
        print_debug("Trying to retrieve inner nodes of a shallow asset node (%s)" % an_node_id)
        return null
    if not connection_list.has(conn_name):
        print_debug("Connection name %s not found in connection list" % conn_name)
        return null
    return connected_asset_nodes["%s:%d" % [conn_name, index]]

func get_all_connected_nodes(conn_name: String) -> Array[HyAssetNode]:
    if not has_inner_asset_nodes:
        print_debug("Trying to retrieve inner nodes of a shallow asset node (%s)" % an_node_id)
        return []
    if not connection_list.has(conn_name):
        print_debug("Connection name %s not found in connection list" % conn_name)
        return []

    return _get_connected_node_list(conn_name)

func _get_connected_node_list(conn_name: String) -> Array[HyAssetNode]:
    var node_list: Array[HyAssetNode] = []
    for i in range(connected_node_counts[conn_name]):
        node_list.append(connected_asset_nodes["%s:%d" % [conn_name, i]])
    return node_list