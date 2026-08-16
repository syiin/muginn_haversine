package json

Null   :: distinct rawptr
Number :: f64
String :: string
Array  :: distinct [dynamic]Value
Object :: distinct map[string]Value

Value :: union {
	Null,
	Number,
	bool,
	String,
	Array,
	Object,
}

Error_Kind :: enum {
	None,
	Open_File,
	Read_File,
	Unexpected_Token,
	Unexpected_EOF,
	Trailing_Data,
}

Error :: struct {
	kind:   Error_Kind,
	offset: int,
}

@(require_results)
parse :: proc(file_path: string) -> (value: Value, err: Error) {
	parser: Parser
	err = parser_init(&parser, file_path)
	if err.kind != .None {
		return
	}
	defer parser_destroy(&parser)

	err = parser_parse(&parser)
	if err.kind != .None {
		return
	}

	value = parser.result
	parser.has_result = false
	return
}

destroy :: proc(value: Value) {
	parser_destroy_value(value)
}
