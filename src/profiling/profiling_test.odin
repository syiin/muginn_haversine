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
