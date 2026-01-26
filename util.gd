extends Node

func unique_id_string() -> String:
    return "%s-%s-%s-%s-%s" % [random_str(8), random_str(4), random_str(4), random_str(4), random_str(12)]

func random_str(length: int) -> String:
    var the_str: = ""
    while length > 4:
        length -= 4
        the_str += "%04x" % (randi() & 0xFFFF)
    the_str += ("%04x" % (randi() & 0xFFFF)).substr(0, length)
    return the_str
    
