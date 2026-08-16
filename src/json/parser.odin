#+private
package json

import "core:strings"
import "core:strconv"

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
	has_result: bool,
}

parser_init :: proc(parser: ^Parser, file_path: string) -> Error {
	return tokeniser_init(&parser.tokeniser, file_path)
}

parser_destroy :: proc(parser: ^Parser) {
	tokeniser_destroy(&parser.tokeniser)
	for frame in parser.stack {
		switch value in frame {
		case Array_Frame:
			parser_destroy_value(Value(value.values))
		case Object_Frame:
			parser_destroy_value(Value(value.values))
			if value.pending_key != "" {
				delete(value.pending_key)
			}
		}
	}
	delete(parser.stack)
	if parser.has_result {
		parser_destroy_value(parser.result)
	}
}

parser_parse :: proc(parser: ^Parser) -> Error {
	for {
		token := tokeniser_next(&parser.tokeniser)
		if parser.has_result && len(parser.stack) == 0 && token.kind != .EOF {
			return Error{kind = .Trailing_Data, offset = token.offset}
		}

		#partial switch token.kind {
		case .EOF:
			if !parser.has_result || len(parser.stack) != 0 {
				return Error{kind = .Unexpected_EOF, offset = token.offset}
			}
			return {}
		case .Invalid:
			kind := token.error_kind
			if kind == .None {
				kind = .Unexpected_Token
			}
			return Error{kind = kind, offset = token.offset}
		case .Left_Brace:
			frame := Object_Frame {
				state = .Expect_First_Key_Or_End,
				values = make(Object),
			}
			append(&parser.stack, Frame(frame))
		case .Left_Bracket:
			frame := Array_Frame {
				state = .Expect_First_Value_Or_End,
				values = make(Array),
			}
			append(&parser.stack, Frame(frame))
		case .Right_Brace:
			if !parser_handle_right_brace(parser) {
				return Error{kind = .Unexpected_Token, offset = token.offset}
			}
		case .Right_Bracket:
			if !parser_handle_right_bracket(parser) {
				return Error{kind = .Unexpected_Token, offset = token.offset}
			}
		case .Colon:
			if !parser_handle_colon(parser_stack_top(parser)) {
				return Error{kind = .Unexpected_Token, offset = token.offset}
			}
		case .Comma:
			if !parser_handle_comma(parser_stack_top(parser)) {
				return Error{kind = .Unexpected_Token, offset = token.offset}
			}
		case .String:
			if !parser_handle_string(parser, token) {
				return Error{kind = .Unexpected_Token, offset = token.offset}
			}
		case .Number, .True, .False, .Null:
			if !parser_handle_scalar(parser, token) {
				return Error{kind = .Unexpected_Token, offset = token.offset}
			}
		}
	}
}

parser_stack_top :: proc(parser: ^Parser) -> ^Frame {
	if len(parser.stack) == 0 {
		return nil
	}
	return &parser.stack[len(parser.stack)-1]
}

parser_handle_colon :: proc(frame: ^Frame) -> bool {
	if frame == nil {
		return false
	}
	switch &value in frame^ {
	case Object_Frame:
		if value.state != .Expect_Colon {
			return false
		}
		value.state = .Expect_Value
	case Array_Frame:
		return false
	}
	return true
}

parser_handle_comma :: proc(frame: ^Frame) -> bool {
	if frame == nil {
		return false
	}
	switch &value in frame^ {
	case Object_Frame:
		if value.state != .Expect_Comma_Or_End {
			return false
		}
		value.state = .Expect_Key
	case Array_Frame:
		if value.state != .Expect_Comma_Or_End {
			return false
		}
		value.state = .Expect_Value
	}
	return true
}

parser_handle_string :: proc(parser: ^Parser, token: Token) -> bool {
	top := parser_stack_top(parser)
	if top != nil {
		switch &frame in top^ {
		case Object_Frame:
			if frame.state == .Expect_First_Key_Or_End || frame.state == .Expect_Key {
				key, clone_error := strings.clone(token.lexeme[1:len(token.lexeme)-1])
				if clone_error != nil {
					return false
				}
				frame.pending_key = key
				frame.state = .Expect_Colon
				return true
			}
		case Array_Frame:
		}
	}

	string_value, clone_error := strings.clone(token.lexeme[1:len(token.lexeme)-1])
	if clone_error != nil {
		return false
	}
	value := Value(String(string_value))
	if !parser_attach_value(parser, value) {
		parser_destroy_value(value)
		return false
	}
	return true
}

parser_handle_scalar :: proc(parser: ^Parser, token: Token) -> bool {
	#partial switch token.kind {
	case .Number:
		value, ok := strconv.parse_f64(token.lexeme)
		if !ok {
			return false
		}
		return parser_attach_value(parser, Value(Number(value)))
	case .True:
		return parser_attach_value(parser, Value(true))
	case .False:
		return parser_attach_value(parser, Value(false))
	case .Null:
		return parser_attach_value(parser, Value(Null(nil)))
	case:
		return false
	}
}

parser_handle_right_brace :: proc(parser: ^Parser) -> bool {
	top := parser_stack_top(parser)
	if top == nil {
		return false
	}

	switch frame in top^ {
	case Object_Frame:
		if frame.state != .Expect_First_Key_Or_End && frame.state != .Expect_Comma_Or_End {
			return false
		}
	case Array_Frame:
		return false
	}

	completed := pop(&parser.stack)
	switch frame in completed {
	case Object_Frame:
		value := Value(frame.values)
		if !parser_attach_value(parser, value) {
			parser_destroy_value(value)
			return false
		}
	case Array_Frame:
		return false
	}
	return true
}

parser_handle_right_bracket :: proc(parser: ^Parser) -> bool {
	top := parser_stack_top(parser)
	if top == nil {
		return false
	}

	switch frame in top^ {
	case Array_Frame:
		if frame.state != .Expect_First_Value_Or_End && frame.state != .Expect_Comma_Or_End {
			return false
		}
	case Object_Frame:
		return false
	}

	completed := pop(&parser.stack)
	switch frame in completed {
	case Array_Frame:
		value := Value(frame.values)
		if !parser_attach_value(parser, value) {
			parser_destroy_value(value)
			return false
		}
	case Object_Frame:
		return false
	}
	return true
}

parser_attach_value :: proc(parser: ^Parser, value: Value) -> bool {
	top := parser_stack_top(parser)
	if top == nil {
		if parser.has_result {
			return false
		}
		parser.result = value
		parser.has_result = true
		return true
	}

	switch &frame in top^ {
	case Object_Frame:
		if frame.state != .Expect_Value {
			return false
		}
		frame.values[frame.pending_key] = value
		frame.pending_key = ""
		frame.state = .Expect_Comma_Or_End
	case Array_Frame:
		if frame.state != .Expect_First_Value_Or_End && frame.state != .Expect_Value {
			return false
		}
		append(&frame.values, value)
		frame.state = .Expect_Comma_Or_End
	}
	return true
}

parser_destroy_value :: proc(value: Value) {
	#partial switch item in value {
	case String:
		delete(item)
	case Array:
		for child in item {
			parser_destroy_value(child)
		}
		delete(item)
	case Object:
		for key, child in item {
			delete(key)
			parser_destroy_value(child)
		}
		delete(item)
	}
}
