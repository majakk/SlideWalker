extends Node2D
## Procedural xkcd-style stick figure: hollow round head, single-stroke
## torso, two-segment arms and legs with elbow/knee joints. The pose is
## computed from the player's motion every frame instead of baked frames,
## so the walk cycle's stride always matches actual ground speed and the
## planted foot never slides.
##
## Angles are measured from straight down; positive swings toward the
## facing direction.

const LINE_COLOR := Color(0.08, 0.08, 0.08)
const LINE_WIDTH := 2.5

const HEAD_RADIUS := 7.0
const TORSO := 16.0
const SHOULDER_DROP := 3.0
const THIGH := 9.0
const SHIN := 9.0
const UPPER_ARM := 7.5
const FOREARM := 7.0
## Hip height above the feet when standing straight (collision capsule
## bottom is at y=+24).
const FEET_Y := 24.0
const HIP_Y := FEET_Y - THIGH - SHIN

const LEG_SWING := 0.6
const ARM_SWING := 0.55
const AIR_BLEND_RATE := 12.0
## Double jump: a quick tucked forward flip.
const FLIP_TIME := 0.38
## Torso lean into the direction of travel at full speed (radians).
const RUN_LEAN := 0.16
const LEAN_RATE := 8.0
const SKID_BLEND_RATE := 14.0
const WAVE_TIME := 1.5

var _velocity := Vector2.ZERO
var _on_floor := true
var _facing := 1
var _phase := 0.0
var _time := 0.0
var _air := 0.0
## 1 -> 0 over one flip; 0 when not flipping.
var _flip := 0.0
var _lean := 0.0
var _skidding := false
var _skid := 0.0
## 1 -> 0 over one wave; 0 when not waving.
var _wave := 0.0

func set_motion(velocity: Vector2, on_floor: bool, facing: int, skidding: bool = false) -> void:
	_velocity = velocity
	_on_floor = on_floor
	_facing = facing
	_skidding = skidding

func play_wave() -> void:
	_wave = 1.0

func play_air_jump() -> void:
	_flip = 1.0

func _process(delta: float) -> void:
	_time += delta
	_flip = move_toward(_flip, 0.0, delta / FLIP_TIME)
	_wave = move_toward(_wave, 0.0, delta / WAVE_TIME)
	var run_amount: float = clamp(abs(_velocity.x) / JumpPhysics.profile.run_speed, 0.0, 1.0)
	_lean = lerp(_lean, RUN_LEAN * run_amount if _on_floor else 0.0, 1.0 - exp(-LEAN_RATE * delta))
	_skid = lerp(_skid, 1.0 if (_skidding and _on_floor) else 0.0, 1.0 - exp(-SKID_BLEND_RATE * delta))
	var speed: float = abs(_velocity.x)
	if _on_floor:
		# Advance the gait so one half-cycle covers exactly one stride.
		var stride: float = 2.0 * (THIGH + SHIN) * sin(LEG_SWING)
		_phase = fmod(_phase + delta * PI * speed / stride, TAU)
	_air = lerp(_air, 0.0 if _on_floor else 1.0, 1.0 - exp(-AIR_BLEND_RATE * delta))
	queue_redraw()

func _ground_pose() -> Dictionary:
	var amount: float = clamp(abs(_velocity.x) / JumpPhysics.profile.run_speed, 0.0, 1.0)
	var idle: float = 1.0 - amount
	var s: float = sin(_phase)
	var c: float = cos(_phase)
	var breathe: float = sin(_time * 2.2) * 0.04 * idle

	var pose := {}
	pose.thigh_l = s * LEG_SWING * amount + 0.1 * idle
	pose.thigh_r = -s * LEG_SWING * amount - 0.1 * idle
	# A knee bends while its leg swings forward (the lifted leg).
	pose.shin_l = pose.thigh_l - (max(0.0, c) * 1.1 * amount + 0.05)
	pose.shin_r = pose.thigh_r - (max(0.0, -c) * 1.1 * amount + 0.05)
	pose.arm_l = -s * ARM_SWING * amount + 0.15 * idle + breathe
	pose.arm_r = s * ARM_SWING * amount - 0.15 * idle - breathe
	pose.fore_l = pose.arm_l + 0.3 + 0.5 * amount
	pose.fore_r = pose.arm_r + 0.3 + 0.5 * amount
	pose.lean = _lean

	# Drop the hip so the lowest foot stays exactly on the ground.
	var foot_l: float = THIGH * cos(pose.thigh_l) + SHIN * cos(pose.shin_l)
	var foot_r: float = THIGH * cos(pose.thigh_r) + SHIN * cos(pose.shin_r)
	pose.bob = (THIGH + SHIN) - max(foot_l, foot_r) + breathe * 4.0
	return pose

func _air_pose() -> Dictionary:
	# 0 = rising, 1 = falling.
	var fall: float = clamp(_velocity.y / 800.0 + 0.5, 0.0, 1.0)
	var flail: float = sin(_time * 18.0) * 0.25 * fall

	var pose := {}
	pose.thigh_l = lerp(1.0, 0.35, fall)
	pose.shin_l = lerp(0.1, 0.0, fall)
	pose.thigh_r = lerp(-0.2, -0.25, fall)
	pose.shin_r = lerp(-0.7, -0.5, fall)
	pose.arm_l = lerp(2.6, 2.3, fall) + flail
	pose.arm_r = lerp(2.2, 2.0, fall) - flail
	pose.fore_l = pose.arm_l + 0.35
	pose.fore_r = pose.arm_r + 0.35
	pose.lean = lerp(0.1, -0.05, fall)
	pose.bob = -2.0
	return pose

## Braking hard after a sudden turn: body already facing the new way and
## leaning into it, front leg braced out, arms thrown back for balance.
func _skid_pose() -> Dictionary:
	var pose := {
		"thigh_l": 0.55, "shin_l": 0.95, "thigh_r": -0.35, "shin_r": -0.15,
		"arm_l": -1.1, "fore_l": -0.7, "arm_r": -0.8, "fore_r": -0.4,
		"lean": 0.32,
	}
	var foot_l: float = THIGH * cos(pose.thigh_l) + SHIN * cos(pose.shin_l)
	var foot_r: float = THIGH * cos(pose.thigh_r) + SHIN * cos(pose.shin_r)
	pose.bob = (THIGH + SHIN) - max(foot_l, foot_r)
	return pose

func _tuck_pose() -> Dictionary:
	return {
		"thigh_l": 1.9, "shin_l": -0.3, "thigh_r": 1.6, "shin_r": -0.5,
		"arm_l": 1.4, "fore_l": 2.4, "arm_r": 1.1, "fore_r": 2.2,
		"lean": 0.25, "bob": -6.0,
	}

func _dir(angle: float) -> Vector2:
	return Vector2(sin(angle) * _facing, cos(angle))

func _draw() -> void:
	var ground: Dictionary = _ground_pose()
	var air: Dictionary = _air_pose()
	var skid: Dictionary = _skid_pose()
	var tuck: Dictionary = _tuck_pose()
	# Tucked for most of the flip, unfolding over its last stretch.
	var tuck_amount: float = clamp(_flip * 3.0, 0.0, 1.0)
	var pose := {}
	for key in ground:
		var p: float = lerp(float(ground[key]), float(air[key]), _air)
		p = lerp(p, float(skid[key]), _skid)
		pose[key] = lerp(p, float(tuck[key]), tuck_amount)

	# Wave: raise the front arm and swing the forearm, easing in and out.
	if _wave > 0.0:
		var elapsed: float = (1.0 - _wave) * WAVE_TIME
		var amount: float = clamp(elapsed / 0.18, 0.0, 1.0) * clamp(_wave * WAVE_TIME / 0.25, 0.0, 1.0)
		# Upper arm out to the front, forearm up and swinging - clear of the head.
		pose.arm_l = lerp(float(pose.arm_l), 1.85, amount)
		pose.fore_l = lerp(float(pose.fore_l), PI - 0.3 + sin(elapsed * 13.0) * 0.45, amount)

	# Rotate the whole figure around its middle, forward in the facing direction.
	draw_set_transform(Vector2.ZERO, TAU * (1.0 - _flip) * _facing if _flip > 0.0 else 0.0, Vector2.ONE)

	var up := Vector2(sin(pose.lean) * _facing, -cos(pose.lean))
	var hip := Vector2(0.0, HIP_Y + pose.bob)
	var neck: Vector2 = hip + up * TORSO
	var shoulder: Vector2 = neck - up * SHOULDER_DROP
	var head: Vector2 = neck + up * HEAD_RADIUS

	_limb(hip, pose.thigh_r, THIGH, pose.shin_r, SHIN)
	_limb(shoulder, pose.arm_r, UPPER_ARM, pose.fore_r, FOREARM)
	_stroke(PackedVector2Array([hip, neck]))
	_limb(hip, pose.thigh_l, THIGH, pose.shin_l, SHIN)
	_limb(shoulder, pose.arm_l, UPPER_ARM, pose.fore_l, FOREARM)
	draw_arc(head, HEAD_RADIUS, 0.0, TAU, 40, LINE_COLOR, LINE_WIDTH, true)

func _limb(root: Vector2, upper_angle: float, upper_len: float, lower_angle: float, lower_len: float) -> void:
	var joint: Vector2 = root + _dir(upper_angle) * upper_len
	var tip: Vector2 = joint + _dir(lower_angle) * lower_len
	_stroke(PackedVector2Array([root, joint, tip]))

## Polyline with round caps and joints, for the pen-drawn xkcd look.
func _stroke(points: PackedVector2Array) -> void:
	draw_polyline(points, LINE_COLOR, LINE_WIDTH, true)
	for p in points:
		draw_circle(p, LINE_WIDTH * 0.5, LINE_COLOR, true, -1.0, true)
