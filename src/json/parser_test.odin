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
