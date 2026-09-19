extends RefCounted
class_name JumpCalibrator
## The platformer adapts to the deck: slides are shown at presentation size,
## so the jump is tuned to the deck's content instead of shrinking slides.
## Picks the smallest apex that still reaches every ledge reachable at the
## maximum apex, plus headroom so jumps aren't frame-perfect.

const CourseModel = preload("res://course_generation/course_model.gd")
const Reachability = preload("res://course_generation/reachability.gd")
const JumpProfile = preload("res://player/jump_profile.gd")

## Sane apex range in body heights. Ledges still out of reach at the max are
## where the reserve lever (a double jump, see plan) would come in.
const MIN_APEX_BODIES: float = 2.5
const MAX_APEX_BODIES: float = 7.5
const HEADROOM: float = 1.12
const BASE_APEX: float = 137.3
const BASE_TIME_TO_APEX: float = 0.443
const RUN_SPEED: float = 340.0
const SEARCH_STEPS: int = 14

static func calibrate(layout: CourseModel.Layout) -> JumpProfile:
	var body: float = JumpProfile.BODY_HEIGHT
	var lo: float = MIN_APEX_BODIES * body
	var hi: float = MAX_APEX_BODIES * body
	var best_coverage: int = Reachability.ledge_coverage(layout.platforms, make_profile(hi))

	for _i in range(SEARCH_STEPS):
		var mid: float = (lo + hi) * 0.5
		if Reachability.ledge_coverage(layout.platforms, make_profile(mid)) >= best_coverage:
			hi = mid
		else:
			lo = mid

	var ledges: int = layout.platforms.size() - 1
	if best_coverage < ledges:
		print("JumpCalibrator: %d/%d ledges unreachable even at max apex - double jump would help" % [
			ledges - best_coverage, ledges])
	return make_profile(min(hi * HEADROOM, MAX_APEX_BODIES * body))

static func make_profile(apex: float) -> JumpProfile:
	var profile := JumpProfile.new()
	profile.run_speed = RUN_SPEED
	profile.apex_height = apex
	# Higher jumps take a little longer so they still read as jumps, not launches.
	profile.time_to_apex = BASE_TIME_TO_APEX * pow(apex / BASE_APEX, 0.3)
	profile.max_fall_speed = abs(profile.jump_velocity) * 1.4
	return profile
