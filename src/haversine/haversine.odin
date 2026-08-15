package haversine

import "core:math"

EARTH_RADIUS_KILOMETERS :: 6_371.0

// distance returns the great-circle distance in kilometers between two
// latitude/longitude points expressed in degrees.
distance :: proc(latitude_1, longitude_1, latitude_2, longitude_2: f64) -> f64 {
	latitude_1_radians := math.to_radians(latitude_1)
	latitude_2_radians := math.to_radians(latitude_2)
	latitude_delta := math.to_radians(latitude_2 - latitude_1)
	longitude_delta := math.to_radians(longitude_2 - longitude_1)

	latitude_sine := math.sin(latitude_delta / 2)
	longitude_sine := math.sin(longitude_delta / 2)
	a := latitude_sine * latitude_sine +
		math.cos(latitude_1_radians) * math.cos(latitude_2_radians) *
		longitude_sine * longitude_sine

	central_angle := 2 * math.asin(math.sqrt(clamp(a, 0, 1)))
	return EARTH_RADIUS_KILOMETERS * central_angle
}
