package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
read_methods_return_the_same_file_test :: proc(t: ^testing.T) {
	file, create_error := os.create_temp_file("", "muginn-read-benchmark-*.txt")
	testing.expect(t, create_error == nil, "Expected to create a temporary file")
	if create_error != nil {
		return
	}

	file_info, stat_error := os.fstat(file, context.allocator)
	testing.expect(t, stat_error == nil, "Expected to inspect the temporary file")
	if stat_error != nil {
		os.close(file)
		return
	}
	defer os.file_info_delete(file_info, context.allocator)
	defer os.remove(file_info.fullpath)

	contents := "0123456789abcdefghijklmnopqrstuvwxyz"
	_, write_error := os.write_string(file, contents)
	close_error := os.close(file)
	testing.expect(t, write_error == nil, "Expected to write the temporary file")
	testing.expect(t, close_error == nil, "Expected to close the temporary file")
	if write_error != nil || close_error != nil {
		return
	}

	c_file_path, c_path_error := strings.clone_to_cstring(file_info.fullpath)
	testing.expect(t, c_path_error == nil, "Expected to allocate the C file path")
	if c_path_error != nil {
		return
	}
	defer delete(c_file_path)

	buffer: [7]byte
	read_context := Read_Context {
		file_path = file_info.fullpath,
		c_file_path = c_file_path,
		buffer = buffer[:],
	}
	expected_checksum := checksum_bytes(transmute([]byte)contents)
	for method in BENCHMARK_METHODS {
		result := method.read(&read_context)
		testing.expect(t, result.ok, method.name)
		testing.expect_value(t, result.bytes_read, u64(len(contents)))
		testing.expect_value(t, result.checksum, expected_checksum)
	}
}
