package main

import "core:flags"
import "core:fmt"
import "core:io"
import "core:os"

import "../../src/fuzzer"
import "../../src/haversine"

PAIRS_PATH :: "pairs.json"
DISTANCES_PATH :: "distance.f64"

Options :: struct {
	seed:             u64 `args:"required" usage:"Seed for the random number generator."`,
	number_of_points: u64 `args:"required" usage:"Number of random coordinate pairs to generate."`,
	n_clusters:       u64 `args:"required" usage:"Number of coordinate clusters to generate."`,
}

random_bounds :: proc(randomizer: ^fuzzer.Fuzzer, low, high: f64) -> (f64, f64) {
	bound_0 := fuzzer.random_number(randomizer, low, high)
	bound_1 := fuzzer.random_number(randomizer, low, high)
	for bound_1 == bound_0 {
		bound_1 = fuzzer.random_number(randomizer, low, high)
	}
	return min(bound_0, bound_1), max(bound_0, bound_1)
}

open_append_file :: proc(path: string) -> ^os.File {
	file, open_error := os.open(
		path,
		{.Write, .Append, .Create},
		os.Permissions_Default_File,
	)
	if open_error != nil {
		fmt.eprintfln("Could not open %q: %v", path, open_error)
		os.exit(1)
	}
	return file
}

append_pair :: proc(pairs_file: ^os.File, x0, y0, x1, y1: f64) {
	fmt.wprintfln(
		os.to_stream(pairs_file),
		"{{\"x0\":%v,\"y0\":%v,\"x1\":%v,\"y1\":%v}}",
		x0,
		y0,
		x1,
		y1,
	)
}

append_distance :: proc(distances_file: ^os.File, distance: f64) {
	value := f64le(distance)
	bytes := ([^]byte)(&value)[:size_of(value)]
	_, write_error := io.write_full(os.to_stream(distances_file), bytes)
	if write_error != nil {
		fmt.eprintfln("Could not append to %q: %v", DISTANCES_PATH, write_error)
		os.exit(1)
	}
}

main :: proc() {
	options: Options
	flags.parse_or_exit(&options, os.args, .Unix)

	if options.n_clusters == 0 {
		fmt.eprintfln("--n-clusters must be greater than zero")
		os.exit(1)
	}
	if options.number_of_points % options.n_clusters != 0 {
		fmt.eprintfln("--number-of-points must be divisible by --n-clusters")
		os.exit(1)
	}
	pairs_per_cluster := options.number_of_points / options.n_clusters

	pairs_file := open_append_file(PAIRS_PATH)
	defer os.close(pairs_file)
	distances_file := open_append_file(DISTANCES_PATH)
	defer os.close(distances_file)

	randomizer: fuzzer.Fuzzer
	fuzzer.init(&randomizer, options.seed)

	distances: [dynamic]f64
	defer delete(distances)

	fmt.println("Pairs: [")
	for _ in 0 ..< options.n_clusters {
		x_low, x_high := random_bounds(&randomizer, -180, 180)
		y_low, y_high := random_bounds(&randomizer, -90, 90)

		for _ in 0 ..< pairs_per_cluster {
			x0 := fuzzer.random_number(&randomizer, x_low, x_high)
			y0 := fuzzer.random_number(&randomizer, y_low, y_high)
			x1 := fuzzer.random_number(&randomizer, x_low, x_high)
			y1 := fuzzer.random_number(&randomizer, y_low, y_high)
			distance := haversine.distance(y0, x0, y1, x1)

			append_pair(pairs_file, x0, y0, x1, y1)
			append_distance(distances_file, distance)
			fmt.printfln("\t{{x0: %v, y0: %v, x1: %v, y1: %v}},", x0, y0, x1, y1)
			append(&distances, distance)
		}
	}
	fmt.println("]")

	fmt.println("Distances: [")
	for distance in distances {
		fmt.printfln("\t%v,", distance)
	}
	fmt.println("]")
}
