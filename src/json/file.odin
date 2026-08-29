#+private
package json

import "base:runtime"
import "core:os"

Read_File_Proc :: #type proc(
	source: rawptr,
	scratch: []byte,
) -> (
	data: []byte,
	end_of_file: bool,
	error_kind: Error_Kind,
)

Destroy_File_Proc :: #type proc(source: rawptr)

File_Input :: struct {
	source:    rawptr,
	read:      Read_File_Proc,
	destroy:   Destroy_File_Proc,
}

Bytes_File_Source :: struct {
	data:     []byte,
	consumed: bool,
	allocator: runtime.Allocator,
}

file_input_open :: proc(file_path: string) -> (input: File_Input, error_kind: Error_Kind) {
	file, open_error := os.open(file_path)
	if open_error != nil {
		return {}, .Open_File
	}
	return File_Input {
		source = file,
		read = read_os_file,
		destroy = destroy_os_file,
	}, .None
}

file_input_from_bytes :: proc(data: []byte) -> File_Input {
	allocator := context.allocator
	source := new(Bytes_File_Source, allocator)
	source^ = Bytes_File_Source {
		data = data,
		allocator = allocator,
	}
	return File_Input {
		source = source,
		read = read_bytes_file,
		destroy = destroy_bytes_file,
	}
}

read_file :: proc(input: ^File_Input, scratch: []byte) -> (
	data: []byte,
	end_of_file: bool,
	error_kind: Error_Kind,
) {
	if input.read == nil {
		return nil, false, .Read_File
	}
	return input.read(input.source, scratch)
}

file_input_destroy :: proc(input: ^File_Input) {
	if input.destroy != nil {
		input.destroy(input.source)
	}
	input^ = {}
}

read_os_file :: proc(source: rawptr, scratch: []byte) -> (
	data: []byte,
	end_of_file: bool,
	error_kind: Error_Kind,
) {
	bytes_read, read_error := os.read((^os.File)(source), scratch)
	if read_error == .EOF {
		return scratch[:bytes_read], true, .None
	}
	if read_error != nil {
		return nil, false, .Read_File
	}
	return scratch[:bytes_read], false, .None
}

destroy_os_file :: proc(source: rawptr) {
	os.close((^os.File)(source))
}

read_bytes_file :: proc(source: rawptr, _: []byte) -> (
	data: []byte,
	end_of_file: bool,
	error_kind: Error_Kind,
) {
	bytes := (^Bytes_File_Source)(source)
	if bytes.consumed {
		return nil, true, .None
	}
	bytes.consumed = true
	return bytes.data, true, .None
}

destroy_bytes_file :: proc(source: rawptr) {
	bytes := (^Bytes_File_Source)(source)
	free(bytes, bytes.allocator)
}
