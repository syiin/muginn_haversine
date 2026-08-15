package fuzzer

import "core:math/rand"

Fuzzer :: struct {
	state:     rand.Xoshiro256_Random_State,
	generator: rand.Generator,
}

// init configures the fuzzer's random generator with a deterministic seed.
init :: proc(fuzzer: ^Fuzzer, seed: u64) {
	fuzzer.generator = rand.xoshiro256_random_generator(&fuzzer.state)
	rand.reset(seed, fuzzer.generator)
}

// random_number returns the next number in the fuzzer's random stream in the
// half-open range [low, high).
@(require_results)
random_number :: proc(
	fuzzer: ^Fuzzer,
	low := f64(0),
	high := f64(1),
) -> f64 {
	return rand.float64_range(low, high, fuzzer.generator)
}
