package main

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import mem_virtual "core:mem/virtual"
import "core:os"

import "../../src/profiling"

PAGE_COUNT :: 1024
SECONDS_TO_TRY :: 1
CSV_FILE_PATH :: "page_faults.csv"

Page_Direction :: enum {
	Forwards,
	Backwards,
}

main :: proc() {
	allocation_size := uint(PAGE_COUNT * mem.PAGE_SIZE)
	cpu_timer_frequency := profiling.estimate_cpu_timer_frequency()
	csv_file, create_error := os.create(CSV_FILE_PATH)
	if create_error != nil {
		fmt.eprintfln("Could not create %q", CSV_FILE_PATH)
		os.exit(1)
	}
	defer os.close(csv_file)
	_, header_error := os.write_string(csv_file, "direction,allocation,page_faults\n")
	if header_error != nil {
		fmt.eprintfln("Could not write to %q", CSV_FILE_PATH)
		os.exit(1)
	}

	fmt.printfln(
		"Page fault test: touching %d pages (%d bytes)",
		PAGE_COUNT,
		allocation_size,
	)
	fmt.printfln("Streaming results to %q", CSV_FILE_PATH)
	for direction in Page_Direction {
		tester: profiling.Repetition_Tester
		profiling.repetition_test_start(
			&tester,
			u64(allocation_size),
			cpu_timer_frequency,
			seconds_to_try = SECONDS_TO_TRY,
		)

		fmt.printfln("\n%s", direction)
		allocation_index: u64
		for profiling.repetition_test_is_testing(&tester) {
			data, allocation_error := mem_virtual.reserve_and_commit(allocation_size)
			if allocation_error != nil {
				profiling.repetition_test_error(&tester, "Virtual memory allocation failed")
				break
			}

			profiling.repetition_test_begin_time(&tester)
			switch direction {
			case .Forwards:
				for offset := 0; offset < len(data); offset += mem.PAGE_SIZE {
					intrinsics.volatile_store(&data[offset], byte(1))
				}
			case .Backwards:
				for offset := len(data); offset > 0; offset -= mem.PAGE_SIZE {
					intrinsics.volatile_store(&data[offset - mem.PAGE_SIZE], byte(1))
				}
			}
			profiling.repetition_test_end_time(&tester)

			mem_virtual.release(raw_data(data), allocation_size)
			if tester.state != .Testing {
				break
			}
			profiling.repetition_test_count_bytes(&tester, u64(allocation_size))
			allocation_index += 1
			row_buffer: [128]byte
			row := fmt.bprintf(
				row_buffer[:],
				"%s,%d,%d\n",
				direction,
				allocation_index,
				tester.current.metrics[profiling.Repetition_Test_Metric_Kind.Page_Faults],
			)
			_, write_error := os.write_string(csv_file, row)
			if write_error != nil {
				profiling.repetition_test_error(&tester, "Could not write the CSV result")
				break
			}
		}

		profiling.print_repetition_test_result(&tester)
	}
}
