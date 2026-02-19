class_name CHANE_AssetNodeFragment
extends Object

const FragmentRoot: = preload("res://graph_editor/fragment_root.gd")

var format_version: int = 1

var fragment_id: String
var source_description: String

var gd_node_tree: FragmentRoot
var gd_nodes_are_for_editor: CHANE_AssetNodeEditor
var serialized_data: String

var context_data: Dictionary[String, Variant] = {}

static func get_new_fragment_id() -> String:
    return Util.random_str(16)

static func new_from_string(fragment_string: String, source_desc: String, with_fragment_id: String = "") -> CHANE_AssetNodeFragment:
    var new_fragment: = CHANE_AssetNodeFragment.new()
    new_fragment.fragment_id = with_fragment_id if with_fragment_id else get_new_fragment_id()
    new_fragment.source_description = source_desc
    new_fragment.serialized_data = fragment_string
    return new_fragment

static func new_for_editor(for_editor: CHANE_AssetNodeEditor, with_fragment_id: String = "") -> CHANE_AssetNodeFragment:
    var new_fragment: = CHANE_AssetNodeFragment.new()
    new_fragment.fragment_id = with_fragment_id if with_fragment_id else get_new_fragment_id()
    new_fragment.gd_nodes_are_for_editor = for_editor
    new_fragment.source_description = "CamHytaleANE:%s" % Util.get_plain_version()
    return new_fragment

func has_node_tree() -> bool:
    return gd_node_tree != null and is_instance_valid(gd_node_tree)

func get_asset_node_trees() -> Array[HyAssetNode]:
    if not has_node_tree():
        push_error("No node tree to get asset node trees from")
        return []
    return gd_node_tree.get_an_tree_roots()

func get_all_included_asset_nodes() -> Array[HyAssetNode]:
    if not has_node_tree():
        push_error("No node tree to get asset nodes from")
        return []
    return gd_node_tree.get_all_asset_nodes()

func get_gd_nodes(for_editor: CHANE_AssetNodeEditor, disown: bool = true) -> Node:
    var editor_matches: = gd_nodes_are_for_editor != null and for_editor == gd_nodes_are_for_editor
    if has_node_tree() and not editor_matches:
        if not serialized_data:
            _create_serialized_data(for_editor)
        if not _make_nodes(for_editor):
            return null
    elif not has_node_tree():
        if not _make_nodes(for_editor):
            return null
    
    var fragment_root_node: = gd_node_tree
    if disown:
        disown_nodes()
    return fragment_root_node

func disown_nodes() -> void:
    gd_nodes_are_for_editor = null
    gd_node_tree = null

func discard_nodes() -> void:
    gd_node_tree.queue_free()
    gd_node_tree = null

func _make_nodes(for_editor: CHANE_AssetNodeEditor) -> bool:
    if not serialized_data:
        push_error("No serialized data to create nodes from")
        return false
    if has_node_tree():
        discard_nodes()
    context_data.clear()
    
    gd_nodes_are_for_editor = for_editor
    return _deserialize_data()


func _create_serialized_data(from_editor: CHANE_AssetNodeEditor = null) -> bool:
    if not has_node_tree():
        push_error("No Godot nodes to create serialized data from")
        return false

    if from_editor:
        gd_nodes_are_for_editor = from_editor
    if not gd_nodes_are_for_editor or not is_instance_valid(gd_nodes_are_for_editor):
        push_error("No editor context to create serialized data from")
        return false
    
    return _do_serialize()

func _do_serialize() -> bool:
    var serializer: = gd_nodes_are_for_editor.serializer

    var asset_node_data: Array[Dictionary] = []
    for asset_node in get_asset_node_trees():
        var serialized_an_tree: = serializer.serialize_asset_node_tree(asset_node)
        if serialized_an_tree:
            asset_node_data.append(serialized_an_tree)
        else:
            push_warning("Serialized asset node data for tree with root %s is empty" % asset_node.an_node_id)
    
    var full_data: Dictionary[String, Variant] = {
        "format_version": format_version,
        "what_is_this": "Copied data from Cam Hytale Asset Node Editor",
        "copied_from": source_description,
        "workspace_id": gd_nodes_are_for_editor.hy_workspace_id,
        "asset_node_data": asset_node_data,
        "inlcuded_metadata": _serialize_metadata(),
        "fragment_context": context_data,
    }
    serialized_data = JSON.stringify(full_data, "", false)
    
    return true

func _serialize_metadata() -> Dictionary:
    const MetadataKeys: = CHANE_HyAssetNodeSerializer.MetadataKeys
    var serializer: = gd_nodes_are_for_editor.serializer

    var serialized_groups: Array = []
    var included_groups: Array[GraphFrame] = Util.engine_class_filtered(gd_node_tree.get_all_graph_elements(), "GraphFrame")
    if included_groups.size() > 0:
        serialized_groups = serializer.serialize_groups(included_groups)

    var serialized_editor_metadata: Dictionary = {
        MetadataKeys.NodesMeta: serializer.serialize_ans_metadata(get_all_included_asset_nodes(), gd_node_tree.asset_node_aux_data),
        MetadataKeys.Links: [],
        MetadataKeys.Groups: serialized_groups,
        MetadataKeys.WorkspaceId: gd_nodes_are_for_editor.hy_workspace_id,
    }
    
    var included_metadata: Dictionary = {
        MetadataKeys.NodeEditorMetadata: serialized_editor_metadata,
        "hanging_connections": context_data.get("hanging_connections", []),
    }

    return included_metadata

func _deserialize_data() -> bool:
    assert(gd_nodes_are_for_editor, "Editor context is required to deserialize data")
    var editor: = gd_nodes_are_for_editor

    var json_result: Variant = JSON.parse_string(serialized_data)
    if not json_result or typeof(json_result) != TYPE_DICTIONARY:
        push_error("Failed to parse serialized data as dictionary")
        return false
    
    var data: = json_result as Dictionary
    
    # format version check goes here in the future
    
    if not check_compatible_workspace(data.get("workspace_id", "")):
        print_debug("Workspace ID %s is not compatible with this editor" % data.get("workspace_id", ""))
        return false
    
    var serializer: = editor.serializer
    var editor_metadata: = data.get("inlcuded_metadata", {}).get(CHANE_HyAssetNodeSerializer.MetadataKeys.NodeEditorMetadata, {}) as Dictionary
    var graph_result: = serializer.deserialize_fragment_as_full_graph(data.get("asset_node_data", []), editor_metadata)
    if not graph_result.success:
        return false
    
    var fragment_root: = FragmentRoot.new()
    fragment_root.asset_nodes_from_graph_parse_result(graph_result)
    
    var an_roots: Array[HyAssetNode] = fragment_root.get_an_tree_roots()
    var new_graph_nodes_by_asset_node: Dictionary[HyAssetNode, CustomGraphNode] = {}
    #var all_connections: Array[Dictionary] = []
    var all_graph_elements: Array[GraphElement] = []

    for tree_root in an_roots:
        var tree_new: = editor.new_graph_nodes_for_tree(tree_root, Vector2.ZERO, graph_result.asset_node_aux_data)
        new_graph_nodes_by_asset_node.merge(tree_new)

        var unique_graph_elements: Array[GraphElement] = []
        for ge in tree_new.values():
            if not unique_graph_elements.has(ge):
                unique_graph_elements.append(ge)
        all_graph_elements.append_array(unique_graph_elements)
        
        #all_connections.append_array(editor.get_new_gn_connections(tree_new[tree_root], tree_new))
    
    return true

func check_compatible_workspace(workspace_id: String) -> bool:
    return gd_nodes_are_for_editor.is_workspace_id_compatible(workspace_id)


func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if gd_node_tree and is_instance_valid(gd_node_tree):
            gd_node_tree.queue_free()
            gd_node_tree = null