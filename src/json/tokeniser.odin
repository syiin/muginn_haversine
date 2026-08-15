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
	if tokeniser.buffer_cursor == tokeniser.buffer_length {
		if tokeniser.reached_end_of_file {
			return Token{kind = .EOF, offset = tokeniser.offset}
		}
		if tokeniser_refill(tokeniser) != nil {
			return Token{kind = .Invalid, offset = tokeniser.offset}
		}
		if tokeniser.buffer_length == 0 {
			return Token{kind = .EOF, offset = tokeniser.offset}
		}
	}

	token_offset := tokeniser.offset
	character := tokeniser.buffer[tokeniser.buffer_cursor]
	tokeniser.buffer_cursor += 1
	tokeniser.offset += 1

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
	case:
		return Token{kind = .Invalid, offset = token_offset}
	}
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
