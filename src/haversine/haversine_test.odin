package haversine

import "core:math"
import "core:testing"

@(test)
distance_test :: proc(t: ^testing.T) {
	// London to New York is about 5,570.2 km.
	london_to_new_york := distance(51.5074, -0.1278, 40.7128, -74.0060)
	testing.expect(t, math.abs(london_to_new_york - 5_570.2) < 0.1)

	testing.expect_value(t, distance(51.5074, -0.1278, 51.5074, -0.1278), 0)

	// Antipodal points exercise the upper edge of the haversine calculation.
	antipodal := distance(0, 0, 0, 180)
	testing.expect(t, math.abs(antipodal - math.PI * EARTH_RADIUS_KILOMETERS) < 0.001)
}
