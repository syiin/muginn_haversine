package profiling

import "core:testing"

@(test)
repetition_tester_records_results_test :: proc(t: ^testing.T) {
	tester: Repetition_Tester
	repetition_test_start(&tester, 64, 1_000_000_000, seconds_to_try = 1)

	tester.current = Repetition_Measurement {
		metrics = {
			.Cycles = 30,
			.Page_Faults = 3,
		},
		processed_bytes = 64,
		open_block_count = 1,
		close_block_count = 1,
	}
	testing.expect(t, repetition_test_commit(&tester))
	tester.current = Repetition_Measurement {
		metrics = {
			.Cycles = 10,
			.Page_Faults = 1,
		},
		processed_bytes = 64,
		open_block_count = 1,
		close_block_count = 1,
	}
	testing.expect(t, repetition_test_commit(&tester))

	testing.expect_value(t, tester.result.iteration_count, u64(2))
	cycles := tester.result.metrics[Repetition_Test_Metric_Kind.Cycles]
	testing.expect_value(t, cycles.total, u64(40))
	testing.expect_value(t, cycles.minimum, u64(10))
	testing.expect_value(t, cycles.maximum, u64(30))
	page_faults := tester.result.metrics[Repetition_Test_Metric_Kind.Page_Faults]
	testing.expect_value(t, page_faults.total, u64(4))
	testing.expect_value(t, page_faults.minimum, u64(1))
	testing.expect_value(t, page_faults.maximum, u64(3))
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
	testing.expect(t, tester.current.metrics[Repetition_Test_Metric_Kind.Cycles] > 0)
	testing.expect(t, repetition_test_commit(&tester))
	testing.expect_value(t, tester.result.iteration_count, u64(1))
}

@(test)
repetition_tester_rejects_wrong_byte_count_test :: proc(t: ^testing.T) {
	tester: Repetition_Tester
	repetition_test_start(&tester, 64, 1_000_000_000, seconds_to_try = 1)
	tester.current = Repetition_Measurement {
		metrics = {.Cycles = 10, .Page_Faults = 0},
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
