package profiling

import "base:intrinsics"
import "core:fmt"
import "core:time"

#assert(
	ODIN_OS == .Linux || (ODIN_OS == .Darwin && ODIN_ARCH == .arm64),
	"profiling supports Linux and Apple Silicon macOS",
)

// read_cpu_timer returns the platform's CPU timestamp counter. LLVM lowers
// this to RDTSC on x86 and the architectural virtual counter on Apple Silicon.
@(require_results)
read_cpu_timer :: #force_inline proc "contextless" () -> u64 {
	return u64(intrinsics.read_cycle_counter())
}

profile_block_end :: proc(label: string, start: u64) {
	elapsed := read_cpu_timer() - start
	fmt.printfln("%s: %d cycles", label, elapsed)
}

// Usage:
// {
//     profile_block("Parse")
//     // Code to profile.
// }
@(deferred_in_out=profile_block_end)
profile_block :: #force_inline proc(label: string) -> u64 {
	return read_cpu_timer()
}

get_os_timer_frequency :: proc "contextless" () -> u64 {
	return 1_000_000_000
}

@(require_results)
read_os_timer :: proc "contextless" () -> u64 {
	return u64(time.to_unix_nanoseconds(time.now()))
}

@(require_results)
estimate_cpu_timer_frequency :: proc "contextless" () -> u64 {
	milliseconds_to_wait := u64(100)
	os_frequency := get_os_timer_frequency()

	cpu_start := read_cpu_timer()
	os_start := read_os_timer()
	os_end: u64
	os_elapsed: u64
	os_wait_time := os_frequency * milliseconds_to_wait / 1_000
	for os_elapsed < os_wait_time {
		os_end = read_os_timer()
		os_elapsed = os_end - os_start
	}

	cpu_end := read_cpu_timer()
	cpu_elapsed := cpu_end - cpu_start
	if os_elapsed == 0 {
		return 0
	}
	return os_frequency * cpu_elapsed / os_elapsed
}
