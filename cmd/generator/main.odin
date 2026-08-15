package main

import "core:flags"
import "core:fmt"
import "core:os"

import "../../src/fuzzer"

Options :: struct {
	seed:             u64 `args:"required" usage:"Seed for the random number generator."`,
	number_of_points: u64 `args:"required" usage:"Number of random points to generate."`,
}

main :: proc() {
	options: Options
	flags.parse_or_exit(&options, os.args, .Unix)

	randomizer: fuzzer.Fuzzer
	fuzzer.init(&randomizer, options.seed)

	for _ in 0 ..< options.number_of_points {
		fmt.println(fuzzer.random_number(&randomizer))
	}
}
