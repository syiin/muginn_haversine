#+private
package json

import "core:os"

TOKENISER_BUFFER_SIZE :: 1024 * 1024

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
	file_path:           string,
	file:                ^os.File,
	buffer:              [TOKENISER_BUFFER_SIZE]byte,
	buffer_cursor:       int,
	buffer_length:       int,
	offset:              int,
	token_buffer:        [dynamic]byte,
	reached_end_of_file: bool,
}

tokeniser_init :: proc(tokeniser: ^Tokeniser, file_path: string) -> Error {
	file, open_error := os.open(file_path)
	if open_error != nil {
		return Error{kind = .Open_File}
	}

	tokeniser^ = Tokeniser {
		file_path = file_path,
		file = file,
	}
	read_error := tokeniser_refill(tokeniser)
	if read_error != nil {
		os.close(file)
		tokeniser.file = nil
		return Error{kind = .Read_File, offset = tokeniser.offset}
	}
	return {}
}

tokeniser_destroy :: proc(tokeniser: ^Tokeniser) {
	os.close(tokeniser.file)
	delete(tokeniser.token_buffer)
}

@(require_results)
tokeniser_next :: proc(tokeniser: ^Tokeniser) -> Token {
	if tokeniser_skip_whitespace(tokeniser) != nil {
		return Token {
			kind = .Invalid,
			offset = tokeniser.offset,
			error_kind = .Read_File,
		}
	}

	character, available, read_error := tokeniser_peek(tokeniser)
	if read_error != nil {
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

tokeniser_skip_whitespace :: proc(tokeniser: ^Tokeniser) -> os.Error {
	for {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != nil || !available {
			return read_error
		}

		switch character {
		case ' ', '\t', '\n', '\r':
			tokeniser_advance(tokeniser)
		case:
			return nil
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
		if read_error != nil {
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
		if read_error != nil {
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
		if read_error != nil {
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
		if read_error != nil {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if available && '0' <= character && character <= '9' {
			append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
			return tokeniser_number_token(tokeniser, token_offset, .Unexpected_Token)
		}
	} else if tokeniser_consume_digits(tokeniser) != nil {
		return tokeniser_number_token(tokeniser, token_offset, .Read_File)
	}

	character, available, read_error := tokeniser_peek(tokeniser)
	if read_error != nil {
		return tokeniser_number_token(tokeniser, token_offset, .Read_File)
	}
	// Handle fractional digits.
	if available && character == '.' {
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))

		character, available, read_error = tokeniser_peek(tokeniser)
		if read_error != nil {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if !available || character < '0' || character > '9' {
			return tokeniser_number_token(
				tokeniser,
				token_offset,
				.Unexpected_EOF if !available else .Unexpected_Token,
			)
		}
		if tokeniser_consume_digits(tokeniser) != nil {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
	}

	character, available, read_error = tokeniser_peek(tokeniser)
	if read_error != nil {
		return tokeniser_number_token(tokeniser, token_offset, .Read_File)
	}
	// Handle exponentials.
	if available && (character == 'e' || character == 'E') {
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))

		character, available, read_error = tokeniser_peek(tokeniser)
		if read_error != nil {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
		if !available {
			return tokeniser_number_token(tokeniser, token_offset, .Unexpected_EOF)
		}
		// Handle an optional exponent sign.
		if character == '+' || character == '-' {
			append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
			character, available, read_error = tokeniser_peek(tokeniser)
			if read_error != nil {
				return tokeniser_number_token(tokeniser, token_offset, .Read_File)
			}
			if !available {
				return tokeniser_number_token(tokeniser, token_offset, .Unexpected_EOF)
			}
		}
		if character < '0' || character > '9' {
			return tokeniser_number_token(tokeniser, token_offset, .Unexpected_Token)
		}
		if tokeniser_consume_digits(tokeniser) != nil {
			return tokeniser_number_token(tokeniser, token_offset, .Read_File)
		}
	}

	return tokeniser_number_token(tokeniser, token_offset, .None)
}

tokeniser_consume_digits :: proc(tokeniser: ^Tokeniser) -> os.Error {
	for {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != nil || !available || character < '0' || character > '9' {
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
	read_error: os.Error,
) {
	if tokeniser.buffer_cursor == tokeniser.buffer_length {
		if tokeniser.reached_end_of_file {
			return 0, false, nil
		}
		read_error = tokeniser_refill(tokeniser)
		if read_error != nil || tokeniser.buffer_length == 0 {
			return 0, false, read_error
		}
	}
	return tokeniser.buffer[tokeniser.buffer_cursor], true, nil
}

tokeniser_advance :: proc(tokeniser: ^Tokeniser) -> byte {
	character := tokeniser.buffer[tokeniser.buffer_cursor]
	tokeniser.buffer_cursor += 1
	tokeniser.offset += 1
	return character
}

tokeniser_refill :: proc(tokeniser: ^Tokeniser) -> os.Error {
	bytes_read, read_error := os.read(tokeniser.file, tokeniser.buffer[:])
	tokeniser.buffer_cursor = 0
	tokeniser.buffer_length = bytes_read

	if read_error == .EOF {
		tokeniser.reached_end_of_file = true
		return nil
	}
	return read_error
}
