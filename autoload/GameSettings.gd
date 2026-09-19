extends Node
## Carries choices made in the startup menu (ui/main_menu.tscn) through to
## the course scene.

enum PlayerStyle { PIXEL_ART, STICK_FIGURE }
## PER_SLIDE: the camera frames one slide at a time and pans across at slide
## boundaries (like slide transitions). SEAMLESS: it follows the player
## continuously along the course.
enum CameraMode { PER_SLIDE, SEAMLESS }
## Same order as CourseGenerator.Mode.
enum CourseLayout { SIDE_SCROLL, CLIMB, DROP }

var player_style: PlayerStyle = PlayerStyle.STICK_FIGURE
var camera_mode: CameraMode = CameraMode.PER_SLIDE
var course_layout: CourseLayout = CourseLayout.SIDE_SCROLL
## Presentation picked in the menu; empty = cycle the dev decks in
## res://presentations_testing.
var deck_path: String = ""
