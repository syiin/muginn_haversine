package profiling

import "core:testing"

@(test)
read_cpu_timer_test :: proc(t: ^testing.T) {
	start := read_cpu_timer()
	end := read_cpu_timer()

	testing.expect(t, start != 0)
	testing.expect(t, end >= start)
}

@(test)
os_timer_test :: proc(t: ^testing.T) {
	testing.expect_value(t, get_os_timer_frequency(), u64(1_000_000_000))
	testing.expect(t, read_os_timer() > 0)
}

@(test)
estimate_cpu_timer_frequency_test :: proc(t: ^testing.T) {
	testing.expect(t, estimate_cpu_timer_frequency() > 0)
}

@(test)
profile_block_test :: proc(t: ^testing.T) {
	clear(&global_profiler.profiles)
	clear(&global_profiler.active_blocks)
	defer {
		clear(&global_profiler.profiles)
		clear(&global_profiler.active_blocks)
	}

	{
		profile_block("Test")
	}
	{
		profile_block("Test")
	}

	testing.expect_value(t, len(global_profiler.profiles), 1)
	testing.expect_value(t, global_profiler.profiles[0].label, "Test")
	testing.expect(t, global_profiler.profiles[0].elapsed_cycles > 0)
	testing.expect_value(
		t,
		global_profiler.profiles[0].self_cycles,
		global_profiler.profiles[0].elapsed_cycles,
	)
	testing.expect_value(t, global_profiler.profiles[0].hit_count, u64(2))

	clear(&global_profiler.profiles)
	{
		profile_block("Parent")
		{
			profile_block("Child")
		}
	}

	testing.expect_value(t, len(global_profiler.active_blocks), 0)
	child := find_or_add_profile("Child")
	parent := find_or_add_profile("Parent")
	testing.expect_value(t, child.self_cycles, child.elapsed_cycles)
	testing.expect_value(
		t,
		parent.self_cycles + child.elapsed_cycles,
		parent.elapsed_cycles,
	)
}
