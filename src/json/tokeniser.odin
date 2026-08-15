#+private
package json

import "core:os"

TOKENISER_BUFFER_SIZE :: 4096

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
	kind:   Token_Kind,
	lexeme: string,
	offset: int,
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

tokeniser_init :: proc(tokeniser: ^Tokeniser, file_path: string) -> os.Error {
	file, open_error := os.open(file_path)
	if open_error != nil {
		return open_error
	}

	tokeniser^ = Tokeniser {
		file_path = file_path,
		file = file,
	}
	read_error := tokeniser_refill(tokeniser)
	if read_error != nil {
		os.close(file)
		tokeniser.file = nil
	}
	return read_error
}

tokeniser_destroy :: proc(tokeniser: ^Tokeniser) {
	os.close(tokeniser.file)
	delete(tokeniser.token_buffer)
}

@(require_results)
tokeniser_next :: proc(tokeniser: ^Tokeniser) -> Token {
	character, available, read_error := tokeniser_peek(tokeniser)
	if read_error != nil {
		return Token{kind = .Invalid, offset = tokeniser.offset}
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
	case '-', '0'..='9':
		return tokeniser_scan_number(tokeniser, token_offset, character)
	case:
		return Token{kind = .Invalid, offset = token_offset}
	}
}

tokeniser_scan_string :: proc(tokeniser: ^Tokeniser, token_offset: int) -> Token {
	clear(&tokeniser.token_buffer)
	append(&tokeniser.token_buffer, byte('"'))

	kind := Token_Kind.Invalid
	for {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != nil || !available {
			break
		}

		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
		if character == '"' {
			kind = .String
			break
		}
		if character == '\\' || character < 0x20 {
			break
		}
	}

	return Token {
		kind = kind,
		lexeme = string(tokeniser.token_buffer[:]),
		offset = token_offset,
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
		if read_error != nil || !available || character < '0' || character > '9' {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
		first_digit = tokeniser_advance(tokeniser)
		append(&tokeniser.token_buffer, first_digit)
	}

	// Handle integer digits and reject leading zeroes.
	if first_digit == '0' {
		character, available, read_error := tokeniser_peek(tokeniser)
		if read_error != nil {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
		if available && '0' <= character && character <= '9' {
			append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
	} else if tokeniser_consume_digits(tokeniser) != nil {
		return tokeniser_number_token(tokeniser, token_offset, false)
	}

	character, available, read_error := tokeniser_peek(tokeniser)
	if read_error != nil {
		return tokeniser_number_token(tokeniser, token_offset, false)
	}
	// Handle fractional digits.
	if available && character == '.' {
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))

		character, available, read_error = tokeniser_peek(tokeniser)
		if read_error != nil || !available || character < '0' || character > '9' {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
		if tokeniser_consume_digits(tokeniser) != nil {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
	}

	character, available, read_error = tokeniser_peek(tokeniser)
	if read_error != nil {
		return tokeniser_number_token(tokeniser, token_offset, false)
	}
	// Handle exponentials.
	if available && (character == 'e' || character == 'E') {
		append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))

		character, available, read_error = tokeniser_peek(tokeniser)
		if read_error != nil || !available {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
		// Handle an optional exponent sign.
		if character == '+' || character == '-' {
			append(&tokeniser.token_buffer, tokeniser_advance(tokeniser))
			character, available, read_error = tokeniser_peek(tokeniser)
			if read_error != nil || !available {
				return tokeniser_number_token(tokeniser, token_offset, false)
			}
		}
		if character < '0' || character > '9' {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
		if tokeniser_consume_digits(tokeniser) != nil {
			return tokeniser_number_token(tokeniser, token_offset, false)
		}
	}

	return tokeniser_number_token(tokeniser, token_offset, true)
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
	valid: bool,
) -> Token {
	return Token {
		kind = .Number if valid else .Invalid,
		lexeme = string(tokeniser.token_buffer[:]),
		offset = token_offset,
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
