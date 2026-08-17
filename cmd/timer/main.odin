package main

import "core:fmt"

import "../../src/profiling"

main :: proc() {
	os_frequency := profiling.get_os_timer_frequency()
	fmt.printfln("    OS Freq: %d", os_frequency)
	cpu_frequency := profiling.estimate_cpu_timer_frequency()
	fmt.printfln("   CPU Freq: %d (estimated)", cpu_frequency)

	os_start := profiling.read_os_timer()
	os_end: u64
	os_elapsed: u64
	for os_elapsed < os_frequency {
		os_end = profiling.read_os_timer()
		os_elapsed = os_end - os_start
	}

	fmt.printfln(
		"   OS Timer: %d -> %d = %d elapsed",
		os_start,
		os_end,
		os_elapsed,
	)
	fmt.printfln(" OS Seconds: %.4f", f64(os_elapsed) / f64(os_frequency))
}
