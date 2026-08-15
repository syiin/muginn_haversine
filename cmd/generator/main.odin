package main

import "core:flags"
import "core:fmt"
import "core:os"

import "../../src/fuzzer"
import "../../src/haversine"

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

			fmt.printfln("\t{{x0: %v, y0: %v, x1: %v, y1: %v}},", x0, y0, x1, y1)
			append(&distances, haversine.distance(y0, x0, y1, x1))
		}
	}
	fmt.println("]")

	fmt.println("Distances: [")
	for distance in distances {
		fmt.printfln("\t%v,", distance)
	}
	fmt.println("]")
}
