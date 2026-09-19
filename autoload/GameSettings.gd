extends Node
## Carries choices made in the startup menu (ui/main_menu.tscn) through to
## the game scene. Grows to hold course-layout mode and the adaptive-zoom
## toggle once those UI pieces land (plan milestones M8/M9).

enum PlayerStyle { PIXEL_ART, STICK_FIGURE }
## PER_SLIDE: the camera frames one slide at a time and pans across at slide
## boundaries (like slide transitions). SEAMLESS: it follows the player
## continuously along the course.
enum CameraMode { PER_SLIDE, SEAMLESS }

var player_style: PlayerStyle = PlayerStyle.STICK_FIGURE
var camera_mode: CameraMode = CameraMode.PER_SLIDE
