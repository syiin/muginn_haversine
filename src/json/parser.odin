#+private
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

Array_State :: enum {
	Expect_First_Value_Or_End,
	Expect_Value,
	Expect_Comma_Or_End,
}

Object_State :: enum {
	Expect_First_Key_Or_End,
	Expect_Key,
	Expect_Colon,
	Expect_Value,
	Expect_Comma_Or_End,
}

Array_Frame :: struct {
	state:  Array_State,
	values: Array,
}

Object_Frame :: struct {
	state:       Object_State,
	values:      Object,
	pending_key: string,
}

Frame :: union {
	Array_Frame,
	Object_Frame,
}

Parser :: struct {
	tokeniser: Tokeniser,
	stack:     [dynamic]Frame,
	result:    Value,
}

parser_init :: proc(parser: ^Parser, file_path: string) -> bool {
	return tokeniser_init(&parser.tokeniser, file_path) == nil
}

parser_destroy :: proc(parser: ^Parser) {
	tokeniser_destroy(&parser.tokeniser)
	delete(parser.stack)
}

parser_parse :: proc(parser: ^Parser) {
	for {
		token := tokeniser_next(&parser.tokeniser)
		#partial switch token.kind {
		case .EOF, .Invalid:
			return
		}
		// Token parsing will be implemented separately.
	}
}
