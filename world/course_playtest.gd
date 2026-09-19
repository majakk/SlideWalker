extends Node2D
## Temporary M2 playtest harness: generates a course from a sample deck and
## drops the player in. Replaced by the real deck-picker flow in M9.

const CourseGenerator = preload("res://course_generation/course_generator.gd")
const CourseModel = preload("res://course_generation/course_model.gd")
const WorldAssembler = preload("res://world/world_assembler.gd")

const DECK_PATH := "res://presentations_testing/F4_ Design Process and Inquiry (part 2).pptx"
## The generated course's floor is at y=0; shift it down so it sits near
## the bottom of the screen like the hand-built test level.
const WORLD_OFFSET := Vector2(0, 650)

@onready var platforms_root: Node2D = $PlatformsRoot
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	var layout: CourseModel.Layout = CourseGenerator.generate_from_pptx(DECK_PATH)
	platforms_root.position = WORLD_OFFSET
	WorldAssembler.assemble(platforms_root, layout)
	player.global_position = WORLD_OFFSET + layout.entry_position
	print("Generated course: %d platforms, world width %.0f px" % [layout.platforms.size(), layout.world_width])
