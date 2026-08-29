package json

import "core:testing"

test_tokeniser :: proc(input: string) -> Tokeniser {
	tokeniser: Tokeniser
	err := tokeniser_init_from_file_input(
		&tokeniser,
		file_input_from_bytes(transmute([]byte)input),
	)
	assert(err.kind == .None)
	return tokeniser
}

Counting_File_Source :: struct {
	data:   []byte,
	cursor: int,
	reads:  int,
}

read_counting_file :: proc(source: rawptr, _: []byte) -> (
	data: []byte,
	end_of_file: bool,
	error_kind: Error_Kind,
) {
	file := (^Counting_File_Source)(source)
	file.reads += 1
	if file.cursor == len(file.data) {
		return nil, true, .None
	}
	start := file.cursor
	file.cursor += 1
	return file.data[start:file.cursor], false, .None
}

read_stalled_file :: proc(_: rawptr, _: []byte) -> (
	data: []byte,
	end_of_file: bool,
	error_kind: Error_Kind,
) {
	return nil, false, .None
}

@(test)
tokeniser_refill_no_op_test :: proc(t: ^testing.T) {
	data := []byte{'{', '}'}
	source := Counting_File_Source{data = data}
	tokeniser: Tokeniser
	err := tokeniser_init_from_file_input(
		&tokeniser,
		File_Input{source = &source, read = read_counting_file},
	)
	defer tokeniser_destroy(&tokeniser)

	testing.expect_value(t, err.kind, Error_Kind.None)
	testing.expect_value(t, source.reads, 1)
	testing.expect_value(t, tokeniser_refill(&tokeniser), Error_Kind.None)
	testing.expect_value(t, source.reads, 1)

	testing.expect_value(t, tokeniser_next(&tokeniser).kind, Token_Kind.Left_Brace)
	testing.expect_value(t, source.reads, 1)
	testing.expect_value(t, tokeniser_next(&tokeniser).kind, Token_Kind.Right_Brace)
	testing.expect_value(t, source.reads, 2)
	testing.expect_value(t, tokeniser_next(&tokeniser).kind, Token_Kind.EOF)
	testing.expect_value(t, source.reads, 3)
}

@(test)
tokeniser_refill_requires_progress_test :: proc(t: ^testing.T) {
	tokeniser: Tokeniser
	err := tokeniser_init_from_file_input(
		&tokeniser,
		File_Input{read = read_stalled_file},
	)
	testing.expect_value(t, err.kind, Error_Kind.Read_File)
}

@(test)
tokeniser_number_test :: proc(t: ^testing.T) {
	valid_numbers := []string {
		"0",
		"-0",
		"12",
		"-12.5",
		"0.5",
		"1e2",
		"1E-2",
		"1e+2",
	}
	for number in valid_numbers {
		tokeniser := test_tokeniser(number)
		token := tokeniser_next(&tokeniser)
		testing.expect_value(t, token.kind, Token_Kind.Number)
		testing.expect_value(t, token.lexeme, number)
		testing.expect_value(t, token.offset, 0)
		tokeniser_destroy(&tokeniser)
	}

	invalid_numbers := []string {
		"-",
		"01",
		"1.",
		"1e",
		"1e+",
	}
	for number in invalid_numbers {
		tokeniser := test_tokeniser(number)
		token := tokeniser_next(&tokeniser)
		testing.expect_value(t, token.kind, Token_Kind.Invalid)
		testing.expect_value(t, token.lexeme, number)
		tokeniser_destroy(&tokeniser)
	}
}

@(test)
tokeniser_number_leaves_delimiter_test :: proc(t: ^testing.T) {
	tokeniser := test_tokeniser("-12.5e+2,")
	defer tokeniser_destroy(&tokeniser)

	number := tokeniser_next(&tokeniser)
	testing.expect_value(t, number.kind, Token_Kind.Number)
	testing.expect_value(t, number.lexeme, "-12.5e+2")

	delimiter := tokeniser_next(&tokeniser)
	testing.expect_value(t, delimiter.kind, Token_Kind.Comma)
	testing.expect_value(t, delimiter.offset, 8)
}

@(test)
tokeniser_string_test :: proc(t: ^testing.T) {
	valid_strings := []string {
		"\"\"",
		"\"hello\"",
		"\"hello world\"",
	}
	for value in valid_strings {
		tokeniser := test_tokeniser(value)
		token := tokeniser_next(&tokeniser)
		testing.expect_value(t, token.kind, Token_Kind.String)
		testing.expect_value(t, token.lexeme, value)
		testing.expect_value(t, token.offset, 0)
		tokeniser_destroy(&tokeniser)
	}

	invalid_strings := []string {
		"\"unterminated",
		"\"line\nbreak\"",
		"\"escape\\value\"",
	}
	for value in invalid_strings {
		tokeniser := test_tokeniser(value)
		token := tokeniser_next(&tokeniser)
		testing.expect_value(t, token.kind, Token_Kind.Invalid)
		tokeniser_destroy(&tokeniser)
	}
}

@(test)
tokeniser_string_leaves_delimiter_test :: proc(t: ^testing.T) {
	tokeniser := test_tokeniser("\"hello\",")
	defer tokeniser_destroy(&tokeniser)

	value := tokeniser_next(&tokeniser)
	testing.expect_value(t, value.kind, Token_Kind.String)
	testing.expect_value(t, value.lexeme, "\"hello\"")

	delimiter := tokeniser_next(&tokeniser)
	testing.expect_value(t, delimiter.kind, Token_Kind.Comma)
	testing.expect_value(t, delimiter.offset, 7)
}

@(test)
tokeniser_whitespace_test :: proc(t: ^testing.T) {
	tokeniser := test_tokeniser(" \t\n\r{")
	defer tokeniser_destroy(&tokeniser)

	token := tokeniser_next(&tokeniser)
	testing.expect_value(t, token.kind, Token_Kind.Left_Brace)
	testing.expect_value(t, token.offset, 4)

	whitespace_only := test_tokeniser(" \t\n\r")
	defer tokeniser_destroy(&whitespace_only)
	token = tokeniser_next(&whitespace_only)
	testing.expect_value(t, token.kind, Token_Kind.EOF)
	testing.expect_value(t, token.offset, 4)
}

@(test)
tokeniser_literal_test :: proc(t: ^testing.T) {
	tokeniser := test_tokeniser("true false null")
	defer tokeniser_destroy(&tokeniser)

	true_token := tokeniser_next(&tokeniser)
	testing.expect_value(t, true_token.kind, Token_Kind.True)
	testing.expect_value(t, true_token.lexeme, "true")
	testing.expect_value(t, true_token.offset, 0)

	false_token := tokeniser_next(&tokeniser)
	testing.expect_value(t, false_token.kind, Token_Kind.False)
	testing.expect_value(t, false_token.lexeme, "false")
	testing.expect_value(t, false_token.offset, 5)

	null_token := tokeniser_next(&tokeniser)
	testing.expect_value(t, null_token.kind, Token_Kind.Null)
	testing.expect_value(t, null_token.lexeme, "null")
	testing.expect_value(t, null_token.offset, 11)

	invalid_literals := []string {
		"tru",
		"fals",
		"nul",
		"tx",
	}
	for value in invalid_literals {
		invalid_tokeniser := test_tokeniser(value)
		token := tokeniser_next(&invalid_tokeniser)
		testing.expect_value(t, token.kind, Token_Kind.Invalid)
		tokeniser_destroy(&invalid_tokeniser)
	}
}
