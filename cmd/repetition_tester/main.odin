package main

import "base:intrinsics"
import "core:c/libc"
import "core:flags"
import "core:fmt"
import mem_virtual "core:mem/virtual"
import "core:os"
import "core:strings"

import "../../src/profiling"

READ_BUFFER_SIZE :: 1024 * 1024

Options :: struct {
	file_path:      string `args:"required" usage:"Path to the file to benchmark."`,
	seconds_to_try: f64    `usage:"Seconds without a new minimum before each method completes."`,
}

Read_Context :: struct {
	file_path:   string,
	c_file_path: cstring,
	buffer:      []byte,
}

Read_Result :: struct {
	bytes_read: u64,
	checksum:   u64,
	ok:         bool,
}

Read_File_Proc :: proc(read_context: ^Read_Context) -> Read_Result

Benchmark_Method :: struct {
	name: string,
	read: Read_File_Proc,
}

@(private)
benchmark_sink: u64

checksum_bytes :: proc(data: []byte, initial: u64 = 0) -> u64 {
	checksum := initial
	for value in data {
		checksum += u64(value)
	}
	return checksum
}

read_with_os_read :: proc(read_context: ^Read_Context) -> (result: Read_Result) {
	file, open_error := os.open(read_context.file_path)
	if open_error != nil {
		return
	}

	for {
		bytes_read, read_error := os.read(file, read_context.buffer)
		if bytes_read > 0 {
			result.bytes_read += u64(bytes_read)
			result.checksum = checksum_bytes(read_context.buffer[:bytes_read], result.checksum)
		}
		if read_error == .EOF {
			break
		}
		if read_error != nil || bytes_read == 0 {
			os.close(file)
			return
		}
	}

	result.ok = os.close(file) == nil
	return
}

read_with_fread :: proc(read_context: ^Read_Context) -> (result: Read_Result) {
	file := libc.fopen(read_context.c_file_path, "rb")
	if file == nil {
		return
	}

	for {
		bytes_read := int(
			libc.fread(
				raw_data(read_context.buffer),
				size_of(byte),
				len(read_context.buffer),
				file,
			),
		)
		if bytes_read > 0 {
			result.bytes_read += u64(bytes_read)
			result.checksum = checksum_bytes(read_context.buffer[:bytes_read], result.checksum)
		}
		if bytes_read < len(read_context.buffer) {
			if libc.ferror(file) != 0 {
				libc.fclose(file)
				return
			}
			if libc.feof(file) != 0 {
				break
			}
			if bytes_read == 0 {
				libc.fclose(file)
				return
			}
		}
	}

	result.ok = libc.fclose(file) == 0
	return
}

read_with_entire_file :: proc(read_context: ^Read_Context) -> (result: Read_Result) {
	data, read_error := os.read_entire_file(read_context.file_path, context.allocator)
	if read_error != nil {
		delete(data)
		return
	}

	result.bytes_read = u64(len(data))
	result.checksum = checksum_bytes(data)
	delete(data)
	result.ok = true
	return
}

read_with_memory_map :: proc(read_context: ^Read_Context) -> (result: Read_Result) {
	data, map_error := mem_virtual.map_file_from_path(read_context.file_path, {.Read})
	if map_error != .None {
		return
	}

	result.bytes_read = u64(len(data))
	result.checksum = checksum_bytes(data)
	mem_virtual.unmap_file(data)
	result.ok = true
	return
}

BENCHMARK_METHODS: [4]Benchmark_Method = {
	{name = "os.read", read = read_with_os_read},
	{name = "fread", read = read_with_fread},
	{name = "os.read_entire_file", read = read_with_entire_file},
	{name = "memory map", read = read_with_memory_map},
}

file_size :: proc(file_path: string) -> (u64, bool) {
	file, open_error := os.open(file_path)
	if open_error != nil {
		return 0, false
	}
	size, size_error := os.file_size(file)
	close_error := os.close(file)
	if size_error != nil || close_error != nil || size <= 0 || i64(u64(size)) != size {
		return 0, false
	}
	return u64(size), true
}

validate_methods :: proc(
	read_context: ^Read_Context,
	expected_byte_count: u64,
) -> (expected_checksum: u64, ok: bool) {
	for method, index in BENCHMARK_METHODS {
		result := method.read(read_context)
		if !result.ok || result.bytes_read != expected_byte_count {
			fmt.eprintfln("%s failed to read the complete file", method.name)
			return
		}
		if index == 0 {
			expected_checksum = result.checksum
		} else if result.checksum != expected_checksum {
			fmt.eprintfln("%s read different file contents", method.name)
			return
		}
	}
	return expected_checksum, true
}

run_method :: proc(
	method: Benchmark_Method,
	read_context: ^Read_Context,
	expected_byte_count: u64,
	expected_checksum: u64,
	cpu_timer_frequency: u64,
	seconds_to_try: f64,
) -> bool {
	fmt.printfln("\n%s", method.name)

	tester: profiling.Repetition_Tester
	profiling.repetition_test_start(
		&tester,
		expected_byte_count,
		cpu_timer_frequency,
		seconds_to_try,
	)
	for profiling.repetition_test_is_testing(&tester) {
		profiling.repetition_test_begin_time(&tester)
		result := method.read(read_context)
		profiling.repetition_test_end_time(&tester)

		if !result.ok {
			profiling.repetition_test_error(&tester, "File read failed")
			break
		}
		if result.checksum != expected_checksum {
			profiling.repetition_test_error(&tester, "File contents changed during the test")
			break
		}
		intrinsics.volatile_store(&benchmark_sink, result.checksum)
		profiling.repetition_test_count_bytes(&tester, result.bytes_read)
	}

	profiling.print_repetition_test_result(&tester)
	return tester.state != .Error
}

main :: proc() {
	options := Options{seconds_to_try = 1}
	flags.parse_or_exit(&options, os.args, .Unix)
	if options.seconds_to_try <= 0 {
		fmt.eprintln("--seconds-to-try must be greater than zero")
		os.exit(1)
	}

	expected_byte_count, size_valid := file_size(options.file_path)
	if !size_valid {
		fmt.eprintfln("Could not read a non-empty regular file from %q", options.file_path)
		os.exit(1)
	}

	c_file_path, c_path_error := strings.clone_to_cstring(options.file_path)
	if c_path_error != nil {
		fmt.eprintln("Could not allocate the C file path")
		os.exit(1)
	}
	defer delete(c_file_path)

	buffer := make([]byte, READ_BUFFER_SIZE)
	defer delete(buffer)
	read_context := Read_Context {
		file_path = options.file_path,
		c_file_path = c_file_path,
		buffer = buffer,
	}

	expected_checksum, methods_valid := validate_methods(&read_context, expected_byte_count)
	if !methods_valid {
		os.exit(1)
	}

	cpu_timer_frequency := profiling.estimate_cpu_timer_frequency()
	if cpu_timer_frequency == 0 {
		fmt.eprintln("Could not estimate the CPU timer frequency")
		os.exit(1)
	}

	fmt.printfln(
		"Warm-cache read benchmark for %q (%d bytes)",
		options.file_path,
		expected_byte_count,
	)
	fmt.println("Each timed repetition opens, reads and touches every byte, then closes the file.")
	for method in BENCHMARK_METHODS {
		if !run_method(
			method,
			&read_context,
			expected_byte_count,
			expected_checksum,
			cpu_timer_frequency,
			options.seconds_to_try,
		) {
			os.exit(1)
		}
	}
}
