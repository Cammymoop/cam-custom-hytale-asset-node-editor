extends Node
class_name ExpressionHelper

static func is_valid_expression(expression_text: String) -> bool:
    var parsed_expression: = Expression.new()
    var error: = parsed_expression.parse(expression_text, [])

    if error != OK:
        var error_text: = "Potential expression '%s' is not a valid expression: %s" % [expression_text, parsed_expression.get_error_text()]
        push_warning(error_text)
        print_debug(error_text)
        return false
    
    return true

static func get_expression_numerical_value(expression_text: String) -> Array:
    var parsed_expression: = Expression.new()
    var error: = parsed_expression.parse(expression_text, [])
    if error != OK:
        var error_text: = "Expression '%s' is not a valid expression: %s" % [expression_text, parsed_expression.get_error_text()]
        push_error(error_text)
        print_debug(error_text)
        return [false, 0.0]
    
    var result: Variant = parsed_expression.execute()
    if parsed_expression.has_execute_failed():
        var error_text: = "Expression '%s' failed to execute: %s" % [expression_text, parsed_expression.get_error_text()]
        push_error(error_text)
        print_debug(error_text)
        return [false, 0.0]
    
    var type_error_text: = ""
    if typeof(result) == TYPE_BOOL:
        return [true, 1.0 if result else 0.0]
    elif typeof(result) in [TYPE_FLOAT, TYPE_INT]:
        return [true, float(result)]
    elif typeof(result) == TYPE_STRING and result.is_valid_float():
        if result.is_valid_float():
            return [true, float(result)]
        else:
            type_error_text = "Numeric Expression '%s' returned a non-numeric string: \"%s\"" % [expression_text, result]
    else:
        type_error_text = "Numeric Expression '%s' returned a non-numeric value of type %s :: ( %s )" % [expression_text, type_string(typeof(result)), result]
    
    if type_error_text:
        push_warning(type_error_text)
        print_debug(type_error_text)
    return [false, 0.0]
