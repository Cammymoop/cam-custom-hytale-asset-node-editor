extends Node

func unique_id_string() -> String:
    return "%s-%s-%s-%s-%s" % [random_str(8), random_str(4), random_str(4), random_str(4), random_str(12)]

func rect2_clamp_point(rect: Rect2, point: Vector2) -> Vector2:
    return point.max(rect.position).min(rect.end)

func rect2_clamp_rect2_pos(limit_rect: Rect2, rect: Rect2) -> Vector2:
    if rect.size.x > limit_rect.size.x and rect.size.y > limit_rect.size.y:
        return limit_rect.position

    var clamp_start_pos: = rect2_clamp_point(limit_rect, rect.position)
    var final_clamped: = rect2_clamp_point(limit_rect, rect.end) - rect.size
    if rect.size.x > limit_rect.size.x or rect.position.x < limit_rect.position.x:
        final_clamped.x = clamp_start_pos.x
    if rect.size.y > limit_rect.size.y or rect.position.y < limit_rect.position.y:
        final_clamped.y = clamp_start_pos.y
    
    return final_clamped

func get_plain_version() -> String:
    return "v%s" % ProjectSettings.get_setting("application/config/version")

func get_version_number_string() -> String:
    var prerelease_string: = " Alpha"
    if OS.has_feature("debug"):
        prerelease_string = " Alpha (Debug)"
    return get_plain_version() + prerelease_string

func random_str(length: int) -> String:
    var the_str: = ""
    while length > 4:
        length -= 4
        the_str += "%04x" % (randi() & 0xFFFF)
    the_str += ("%04x" % (randi() & 0xFFFF)).substr(0, length)
    return the_str

func average_graph_element_pos_offset(ges: Array[GraphElement]) -> Vector2:
    var offsets: Array[Vector2] = []
    for ge in ges:
        offsets.append(ge.position_offset)
    return average_vector2(offsets)
    
func average_vector2(vectors: Array[Vector2]) -> Vector2:
    if vectors.size() == 0:
        return Vector2.ZERO
    if vectors.size() <= 8:
        return _average_vector2_small(vectors)
    
    var pivot_idx: int = floori(vectors.size() / 2.0)
    var left_avg: Vector2 = average_vector2(vectors.slice(0, pivot_idx))
    var right_avg: Vector2 = average_vector2(vectors.slice(pivot_idx, vectors.size()))
    return (left_avg + right_avg) / 2.0

func _average_vector2_small(vectors: Array[Vector2]) -> Vector2:
    var total: Vector2 = Vector2.ZERO
    for vector in vectors:
        total += vector
    return total / vectors.size()

func get_popup_window_pos(mouse_pos: Vector2i) -> Vector2i:
    var window: = get_window()
    if not window.gui_embed_subwindows:
        return mouse_pos + window.position
    return mouse_pos

func clamp_popup_pos_inside_window(popup_pos: Vector2i, popup_size: Vector2, parent_window: Window) -> Vector2i:
    if not parent_window.gui_embed_subwindows:
        var window_in_screen_rect: = parent_window.get_visible_rect()
        window_in_screen_rect.position = Vector2(parent_window.position)
        return Vector2i(rect2_clamp_rect2_pos(window_in_screen_rect, Rect2(popup_pos, popup_size)))
    
    var global_pos_rect: = Rect2(Vector2.ZERO, parent_window.size)
    return Vector2i(rect2_clamp_rect2_pos(global_pos_rect, Rect2(popup_pos, popup_size)))

func is_ctrl_cmd_pressed() -> bool:
    var ctrl_keycode: = KEY_CTRL
    if OS.has_feature("macos"):
        ctrl_keycode = KEY_META
    return Input.is_key_pressed(ctrl_keycode)

func is_shift_pressed() -> bool:
    return Input.is_key_pressed(KEY_SHIFT)

func get_icon_for_color(icon_color: Color) -> Texture2D:
    var icon_size: = ANESettings.MENU_ICON_SIZE
    var img: = Image.create(icon_size, icon_size, false, Image.FORMAT_RGB8)
    img.fill(icon_color)
    return ImageTexture.create_from_image(img)

func out_connections(conn_infos: Array[Dictionary], graph_node_name: String, only_at_port: int = -1) -> Array[Dictionary]:
    var out_conn_infos: Array[Dictionary] = []
    for conn_info in conn_infos:
        if conn_info.get("to_node", "") == graph_node_name:
            if only_at_port == -1 or conn_info.get("to_port", -1) == only_at_port:
                out_conn_infos.append(conn_info)
    return out_conn_infos

func in_connections(conn_infos: Array[Dictionary], graph_node_name: String, only_at_port: int = -1) -> Array[Dictionary]:
    var in_conn_infos: Array[Dictionary] = []
    for conn_info in conn_infos:
        if conn_info.get("from_node", "") == graph_node_name:
            if only_at_port == -1 or conn_info.get("from_port", -1) == only_at_port:
                in_conn_infos.append(conn_info)
    return in_conn_infos

func str_empty_or_match(str_a: String, str_b: String) -> bool:
    return str_a == "" or str_b == "" or str_a == str_b