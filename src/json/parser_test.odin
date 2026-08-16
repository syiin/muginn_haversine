package json

import "core:testing"

@(test)
parser_stack_top_empty_test :: proc(t: ^testing.T) {
	parser: Parser
	testing.expect_value(t, parser_stack_top(&parser), nil)
}

@(test)
parser_pushes_object_frame_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("{")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 1)
	switch frame in parser.stack[0] {
	case Object_Frame:
		testing.expect_value(t, frame.state, Object_State.Expect_First_Key_Or_End)
		testing.expect_value(t, len(frame.values), 0)
	case Array_Frame:
		testing.expect(t, false, "Expected an object frame")
	}
}

@(test)
parser_pushes_array_frame_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("[")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 1)
	switch frame in parser.stack[0] {
	case Array_Frame:
		testing.expect_value(t, frame.state, Array_State.Expect_First_Value_Or_End)
		testing.expect_value(t, len(frame.values), 0)
	case Object_Frame:
		testing.expect(t, false, "Expected an array frame")
	}
}

@(test)
parser_populates_object_key_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("{\"name\"")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 1)
	switch frame in parser.stack[0] {
	case Object_Frame:
		testing.expect_value(t, frame.pending_key, "name")
		testing.expect_value(t, frame.state, Object_State.Expect_Colon)
	case Array_Frame:
		testing.expect(t, false, "Expected an object frame")
	}
}

@(test)
parser_handles_object_colon_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("{\"name\":")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 1)
	switch frame in parser.stack[0] {
	case Object_Frame:
		testing.expect_value(t, frame.pending_key, "name")
		testing.expect_value(t, frame.state, Object_State.Expect_Value)
	case Array_Frame:
		testing.expect(t, false, "Expected an object frame")
	}
}

@(test)
parser_handles_object_comma_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("{\"child\":{},")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 1)
	switch frame in parser.stack[0] {
	case Object_Frame:
		testing.expect_value(t, frame.state, Object_State.Expect_Key)
		testing.expect_value(t, len(frame.values), 1)
	case Array_Frame:
		testing.expect(t, false, "Expected an object frame")
	}
}

@(test)
parser_handles_array_comma_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("[[],")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 1)
	switch frame in parser.stack[0] {
	case Array_Frame:
		testing.expect_value(t, frame.state, Array_State.Expect_Value)
		testing.expect_value(t, len(frame.values), 1)
	case Object_Frame:
		testing.expect(t, false, "Expected an array frame")
	}
}

@(test)
parser_completes_scalar_array_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("[\"hello\",-12.5,true,false,null]")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect(t, parser.has_result)
	value, is_array := parser.result.(Array)
	testing.expect(t, is_array, "Expected an array result")
	if !is_array {
		return
	}
	testing.expect_value(t, len(value), 5)

	string_value, is_string := value[0].(String)
	testing.expect(t, is_string, "Expected a string value")
	testing.expect_value(t, string_value, String("hello"))
	number_value, is_number := value[1].(Number)
	testing.expect(t, is_number, "Expected a number value")
	testing.expect_value(t, number_value, Number(-12.5))
	true_value, is_bool := value[2].(bool)
	testing.expect(t, is_bool, "Expected a boolean value")
	testing.expect_value(t, true_value, true)
	false_value, is_false_bool := value[3].(bool)
	testing.expect(t, is_false_bool, "Expected a boolean value")
	testing.expect_value(t, false_value, false)
	_, is_null := value[4].(Null)
	testing.expect(t, is_null, "Expected a null value")
}

@(test)
parser_completes_string_object_value_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("{\"name\":\"muginn\"}")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect(t, parser.has_result)
	object, is_object := parser.result.(Object)
	testing.expect(t, is_object, "Expected an object result")
	if !is_object {
		return
	}
	value, found := object["name"]
	testing.expect(t, found, "Expected the name key")
	string_value, is_string := value.(String)
	testing.expect(t, is_string, "Expected a string value")
	testing.expect_value(t, string_value, String("muginn"))
}

@(test)
parser_completes_scalar_root_test :: proc(t: ^testing.T) {
	inputs := []string {"\"hello\"", "-12.5", "true", "false", "null"}
	for input in inputs {
		parser: Parser
		parser.tokeniser = test_tokeniser(input)

		parser_parse(&parser)

		testing.expect_value(t, len(parser.stack), 0)
		testing.expect(t, parser.has_result)
		parser_destroy(&parser)
	}
}

@(test)
parser_completes_empty_object_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("{}")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 0)
	testing.expect(t, parser.has_result)
	is_object := false
	#partial switch value in parser.result {
	case Object:
		is_object = true
		testing.expect_value(t, len(value), 0)
	}
	testing.expect(t, is_object, "Expected an object result")
}

@(test)
parser_completes_empty_array_test :: proc(t: ^testing.T) {
	parser: Parser
	parser.tokeniser = test_tokeniser("[]")
	defer parser_destroy(&parser)

	parser_parse(&parser)

	testing.expect_value(t, len(parser.stack), 0)
	testing.expect(t, parser.has_result)
	is_array := false
	#partial switch value in parser.result {
	case Array:
		is_array = true
		testing.expect_value(t, len(value), 0)
	}
	testing.expect(t, is_array, "Expected an array result")
}
