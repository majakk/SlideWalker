extends RefCounted
## Shared low-level helpers so pptx_parser.gd and odp_parser.gd work against
## ordinary recursive tree structures instead of raw XMLParser streaming
## state. Both .pptx and .odp are zip archives of XML, so this is the one
## piece of plumbing both formats share.

## Parses an XML byte buffer into a plain tree: {tag, attrs, children, text}.
## Godot's XMLParser is a streaming/pull parser (not a DOM), so this walks
## it once and materializes an ordinary tree callers can recurse over.
static func parse_xml_tree(bytes: PackedByteArray) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(bytes) != OK:
		return {}

	var root: Dictionary = {}
	var stack: Array[Dictionary] = []

	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var attrs: Dictionary = {}
				for i in range(parser.get_attribute_count()):
					attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				var node: Dictionary = {
					"tag": parser.get_node_name(),
					"attrs": attrs,
					"children": [],
					"text": "",
				}
				if stack.is_empty():
					root = node
				else:
					(stack[-1]["children"] as Array).append(node)
				# Self-closed elements (<a:off/>) never get a matching
				# NODE_ELEMENT_END, so only push non-empty elements.
				if not parser.is_empty():
					stack.push_back(node)
			XMLParser.NODE_ELEMENT_END:
				if not stack.is_empty():
					stack.pop_back()
			XMLParser.NODE_TEXT:
				if not stack.is_empty():
					stack[-1]["text"] += parser.get_node_data()

	return root

## Depth-first search for the first descendant (or self) with the given tag.
static func find_first(node: Dictionary, tag: String) -> Dictionary:
	if node.is_empty():
		return {}
	if node.get("tag", "") == tag:
		return node
	for child in node.get("children", []):
		var found: Dictionary = find_first(child, tag)
		if not found.is_empty():
			return found
	return {}

## Depth-first collection of all descendants (or self) with the given tag,
## stopping recursion into a subtree once it matches (siblings/cousins at
## deeper nesting are still visited independently).
static func find_all(node: Dictionary, tag: String, out: Array = []) -> Array:
	if node.is_empty():
		return out
	if node.get("tag", "") == tag:
		out.append(node)
		return out
	for child in node.get("children", []):
		find_all(child, tag, out)
	return out

## Direct children only (not deep) with the given tag.
static func direct_children(node: Dictionary, tag: String) -> Array:
	var out: Array = []
	for child in node.get("children", []):
		if child.get("tag", "") == tag:
			out.append(child)
	return out

static func open_zip_entry_tree(zip: ZIPReader, path: String) -> Dictionary:
	if not zip.file_exists(path):
		return {}
	return parse_xml_tree(zip.read_file(path))
