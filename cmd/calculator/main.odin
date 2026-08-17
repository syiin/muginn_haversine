package main

import "core:encoding/endian"
import "core:flags"
import "core:fmt"
import "core:os"

import "../../src/haversine"
import "../../src/json"
import "../../src/profiling"

Options :: struct {
	file_path:          string `args:"required" usage:"Path to the input JSON file."`,
	output_file_path:   string `args:"required" usage:"Path to the output file."`,
	distance_file_path: string `usage:"Optional path to little-endian f64 reference distances."`,
}

DISTANCE_SIZE :: size_of(f64)
DISTANCE_READ_BUFFER_SIZE :: 64 * 1024

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

accumulate_distances :: proc(data: []byte, total: ^f64, count: ^int) -> bool {
	for offset := 0; offset < len(data); offset += DISTANCE_SIZE {
		distance, ok := endian.get_f64(data[offset:offset + DISTANCE_SIZE], .Little)
		if !ok {
			return false
		}
		total^ += distance
		count^ += 1
	}
	return true
}

read_average_distance :: proc(file_path: string) -> (f64, bool) {
	file, open_error := os.open(file_path)
	if open_error != nil {
		return 0, false
	}
	defer os.close(file)

	buffer: [DISTANCE_READ_BUFFER_SIZE + DISTANCE_SIZE - 1]byte
	remaining := 0
	total_distance: f64
	distance_count := 0
	for {
		bytes_read, read_error := os.read(
			file,
			buffer[remaining:remaining + DISTANCE_READ_BUFFER_SIZE],
		)
		buffered := remaining + bytes_read
		complete_bytes := buffered - buffered % DISTANCE_SIZE
		if !accumulate_distances(buffer[:complete_bytes], &total_distance, &distance_count) {
			return 0, false
		}

		remaining = buffered - complete_bytes
		copy(buffer[:remaining], buffer[complete_bytes:buffered])
		if read_error == .EOF {
			break
		}
		if read_error != nil || bytes_read == 0 {
			return 0, false
		}
	}

	if remaining != 0 || distance_count == 0 {
		return 0, false
	}
	return total_distance / f64(distance_count), true
}

print_time_elapsed :: proc(label: string, total_elapsed: u64, begin: u64, end: u64) {
	elapsed := end - begin
	percent := 100.0 * f64(elapsed) / f64(total_elapsed)
	fmt.printfln("%s: %d (%.2f%%)", label, elapsed, percent)
}

main :: proc() {
	prof_begin := profiling.read_cpu_timer()
	options: Options
	prof_read := profiling.read_cpu_timer()
	flags.parse_or_exit(&options, os.args, .Unix)

	prof_parse := profiling.read_cpu_timer()
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

	prof_sum := profiling.read_cpu_timer()
	average_distance, valid := calculate_average_distance(value)
	if !valid {
		fmt.eprintfln(
			"Expected %q to contain a non-empty array of coordinate pairs",
			options.file_path,
		)
		os.exit(1)
	}
	fmt.printfln("Average distance: %v km", average_distance)

	prof_check := profiling.read_cpu_timer()
	if options.distance_file_path != "" {
		reference_average, reference_valid := read_average_distance(options.distance_file_path)
		if !reference_valid {
			fmt.eprintfln("Could not read reference distances from %q", options.distance_file_path)
			os.exit(1)
		}
		fmt.printfln("Distance delta: %v km", average_distance - reference_average)
	}

	prof_end := profiling.read_cpu_timer()
	total_elapsed := prof_end - prof_begin
	cpu_frequency := profiling.estimate_cpu_timer_frequency()
	total_milliseconds := 1_000.0 * f64(total_elapsed) / f64(cpu_frequency)

	fmt.printfln("Total time: %.4f ms (CPU frequency: %d)", total_milliseconds, cpu_frequency)

	profile_labels := [?]string{"Startup", "Read", "Parse", "Sum", "Check"}
	profile_timestamps := [?]u64{
		prof_begin,
		prof_read,
		prof_parse,
		prof_sum,
		prof_check,
		prof_end,
	}
	for label, index in profile_labels {
		print_time_elapsed(
			label,
			total_elapsed,
			profile_timestamps[index],
			profile_timestamps[index + 1],
		)
	}
}
