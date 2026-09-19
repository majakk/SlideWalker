extends Node
## Carries choices made in the startup menu (ui/main_menu.tscn) through to
## the course scene.

enum PlayerStyle { PIXEL_ART, STICK_FIGURE }
## PER_SLIDE: the camera frames one slide at a time and pans across at slide
## boundaries (like slide transitions). SEAMLESS: it follows the player
## continuously along the course.
enum CameraMode { PER_SLIDE, SEAMLESS }
## Same order as CourseGenerator.Mode.
enum CourseLayout { SIDE_SCROLL, CLIMB, DROP, SPIRAL }

var player_style: PlayerStyle = PlayerStyle.STICK_FIGURE
var camera_mode: CameraMode = CameraMode.PER_SLIDE
var course_layout: CourseLayout = CourseLayout.SIDE_SCROLL
## Presentation picked in the menu; empty = cycle the dev decks in
## res://presentations_testing.
var deck_path: String = ""
## Elapsed-time clock in the corner of the screen.
var show_timer: bool = false

## The presentation currently running (paused behind the menu overlay):
## the menu offers "Resume" unless the file or course type changed since.
var session_active: bool = false
var session_deck_path: String = ""
var session_layout: CourseLayout = CourseLayout.SIDE_SCROLL

func session_matches_choices() -> bool:
	return session_active and deck_path == session_deck_path and course_layout == session_layout
