#+private
package json

TOKENISER_BUFFER_SIZE :: 64 * 1024

Token_Kind :: enum {
	Invalid,
	EOF,
	Left_Brace,
	Right_Brace,
	Left_Bracket,
	Right_Bracket,
	Colon,
	Comma,
	String,
	Number,
	True,
	False,
	Null,
}

Token :: struct {
	kind:       Token_Kind,
	lexeme:     string,
	offset:     int,
	error_kind: Error_Kind,
}

Tokeniser :: struct {
	input:         File_Input,
	scratch:       [TOKENISER_BUFFER_SIZE]byte,
	window:        []byte,
	window_cursor: int,
	offset:        int,
	token_buffer:  [dynamic]byte,
	end_of_file:   bool,
}

tokeniser_init :: proc(tokeniser: ^Tokeniser, file_path: string) -> Error {
	input, error_kind := file_input_open(file_path)
	if error_kind != .None {
		return Error{kind = error_kind}
	}
	return tokeniser_init_from_file_input(tokeniser, input)
}

tokeniser_init_from_file_input :: proc(tokeniser: ^Tokeniser, input: File_Input) -> Error {
	tokeniser^ = Tokeniser{input = input}
	error_kind := tokeniser_refill(tokeniser)
	if error_kind != .None {
		file_input_destroy(&tokeniser.input)
		return Error{kind = error_kind, offset = tokeniser.offset}
	}
	return {}
}

tokeniser_destroy :: proc(tokeniser: ^Tokeniser) {
	file_input_destroy(&tokeniser.input)
	delete(tokeniser.token_buffer)
}

@(require_results)
tokeniser_next :: proc(tokeniser: ^Tokeniser) -> Token {
	if tokeniser_skip_whitespace(tokeniser) != .None {
		return Token {
			kind = .Invalid,
			offset = tokeniser.offset,
			error_kind = .Read_File,
		}
	}

	character, available, read_error := tokeniser_peek(tokeniser)
	if read_error != .None {
		return Token {
			kind = .Invalid,
			offset = tokeniser.offset,
			error_kind = .Read_File,
		}
	}
	if !available {
		return Token{kind = .EOF, offset = tokeniser.offset}
	}

	token_offset := tokeniser.offset
	tokeniser_advance(tokeniser)

	switch character {
	case '{':
		return Token{kind = .Left_Brace, lexeme = "{", offset = token_offset}
	case '}':
		return Token{kind = .Right_Brace, lexeme = "}", offset = token_offset}
	case '[':
		return Token{kind = .Left_Bracket, lexeme = "[", offset = token_offset}
	case ']':
		return Token{kind = .Right_Bracket, lexeme = "]", offset = token_offset}
	case ':':
		return Token{kind = .Colon, lexeme = ":", offset = token_offset}
	case ',':
		return Token{kind = .Comma, lexeme = ",", offset = token_offset}
	case '"':
		return tokeniser_scan_string(tokeniser, token_offset)
	case 't':
		return tokeniser_scan_literal(tokeniser, token_offset, "true", .True)
	case 'f':
		return tokeniser_scan_literal(tokeniser, token_offset, "false", .False)
	case 'n':
		return tokeniser_scan_literal(tokeniser, token_offset, "null", .Null)
	case '-', '0'..='9':
		return tokeniser_scan_number(tokeniser, token_offset, character)
	case:
		return Token {
			kind = .Invalid,
			offset = token_offset,
			error_kind = .Unexpected_Token,
		}
	}
}

tokeniser_skip_whitespace :: proc(tokeniser: ^Tokeniser) -> Error_Kind {
	for {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != .None || !available {
			return read_error
		}

		switch character {
		case ' ', '\t', '\n', '\r':
			tokeniser_advance(tokeniser)
		case:
			return .None
		}
	}
}

tokeniser_scan_literal :: proc(
	tokeniser: ^Tokeniser,
	token_offset: int,
	expected: string,
	kind: Token_Kind,
) -> Token {
	clear(&tokeniser.token_buffer)
	append(&tokeniser.token_buffer, expected[0])

	for index in 1 ..< len(expected) {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != .None {
			return Token {
				kind = .Invalid,
				lexeme = string(tokeniser.token_buffer[:]),
				offset = token_offset,
				error_kind = .Read_File,
			}
		}
		if !available || character != expected[index] {
			return Token {
				kind = .Invalid,
				lexeme = string(tokeniser.token_buffer[:]),
				offset = token_offset,
				error_kind = .Unexpected_EOF if !available else .Unexpected_Token,
			}
		}
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
	}

	return Token {
		kind = kind,
		lexeme = string(tokeniser.token_buffer[:]),
		offset = token_offset,
	}
}

tokeniser_scan_string :: proc(tokeniser: ^Tokeniser, token_offset: int) -> Token {
	clear(&tokeniser.token_buffer)
	append(&tokeniser.token_buffer, byte('"'))

	kind := Token_Kind.Invalid
	error_kind := Error_Kind.None
	for {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != .None {
			error_kind = .Read_File
			break
		}
		if !available {
			error_kind = .Unexpected_EOF
			break
		}

		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
		if character == '"' {
			kind = .String
			break
		}
		if character == '\\' || character < 0x20 {
			error_kind = .Unexpected_Token
			break
		}
	}

	return Token {
		kind = kind,
		lexeme = string(tokeniser.token_buffer[:]),
		offset = token_offset,
		error_kind = error_kind,
	}
}

tokeniser_scan_number :: proc(
	tokeniser: ^Tokeniser,
	token_offset: int,
	first_character: byte,
) -> Token {
	clear(&tokeniser.token_buffer)
	append(&tokeniser.token_buffer, first_character)

	// Handle negative numbers.
	first_digit := first_character
	if first_character == '-' {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != .None {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if !available || character < '0' || character > '9' {
			return tokeniser_number_token(
				tokeniser,
				token_offset,
				.Unexpected_EOF if !available else .Unexpected_Token,
			)
		}
		first_digit = tokeniser_advance(tokeniser)
		append(&tokeniser.token_buffer, first_digit)
	}

	// Handle integer digits and reject leading zeroes.
	if first_digit == '0' {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != .None {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if available && '0' <= character && character <= '9' {
			append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
			return tokeniser_number_token(tokeniser, token_offset, .Unexpected_Token)
		}
	} else if tokeniser_consume_digits(tokeniser) != .None {
		return tokeniser_number_token(tokeniser, token_offset, .Read_File)
	}

	character, available, read_error := tokeniser_peek(tokeniser)
	if read_error != .None {
		return tokeniser_number_token(tokeniser, token_offset, .Read_File)
	}
	// Handle fractional digits.
	if available && character == '.' {
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))

		character, available, read_error = tokeniser_peek(tokeniser)
		if read_error != .None {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if !available || character < '0' || character > '9' {
			return tokeniser_number_token(
				tokeniser,
				token_offset,
				.Unexpected_EOF if !available else .Unexpected_Token,
			)
		}
		if tokeniser_consume_digits(tokeniser) != .None {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
	}

	character, available, read_error = tokeniser_peek(tokeniser)
	if read_error != .None {
		return tokeniser_number_token(tokeniser, token_offset, .Read_File)
	}
	// Handle exponentials.
	if available && (character == 'e' || character == 'E') {
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))

		character, available, read_error = tokeniser_peek(tokeniser)
		if read_error != .None {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if !available {
			return tokeniser_number_token(tokeniser, token_offset, .Unexpected_EOF)
		}
		// Handle an optional exponent sign.
		if character == '+' || character == '-' {
			append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
			character, available, read_error = tokeniser_peek(tokeniser)
			if read_error != .None {
				return tokeniser_number_token(tokeniser, token_offset, .Read_File)
			}
			if !available {
				return tokeniser_number_token(tokeniser, token_offset, .Unexpected_EOF)
			}
		}
		if character < '0' || character > '9' {
			return tokeniser_number_token(tokeniser, token_offset, .Unexpected_Token)
		}
		if tokeniser_consume_digits(tokeniser) != .None {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
	}

	return tokeniser_number_token(tokeniser, token_offset, .None)
}

tokeniser_consume_digits :: proc(tokeniser: ^Tokeniser) -> Error_Kind {
	for {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != .None || !available || character < '0' || character > '9' {
			return read_error
		}
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
	}
}

tokeniser_number_token :: proc(
	tokeniser: ^Tokeniser,
	token_offset: int,
	error_kind: Error_Kind,
) -> Token {
	return Token {
		kind = .Number if error_kind == .None else .Invalid,
		lexeme = string(tokeniser.token_buffer[:]),
		offset = token_offset,
		error_kind = error_kind,
	}
}

tokeniser_peek :: proc(tokeniser: ^Tokeniser) -> (
	character: byte,
	available: bool,
	read_error: Error_Kind,
) {
	read_error = tokeniser_refill(tokeniser)
	if read_error != .None || tokeniser.window_cursor == len(tokeniser.window) {
		return 0, false, read_error
	}
	return tokeniser.window[tokeniser.window_cursor], true, .None
}

tokeniser_advance :: proc(tokeniser: ^Tokeniser) -> byte {
	character := tokeniser.window[tokeniser.window_cursor]
	tokeniser.window_cursor += 1
	tokeniser.offset += 1
	return character
}

tokeniser_refill :: proc(tokeniser: ^Tokeniser) -> Error_Kind {
	if tokeniser.window_cursor < len(tokeniser.window) || tokeniser.end_of_file {
		return .None
	}

	data, end_of_file, error_kind := read_file(&tokeniser.input, tokeniser.scratch[:])
	if error_kind != .None {
		return error_kind
	}
	if len(data) == 0 && !end_of_file {
		return .Read_File
	}

	tokeniser.window = data
	tokeniser.window_cursor = 0
	tokeniser.end_of_file = end_of_file
	return .None
}
