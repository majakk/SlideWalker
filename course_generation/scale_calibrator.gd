extends RefCounted
class_name ScaleCalibrator
## Picks one deck-wide world-units-per-cm scale so slide content maps onto
## jump-friendly platform spacing, without ever moving shapes relative to
## each other (a uniform scale preserves all relative geometry). Per the
## M2 plan scope, this is deck-wide only - no per-slide bounded local
## adjustment yet (that lands when coverage-driven refinement is built).

const PlatformCandidateBuilder = preload("res://course_generation/platform_candidate_builder.gd")
## Preloaded (rather than referenced as the bare autoload name) so this
## static utility resolves identically whether it runs inside the full
## game, a headless `-s` test script, or a future unit-test harness.
const JumpPhysics = preload("res://autoload/JumpPhysics.gd")

const DEFAULT_SCALE_PX_PER_CM: float = 40.0
const MIN_SCALE_PX_PER_CM: float = 12.0
const MAX_SCALE_PX_PER_CM: float = 70.0
## Fraction of the player's max jump apex a "typical" (75th percentile)
## content gap should occupy once scaled - leaves headroom rather than
## sizing exactly to the limit.
const TARGET_APEX_FRACTION: float = 0.6
const TARGET_PERCENTILE: float = 0.75

## per_slide_candidates: Array[Array[PlatformCandidateBuilder.Candidate]]
static func calibrate(per_slide_candidates: Array) -> float:
	var gaps: Array[float] = []
	for slide_candidates in per_slide_candidates:
		var tops: Array[float] = []
		for c in slide_candidates:
			tops.append((c as PlatformCandidateBuilder.Candidate).top_cm)
		tops.sort()
		for i in range(1, tops.size()):
			var gap: float = tops[i] - tops[i - 1]
			if gap > 0.01:
				gaps.append(gap)

	if gaps.is_empty():
		return DEFAULT_SCALE_PX_PER_CM

	gaps.sort()
	var idx: int = int(clamp(round(TARGET_PERCENTILE * (gaps.size() - 1)), 0, gaps.size() - 1))
	var gap_cm: float = gaps[idx]
	if gap_cm <= 0.0:
		return DEFAULT_SCALE_PX_PER_CM

	var apex_px: float = JumpPhysics.max_up_dy(0.0)
	var target_px: float = apex_px * TARGET_APEX_FRACTION
	var scale: float = target_px / gap_cm
	return clamp(scale, MIN_SCALE_PX_PER_CM, MAX_SCALE_PX_PER_CM)
