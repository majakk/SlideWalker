extends RefCounted
## Recognizes links to the video platforms decks actually use, so a slide's
## video still (often just a screenshot with the clip linked behind it) can
## announce itself as a video rather than as a generic link.
##
## Playing the clip inside the slide's own frame would need a browser engine
## in-process (no Godot build plays YouTube/Vimeo streams natively), so for
## now interacting opens it in the system browser and the prompt says so.

const YOUTUBE_HOSTS := ["youtube.com", "youtu.be", "youtube-nocookie.com"]
const VIMEO_HOSTS := ["vimeo.com"]
## PeerTube is federated across independent hosts, so it's recognized by the
## URL shape its instances share instead of by a host list.
const PEERTUBE_PATHS := ["/w/", "/videos/watch/", "/videos/embed/"]

## "YouTube", "Vimeo", "PeerTube", or "" when this isn't a video link.
static func platform_of(url: String) -> String:
	var lower: String = url.to_lower()
	var host: String = _host(lower)
	for youtube in YOUTUBE_HOSTS:
		if host == youtube or host.ends_with("." + youtube):
			return "YouTube"
	for vimeo in VIMEO_HOSTS:
		if host == vimeo or host.ends_with("." + vimeo):
			return "Vimeo"
	for path in PEERTUBE_PATHS:
		if lower.contains(path):
			return "PeerTube"
	return ""

static func is_video(url: String) -> bool:
	return platform_of(url) != ""

## What the in-world prompt reads.
static func prompt_for(url: String) -> String:
	var platform: String = platform_of(url)
	if platform != "":
		return "▶  Play %s clip  ·  E  ·  opens in your browser" % platform
	return "Open %s  ·  E  ·  opens in your browser" % _host(url)

static func _host(url: String) -> String:
	var rest: String = url
	for scheme in ["https://", "http://"]:
		rest = rest.trim_prefix(scheme)
	var slash: int = rest.find("/")
	if slash != -1:
		rest = rest.substr(0, slash)
	return rest.trim_prefix("www.").to_lower()
