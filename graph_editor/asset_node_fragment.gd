extends RefCounted

const Fragment: = preload("./asset_node_fragment.gd")
const FragmentRoot: = preload("./fragment_root.gd")

var format_version: int = 1

var fragment_id: String
var is_cut_fragment: bool = false
var source_description: String

var gd_node_tree: FragmentRoot
var gd_nodes_are_for_editor: CHANE_AssetNodeEditor
var serialized_data: String

var context_data: Dictionary[String, Variant] = {}

static func get_new_fragment_id() -> String:
    return Util.random_str(16)

static func new_from_string(fragment_string: String, source_desc: String, with_fragment_id: String = "") -> Fragment:
    var new_fragment: = new()
    new_fragment.fragment_id = with_fragment_id if with_fragment_id else get_new_fragment_id()
    new_fragment.source_description = source_desc
    new_fragment.serialized_data = fragment_string
    return new_fragment

static func new_for_editor(for_editor: CHANE_AssetNodeEditor, with_fragment_id: String = "") -> Fragment:
    var new_fragment: = new()
    new_fragment.fragment_id = with_fragment_id if with_fragment_id else get_new_fragment_id()
    new_fragment.gd_nodes_are_for_editor = for_editor
    new_fragment.source_description = "CamHytaleANE:%s" % Util.get_plain_version()
    return new_fragment

static func new_duplicate_fragment(fragment: Fragment) -> Fragment:
    var new_fragment: Fragment
    if fragment.has_node_tree():
        new_fragment = new_for_editor(fragment.gd_nodes_are_for_editor)
        fragment._duplicate_to(new_fragment, true)
    else:
        new_fragment = new_from_string(fragment.serialized_data, fragment.source_description)
    return new_fragment

func load_editor_selection(as_cut: bool, from_editor: CHANE_AssetNodeEditor = null) -> bool:
    if from_editor:
        gd_nodes_are_for_editor = from_editor
    var selected_ges: Array[GraphElement] = gd_nodes_are_for_editor.get_selected_ges()
    return load_graph_elements(selected_ges, gd_nodes_are_for_editor.focused_graph, as_cut)
    
func load_graph_elements(graph_elements: Array[GraphElement], from_graph: CHANE_AssetNodeGraphEdit, as_cut: bool) -> bool:
    if not gd_nodes_are_for_editor:
        push_error("No editor context while loading graph elements into fragment")
        return false
    if has_node_tree() or serialized_data:
        push_error("Fragment alerady has data, create a new fragment to load nodes from editor")
        return false
    var editor: = gd_nodes_are_for_editor

    if graph_elements.size() == 0:
        push_warning("No provided elements to load into new fragment from editor")
        return false

    is_cut_fragment = as_cut
    
    var included_asset_nodes: = editor.get_included_asset_nodes_for_ges(graph_elements)
    context_data["hanging_connections"] = editor.get_hanging_an_connections_for_ges(graph_elements, from_graph)

    gd_node_tree = FragmentRoot.new()
    if as_cut:
        gd_node_tree.take_asset_nodes_from_editor(editor, included_asset_nodes)
        editor.remove_graph_elements_from_graphs(graph_elements)
        add_gd_nodes_to_fragment_root(graph_elements)
    else:
        gd_node_tree.get_duplicate_an_set_from_editor(editor, included_asset_nodes)
        create_new_graph_nodes_in_fragment_root()
        var duplicate_groups: = editor.get_duplicate_group_set(Util.engine_class_filtered(graph_elements, "GraphFrame"))
        add_gd_nodes_to_fragment_root(duplicate_groups)
    
    set_from_graph_pos(gd_node_tree.recenter_graph_elements())
    
    return true

func set_from_graph_pos(from_graph_pos: Vector2) -> void:
    context_data["from_graph_pos"] = JSON.from_native(from_graph_pos)

func get_from_graph_pos() -> Vector2:
    if not has_node_tree():
        push_error("No node tree to get from graph pos from")
        return Vector2.ZERO

    if not context_data.has("from_graph_pos"):
        return Vector2.ZERO
    return JSON.to_native(context_data["from_graph_pos"])

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

## Gets a new set of GraphElement Nodes attached to a FragmentRoot which contains a new set of HyAssetNodes
## Unless this is a fragment created as a Cut, or to hold deleted nodes for undoing later, the returned Asset Nodes will always have a new set of Node IDs
## Note: The fragment owns the reference to the Godot Nodes and will free them when it's gone, so we only ever return duplicated instances for use elsewhere
func get_gd_nodes_copy(for_editor: CHANE_AssetNodeEditor = null) -> FragmentRoot:
    if not gd_nodes_are_for_editor:
        gd_nodes_are_for_editor = for_editor
    if not gd_nodes_are_for_editor:
        push_error("No editor context to get fragment nodes")
        return null

    if not has_node_tree():
        if not _make_nodes(gd_nodes_are_for_editor):
            return null
    
    return gd_node_tree.get_duplicate(not is_cut_fragment)

func get_consistent_named_gd_nodes(prefix: String, number_starts_at: int) -> FragmentRoot:
    var new_copy: = get_gd_nodes_copy()
    var all_ges: = new_copy.get_all_graph_elements()
    for i in all_ges.size():
        all_ges[i].name = "%s--%d" % [prefix, number_starts_at + i]
    return new_copy

func get_num_gd_nodes() -> int:
    if not gd_nodes_are_for_editor:
        push_error("No editor context to get number of GD nodes from")
        return 0
    if not has_node_tree():
        if not _make_nodes(gd_nodes_are_for_editor):
            return 0
    return gd_node_tree.num_graph_elements()


func disown_nodes() -> void:
    gd_nodes_are_for_editor = null
    gd_node_tree = null

func discard_nodes() -> void:
    gd_nodes_are_for_editor = null
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
    const MetadataKeys: = CHANE_HyAssetNodeSerializer.MetadataKeys
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
    var editor_metadata: = data.get("inlcuded_metadata", {}).get(MetadataKeys.NodeEditorMetadata, {}) as Dictionary
    var graph_result: = serializer.deserialize_fragment_as_full_graph(data.get("asset_node_data", []), editor_metadata)
    if not graph_result.success:
        return false

    var all_groups_data: Array = data.get(MetadataKeys.NodeEditorMetadata, {}).get(MetadataKeys.Groups, [])
    var new_groups: Array[GraphFrame] = serializer.deserialize_groups(all_groups_data, editor.get_new_group_name)
    
    gd_node_tree = FragmentRoot.new()
    gd_node_tree.asset_nodes_from_graph_parse_result(graph_result)
    
    create_new_graph_nodes_in_fragment_root()
    add_gd_nodes_to_fragment_root(new_groups)

    return true
    
func create_new_graph_nodes_in_fragment_root() -> Array[GraphElement]:
    var added_graph_elements: Array[GraphElement] = []

    var an_roots: Array[HyAssetNode] = gd_node_tree.get_an_tree_roots()
    #var all_connections: Array[Dictionary] = []
    
    var editor: = gd_nodes_are_for_editor

    for tree_root in an_roots:
        var tree_new: = editor.new_graph_nodes_for_tree(tree_root, Vector2.ZERO, gd_node_tree.asset_node_aux_data)

        var unique_graph_elements: Array[GraphElement] = []
        for ge in tree_new.values():
            if not unique_graph_elements.has(ge):
                unique_graph_elements.append(ge)
        added_graph_elements.append_array(unique_graph_elements)
    
    add_gd_nodes_to_fragment_root(added_graph_elements)
        
    return added_graph_elements

func add_gd_nodes_to_fragment_root(graph_elements: Array) -> void:
    assert(has_node_tree(), "Fragment root is required to add GD nodes to")
    
    for ge in graph_elements:
        if not ge is GraphElement:
            continue
        gd_node_tree.add_child(ge, true)

func check_compatible_workspace(workspace_id: String) -> bool:
    return gd_nodes_are_for_editor.is_workspace_id_compatible(workspace_id)

func _duplicate_to(other: Fragment, reroll_ids: bool) -> void:
    other.source_description = source_description
    other.gd_node_tree = gd_node_tree.get_duplicate(reroll_ids)
    other.create_new_graph_nodes_in_fragment_root()
    var duplicated_groups: = gd_nodes_are_for_editor.get_duplicate_group_set(Util.engine_class_filtered(gd_node_tree.get_all_graph_elements(), "GraphFrame"))
    other.add_gd_nodes_to_fragment_root(duplicated_groups)
    other.context_data = context_data.duplicate(true)

# When a fragment is freed, free the Godot Nodes as well (which are not ref-counted) if there are any
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if gd_node_tree:
            gd_node_tree.queue_free()
            gd_node_tree = null