extends RefCounted
## The platformer adapts to the deck: slides are shown at presentation size,
## so the jump is tuned to the deck's content instead of shrinking slides.
## Picks the smallest apex where (a) the double jump reaches every ledge
## that is reachable at all, (b) a plain single jump still reaches most
## ledges, and (c) a double jump straight up from the floor reaches the
## highest ledge in the deck (the top of the slide, titles included).
## Headroom on top so jumps aren't frame-perfect.

const CourseModel = preload("res://course_generation/course_model.gd")
const Reachability = preload("res://course_generation/reachability.gd")
const JumpProfile = preload("res://player/jump_profile.gd")

const MIN_APEX_BODIES: float = 2.0
const MAX_APEX_BODIES: float = 8.5
## Extra height above the highest ledge the floor double jump must clear,
## so landing on the title isn't a pixel-perfect stretch.
const TOP_REACH_MARGIN_PX: float = 30.0
## Share of reachable ledges a single jump must reach on its own.
const SINGLE_JUMP_SHARE: float = 0.85
const HEADROOM: float = 1.12
const BASE_APEX: float = 137.3
const BASE_TIME_TO_APEX: float = 0.443
const RUN_SPEED: float = 340.0
const SEARCH_STEPS: int = 14

static func calibrate(layout: CourseModel.Layout) -> JumpProfile:
	var body: float = JumpProfile.BODY_HEIGHT
	var lo: float = MIN_APEX_BODIES * body
	var hi: float = MAX_APEX_BODIES * body
	var best: int = Reachability.ledge_coverage(layout.platforms, make_profile(hi))
	var single_target: int = int(ceil(best * SINGLE_JUMP_SHARE))

	for _i in range(SEARCH_STEPS):
		var mid: float = (lo + hi) * 0.5
		var profile: JumpProfile = make_profile(mid)
		var ok: bool = Reachability.ledge_coverage(layout.platforms, profile) >= best \
			and Reachability.ledge_coverage(layout.platforms, profile.with_air_jumps(0)) >= single_target
		if ok:
			hi = mid
		else:
			lo = mid

	var ledges: int = layout.platforms.size() - 1
	if best < ledges:
		print("JumpCalibrator: %d/%d ledges unreachable even with a double jump" % [ledges - best, ledges])

	# Floor double jump reaches the top: apex * (1 + strength^2) >= highest ledge.
	var highest: float = 0.0
	for p in layout.platforms:
		highest = max(highest, -p.y)
	var strength: float = make_profile(lo).air_jump_strength
	var top_apex: float = (highest + TOP_REACH_MARGIN_PX) / (1.0 + strength * strength)

	return make_profile(min(max(hi * HEADROOM, top_apex), MAX_APEX_BODIES * body))

static func make_profile(apex: float) -> JumpProfile:
	var profile := JumpProfile.new()
	profile.run_speed = RUN_SPEED
	profile.apex_height = apex
	# Higher jumps take a little longer so they still read as jumps, not launches.
	profile.time_to_apex = BASE_TIME_TO_APEX * pow(apex / BASE_APEX, 0.3)
	profile.max_fall_speed = abs(profile.jump_velocity) * 1.4
	return profile
