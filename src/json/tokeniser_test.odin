package json

import "core:testing"

test_tokeniser :: proc(input: string) -> Tokeniser {
	tokeniser: Tokeniser
	copy(tokeniser.buffer[:], transmute([]byte)input)
	tokeniser.buffer_length = len(input)
	tokeniser.reached_end_of_file = true
	return tokeniser
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
		delete(tokeniser.token_buffer)
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
		delete(tokeniser.token_buffer)
	}
}

@(test)
tokeniser_number_leaves_delimiter_test :: proc(t: ^testing.T) {
	tokeniser := test_tokeniser("-12.5e+2,")
	defer delete(tokeniser.token_buffer)

	number := tokeniser_next(&tokeniser)
	testing.expect_value(t, number.kind, Token_Kind.Number)
	testing.expect_value(t, number.lexeme, "-12.5e+2")

	delimiter := tokeniser_next(&tokeniser)
	testing.expect_value(t, delimiter.kind, Token_Kind.Comma)
	testing.expect_value(t, delimiter.offset, 8)
}
