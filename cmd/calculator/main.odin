package main

import "core:encoding/endian"
import "core:flags"
import "core:fmt"
import "core:os"

import "../../src/haversine"
import "../../src/json"

Options :: struct {
	file_path:          string `args:"required" usage:"Path to the input JSON file."`,
	output_file_path:   string `args:"required" usage:"Path to the output file."`,
	distance_file_path: string `usage:"Optional path to little-endian f64 reference distances."`,
}

object_number :: proc(object: json.Object, key: string) -> (f64, bool) {
	value, found := object[key]
	if !found {
		return 0, false
	}
	number, is_number := value.(json.Number)
	if !is_number {
		return 0, false
	}
	return number, true
}

calculate_average_distance :: proc(value: json.Value) -> (f64, bool) {
	root, is_object := value.(json.Object)
	if !is_object {
		return 0, false
	}
	pairs_value, found := root["pairs"]
	if !found {
		return 0, false
	}
	pairs, is_array := pairs_value.(json.Array)
	if !is_array || len(pairs) == 0 {
		return 0, false
	}

	total_distance: f64
	for pair_value in pairs {
		pair, is_pair := pair_value.(json.Object)
		if !is_pair {
			return 0, false
		}
		x0, has_x0 := object_number(pair, "x0")
		y0, has_y0 := object_number(pair, "y0")
		x1, has_x1 := object_number(pair, "x1")
		y1, has_y1 := object_number(pair, "y1")
		if !has_x0 || !has_y0 || !has_x1 || !has_y1 {
			return 0, false
		}
		total_distance += haversine.distance(y0, x0, y1, x1)
	}
	return total_distance / f64(len(pairs)), true
}

read_average_distance :: proc(file_path: string) -> (f64, bool) {
	data, read_error := os.read_entire_file(file_path, context.allocator)
	if read_error != nil {
		return 0, false
	}
	defer delete(data)

	distance_size := size_of(f64)
	if len(data) == 0 || len(data) % distance_size != 0 {
		return 0, false
	}

	total_distance: f64
	for offset := 0; offset < len(data); offset += distance_size {
		distance, ok := endian.get_f64(data[offset:], .Little)
		if !ok {
			return 0, false
		}
		total_distance += distance
	}
	return total_distance / f64(len(data) / distance_size), true
}

main :: proc() {
	options: Options
	flags.parse_or_exit(&options, os.args, .Unix)

	value, parse_error := json.parse(options.file_path)
	if parse_error.kind != .None {
		fmt.eprintfln(
			"Could not parse %q: %v at byte offset %d",
			options.file_path,
			parse_error.kind,
			parse_error.offset,
		)
		os.exit(1)
	}
	defer json.destroy(value)

	average_distance, valid := calculate_average_distance(value)
	if !valid {
		fmt.eprintfln("Expected %q to contain a non-empty array of coordinate pairs", options.file_path)
		os.exit(1)
	}
	fmt.printfln("Average distance: %v km", average_distance)

	if options.distance_file_path != "" {
		reference_average, reference_valid := read_average_distance(options.distance_file_path)
		if !reference_valid {
			fmt.eprintfln("Could not read reference distances from %q", options.distance_file_path)
			os.exit(1)
		}
		fmt.printfln("Distance delta: %v km", average_distance - reference_average)
	}
}
