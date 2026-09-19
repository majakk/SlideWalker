extends Node
## Holds the active course's JumpProfile. Course setup replaces it with one
## calibrated to the loaded deck; the default suits hand-built test levels.

const JumpProfile = preload("res://player/jump_profile.gd")

var profile: JumpProfile = JumpProfile.new()
