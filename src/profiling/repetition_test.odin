package profiling

import "core:testing"

@(test)
repetition_tester_records_results_test :: proc(t: ^testing.T) {
	tester: Repetition_Tester
	repetition_test_start(&tester, 64, 1_000_000_000, seconds_to_try = 1)

	tester.current = Repetition_Measurement {
		elapsed_cycles = 30,
		processed_bytes = 64,
		open_block_count = 1,
		close_block_count = 1,
	}
	testing.expect(t, repetition_test_commit(&tester))
	tester.current = Repetition_Measurement {
		elapsed_cycles = 10,
		processed_bytes = 64,
		open_block_count = 1,
		close_block_count = 1,
	}
	testing.expect(t, repetition_test_commit(&tester))

	testing.expect_value(t, tester.result.iteration_count, u64(2))
	testing.expect_value(t, tester.result.total_cycles, u64(40))
	testing.expect_value(t, tester.result.minimum_cycles, u64(10))
	testing.expect_value(t, tester.result.maximum_cycles, u64(30))
}

@(test)
repetition_tester_times_blocks_test :: proc(t: ^testing.T) {
	tester: Repetition_Tester
	repetition_test_start(&tester, 64, 1_000_000_000, seconds_to_try = 1)

	repetition_test_begin_time(&tester)
	repetition_test_end_time(&tester)
	repetition_test_count_bytes(&tester, 64)

	testing.expect(t, !tester.timing_active)
	testing.expect_value(t, tester.current.open_block_count, u32(1))
	testing.expect_value(t, tester.current.close_block_count, u32(1))
	testing.expect(t, repetition_test_commit(&tester))
	testing.expect_value(t, tester.result.iteration_count, u64(1))
}

@(test)
repetition_tester_rejects_wrong_byte_count_test :: proc(t: ^testing.T) {
	tester: Repetition_Tester
	repetition_test_start(&tester, 64, 1_000_000_000, seconds_to_try = 1)
	tester.current = Repetition_Measurement {
		elapsed_cycles = 10,
		processed_bytes = 63,
		open_block_count = 1,
		close_block_count = 1,
	}

	testing.expect(t, !repetition_test_commit(&tester))
	testing.expect_value(t, tester.state, Repetition_Test_State.Error)
	testing.expect_value(
		t,
		tester.error_message,
		"Processed byte count does not match the target",
	)
}
