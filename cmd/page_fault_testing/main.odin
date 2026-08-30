package main

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import mem_virtual "core:mem/virtual"

import "../../src/profiling"

PAGE_COUNT :: 1024
SECONDS_TO_TRY :: 1

main :: proc() {
	allocation_size := uint(PAGE_COUNT * mem.PAGE_SIZE)
	cpu_timer_frequency := profiling.estimate_cpu_timer_frequency()

	tester: profiling.Repetition_Tester
	profiling.repetition_test_start(
		&tester,
		u64(allocation_size),
		cpu_timer_frequency,
		seconds_to_try = SECONDS_TO_TRY,
	)

	fmt.printfln(
		"Page fault test: touching %d pages (%d bytes)",
		PAGE_COUNT,
		allocation_size,
	)
	for profiling.repetition_test_is_testing(&tester) {
		data, allocation_error := mem_virtual.reserve_and_commit(allocation_size)
		if allocation_error != nil {
			profiling.repetition_test_error(&tester, "Virtual memory allocation failed")
			break
		}

		profiling.repetition_test_begin_time(&tester)
		for offset := 0; offset < len(data); offset += mem.PAGE_SIZE {
			intrinsics.volatile_store(&data[offset], byte(1))
		}
		profiling.repetition_test_end_time(&tester)

		mem_virtual.release(raw_data(data), allocation_size)
		profiling.repetition_test_count_bytes(&tester, u64(allocation_size))
	}

	profiling.print_repetition_test_result(&tester)
}
