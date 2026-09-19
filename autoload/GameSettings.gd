extends Node
## Carries choices made in the startup menu (ui/main_menu.tscn) through to
## the game scene. Grows to hold course-layout mode and the adaptive-zoom
## toggle once those UI pieces land (plan milestones M8/M9).

enum PlayerStyle { PIXEL_ART, STICK_FIGURE }

var player_style: PlayerStyle = PlayerStyle.STICK_FIGURE
