package fuzzer

import "core:testing"

@(test)
random_number_test :: proc(t: ^testing.T) {
	first, second: Fuzzer
	init(&first, 42)
	init(&second, 42)

	default_number := random_number(&first)
	testing.expect(t, default_number >= 0 && default_number < 1)
	testing.expect_value(t, default_number, random_number(&second))

	latitude := random_number(&first, -90, 90)
	testing.expect(t, latitude >= -90 && latitude < 90)
	testing.expect_value(t, latitude, random_number(&second, -90, 90))
}
