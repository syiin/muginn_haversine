package profiling

import "core:fmt"

Repetition_Test_State :: enum {
	Ready,
	Testing,
	Completed,
	Error,
}

Repetition_Test_Metric_Kind :: enum {
	Cycles,
	Page_Faults,
}

Repetition_Test_Metric :: struct {
	total:   u64,
	minimum: u64,
	maximum: u64,
}

Repetition_Test_Result :: struct {
	iteration_count: u64,
	metrics:         [Repetition_Test_Metric_Kind]Repetition_Test_Metric,
}

Repetition_Measurement :: struct {
	metrics:           [Repetition_Test_Metric_Kind]u64,
	processed_bytes:   u64,
	open_block_count:  u32,
	close_block_count: u32,
}

Repetition_Tester :: struct {
	state:                  Repetition_Test_State,
	target_processed_bytes: u64,
	cpu_timer_frequency:    u64,
	try_for_cycles:         u64,
	last_minimum_at:        u64,
	metric_starts:          [Repetition_Test_Metric_Kind]u64,
	timing_active:          bool,
	current:                Repetition_Measurement,
	result:                 Repetition_Test_Result,
	error_message:          string,
}

repetition_test_error :: proc(tester: ^Repetition_Tester, message: string) {
	if tester.state != .Error {
		tester.state = .Error
		tester.error_message = message
	}
}

repetition_test_start :: proc(
	tester: ^Repetition_Tester,
	target_processed_bytes: u64,
	cpu_timer_frequency: u64,
	seconds_to_try: f64 = 10,
) {
	tester^ = {}
	if target_processed_bytes == 0 {
		repetition_test_error(tester, "Target processed byte count must be greater than zero")
		return
	}
	if cpu_timer_frequency == 0 {
		repetition_test_error(tester, "CPU timer frequency must be greater than zero")
		return
	}
	if seconds_to_try <= 0 {
		repetition_test_error(tester, "Test duration must be greater than zero")
		return
	}

	try_for_cycles := u64(f64(cpu_timer_frequency) * seconds_to_try)
	if try_for_cycles == 0 {
		try_for_cycles = 1
	}
	tester^ = Repetition_Tester {
		state = .Testing,
		target_processed_bytes = target_processed_bytes,
		cpu_timer_frequency = cpu_timer_frequency,
		try_for_cycles = try_for_cycles,
		last_minimum_at = read_cpu_timer(),
	}
}

repetition_test_begin_time :: proc(tester: ^Repetition_Tester) {
	if tester.state != .Testing {
		return
	}
	if tester.timing_active {
		repetition_test_error(tester, "Timing blocks cannot overlap")
		return
	}
	page_fault_count, ok := read_os_page_fault_count()
	if !ok {
		repetition_test_error(tester, "Failed to read OS page fault count")
		return
	}

	tester.current.open_block_count += 1
	tester.metric_starts[.Page_Faults] = page_fault_count
	tester.metric_starts[.Cycles] = read_cpu_timer()
	tester.timing_active = true
}

repetition_test_end_time :: proc(tester: ^Repetition_Tester) {
	if tester.state != .Testing {
		return
	}
	if !tester.timing_active {
		repetition_test_error(tester, "Timing block ended without being started")
		return
	}
	cycle_count := read_cpu_timer()
	page_fault_count, ok := read_os_page_fault_count()
	if !ok {
		tester.timing_active = false
		repetition_test_error(tester, "Failed to read OS page fault count")
		return
	}

	tester.current.metrics[.Cycles] += cycle_count - tester.metric_starts[.Cycles]
	tester.current.metrics[.Page_Faults] +=
		page_fault_count - tester.metric_starts[.Page_Faults]
	tester.current.close_block_count += 1
	tester.timing_active = false
}

repetition_test_count_bytes :: proc(tester: ^Repetition_Tester, processed_bytes: u64) {
	if tester.state == .Testing {
		tester.current.processed_bytes += processed_bytes
	}
}

@(private)
repetition_test_commit :: proc(tester: ^Repetition_Tester) -> bool {
	if tester.state != .Testing {
		return false
	}
	if tester.timing_active {
		repetition_test_error(tester, "Timing block was not ended")
		return false
	}

	measurement := tester.current
	if measurement.open_block_count == 0 &&
	   measurement.close_block_count == 0 &&
	   measurement.processed_bytes == 0 {
		return true
	}
	if measurement.open_block_count != measurement.close_block_count {
		repetition_test_error(tester, "Timing block counts do not match")
		return false
	}
	if measurement.close_block_count == 0 {
		repetition_test_error(tester, "No timing block was recorded")
		return false
	}
	if measurement.processed_bytes != tester.target_processed_bytes {
		repetition_test_error(tester, "Processed byte count does not match the target")
		return false
	}

	result := &tester.result
	result.iteration_count += 1
	new_cycle_minimum := false
	for kind in Repetition_Test_Metric_Kind {
		value := measurement.metrics[kind]
		metric := &result.metrics[kind]
		metric.total += value
		if result.iteration_count == 1 || value < metric.minimum {
			metric.minimum = value
			if kind == .Cycles {
				new_cycle_minimum = true
			}
		}
		if result.iteration_count == 1 || value > metric.maximum {
			metric.maximum = value
		}
	}
	if new_cycle_minimum {
		tester.last_minimum_at = read_cpu_timer()
	}
	tester.current = {}
	return true
}

// Usage:
//
// repetition_test_start(&tester, byte_count, estimate_cpu_timer_frequency())
// for repetition_test_is_testing(&tester) {
//     repetition_test_begin_time(&tester)
//     // Code under test.
//     repetition_test_end_time(&tester)
//     repetition_test_count_bytes(&tester, byte_count)
// }
repetition_test_is_testing :: proc(tester: ^Repetition_Tester) -> bool {
	if !repetition_test_commit(tester) {
		return false
	}
	if tester.result.iteration_count > 0 &&
	   read_cpu_timer() - tester.last_minimum_at >= tester.try_for_cycles {
		tester.state = .Completed
		return false
	}
	return true
}

@(private)
print_repetition_measurement :: proc(
	label: string,
	cycles: u64,
	page_fault_count: u64,
	processed_bytes: u64,
	cpu_timer_frequency: u64,
) {
	seconds := f64(cycles) / f64(cpu_timer_frequency)
	gigabytes_per_second: f64
	if seconds > 0 {
		gigabytes_per_second = f64(processed_bytes) / seconds / 1_000_000_000
	}
	fmt.printfln(
		"  %s: %d cycles, %.4f ms, %.4f GB/s, %d page faults",
		label,
		cycles,
		seconds * 1_000,
		gigabytes_per_second,
		page_fault_count,
	)
}

print_repetition_test_result :: proc(tester: ^Repetition_Tester) {
	if tester.state == .Error {
		fmt.eprintfln("Repetition test error: %s", tester.error_message)
		return
	}
	if tester.result.iteration_count == 0 {
		fmt.println("Repetition test has no results")
		return
	}

	fmt.printfln(
		"Repetition test: %d iterations of %d bytes",
		tester.result.iteration_count,
		tester.target_processed_bytes,
	)
	cycles := tester.result.metrics[.Cycles]
	page_faults := tester.result.metrics[.Page_Faults]
	print_repetition_measurement(
		"Minimum",
		cycles.minimum,
		page_faults.minimum,
		tester.target_processed_bytes,
		tester.cpu_timer_frequency,
	)
	print_repetition_measurement(
		"Average",
		cycles.total / tester.result.iteration_count,
		page_faults.total / tester.result.iteration_count,
		tester.target_processed_bytes,
		tester.cpu_timer_frequency,
	)
	print_repetition_measurement(
		"Maximum",
		cycles.maximum,
		page_faults.maximum,
		tester.target_processed_bytes,
		tester.cpu_timer_frequency,
	)
}
