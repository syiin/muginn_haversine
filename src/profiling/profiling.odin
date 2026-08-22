package profiling

import "base:intrinsics"
import "core:fmt"
import "core:time"

#assert(
	ODIN_OS == .Linux || (ODIN_OS == .Darwin && ODIN_ARCH == .arm64),
	"profiling supports Linux and Apple Silicon macOS",
)

MAX_PROFILE_COUNT :: 64

Profile :: struct {
	label:           string,
	elapsed_cycles:  u64, // Inclusive; nested invocations of the same label count once.
	self_cycles:     u64,
	hit_count:       u64, // Includes nested invocations of the same label.
	outermost_count: u64,
}

Active_Block :: struct {
	label:        string,
	child_cycles: u64,
	is_outermost: bool,
}

Profiler :: struct {
	profiles:      [dynamic; MAX_PROFILE_COUNT]Profile,
	active_blocks: [dynamic; MAX_PROFILE_COUNT]Active_Block,
}

@(private)
global_profiler: Profiler

// read_cpu_timer returns the platform's CPU timestamp counter. LLVM lowers
// this to RDTSC on x86 and the architectural virtual counter on Apple Silicon.
@(require_results)
read_cpu_timer :: #force_inline proc "contextless" () -> u64 {
	return u64(intrinsics.read_cycle_counter())
}

@(private)
find_or_add_profile :: proc(label: string) -> ^Profile {
	for &profile in global_profiler.profiles {
		if profile.label == label {
			return &profile
		}
	}

	assert(len(global_profiler.profiles) < cap(global_profiler.profiles))
	append(&global_profiler.profiles, Profile{label = label})
	return &global_profiler.profiles[len(global_profiler.profiles) - 1]
}

profile_block_end :: proc(label: string, start: u64) {
	elapsed := read_cpu_timer() - start
	assert(len(global_profiler.active_blocks) > 0)
	active_block := pop(&global_profiler.active_blocks)

	profile := find_or_add_profile(label)
	if active_block.is_outermost {
		profile.elapsed_cycles += elapsed
		profile.outermost_count += 1
	}
	profile.self_cycles += elapsed - active_block.child_cycles
	profile.hit_count += 1

	if len(global_profiler.active_blocks) > 0 {
		parent := &global_profiler.active_blocks[len(global_profiler.active_blocks) - 1]
		parent.child_cycles += elapsed
	}
}

// Usage:
// {
//     profile_block("Parse")
//     // Code to profile.
// }
@(deferred_in_out=profile_block_end)
profile_block :: #force_inline proc(label: string) -> u64 {
	assert(len(global_profiler.active_blocks) < cap(global_profiler.active_blocks))
	is_outermost := true
	for active_block in global_profiler.active_blocks {
		if active_block.label == label {
			is_outermost = false
			break
		}
	}
	append(
		&global_profiler.active_blocks,
		Active_Block{label = label, is_outermost = is_outermost},
	)
	return read_cpu_timer()
}

print_report :: proc() {
	for profile in global_profiler.profiles {
		fmt.printfln(
			"%s: %d inclusive cycles, %d self cycles, %d hits, %d outermost hits",
			profile.label,
			profile.elapsed_cycles,
			profile.self_cycles,
			profile.hit_count,
			profile.outermost_count,
		)
	}
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
