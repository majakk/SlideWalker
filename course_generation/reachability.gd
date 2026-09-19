extends RefCounted
class_name Reachability
## Jump-chain reachability over a course's platforms: which ledges can be
## reached from the floor by chaining jumps (dropping down is always fine).

const CourseModel = preload("res://course_generation/course_model.gd")

## Indices of platforms reachable from any floor platform.
static func reachable_set(platforms: Array[CourseModel.Platform], profile) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[int] = []
	for i in range(platforms.size()):
		if platforms[i].kind == CourseModel.Platform.Kind.FLOOR:
			visited[i] = true
			queue.append(i)
	while not queue.is_empty():
		var a: CourseModel.Platform = platforms[queue.pop_front()]
		for j in range(platforms.size()):
			if visited.has(j):
				continue
			var b: CourseModel.Platform = platforms[j]
			var dx: float = max(0.0, max(b.x - (a.x + a.width), a.x - (b.x + b.width)))
			if profile.reachable(dx, a.y - b.y):
				visited[j] = true
				queue.append(j)
	return visited

static func ledge_coverage(platforms: Array[CourseModel.Platform], profile) -> int:
	var count: int = 0
	var visited: Dictionary = reachable_set(platforms, profile)
	for i in visited:
		if platforms[i].kind == CourseModel.Platform.Kind.CONTENT:
			count += 1
	return count
