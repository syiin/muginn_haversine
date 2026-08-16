package main

import "core:flags"
import "core:os"

import "../../src/json"

Options :: struct {
	file_path:        string `args:"required" usage:"Path to the input JSON file."`,
	output_file_path: string `args:"required" usage:"Path to the output file."`,
}

main :: proc() {
	options: Options
	flags.parse_or_exit(&options, os.args, .Unix)
}
