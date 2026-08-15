#+private
package json

Frame_Kind :: enum {
	Object,
	Array,
}

Frame_State :: enum {
	Expect_Key_Or_End,
	Expect_Colon,
	Expect_Value_Or_End,
	Expect_Comma_Or_End,
}

Frame :: struct {
	kind:  Frame_Kind,
	state: Frame_State,
}

Parser :: struct {
	tokeniser: Tokeniser,
	stack:     [dynamic]Frame,
}

parser_init :: proc(parser: ^Parser, file_path: string) -> bool {
	return tokeniser_init(&parser.tokeniser, file_path) == nil
}

parser_destroy :: proc(parser: ^Parser) {
	tokeniser_destroy(&parser.tokeniser)
	delete(parser.stack)
}

parser_parse :: proc(parser: ^Parser) {
}
