extends RefCounted
## Picks the parser for a presentation file by extension. Every parser
## produces the same PresentationModel.SlideDeck, so course_generation/ and
## world/ never know which format was loaded.

const PptxParser = preload("res://presentation_import/pptx_parser.gd")
const OdpParser = preload("res://presentation_import/odp_parser.gd")
const PdfParser = preload("res://presentation_import/pdf_parser.gd")
const PresentationModel = preload("res://presentation_import/presentation_model.gd")

const SUPPORTED_EXTENSIONS := ["pptx", "odp", "pdf"]

static func parse(path: String) -> PresentationModel.SlideDeck:
	match path.get_extension().to_lower():
		"odp":
			return OdpParser.parse(path)
		"pdf":
			return PdfParser.parse(path)
		"pptx":
			return PptxParser.parse(path)
	push_warning("PresentationParser: unsupported file type %s" % path.get_file())
	var empty := PresentationModel.SlideDeck.new()
	empty.source_path = path
	return empty

static func is_supported(path: String) -> bool:
	return SUPPORTED_EXTENSIONS.has(path.get_extension().to_lower())

## True when the deck's images are plain files on disk (pdf page rasters)
## rather than entries inside the presentation's own zip archive.
static func uses_filesystem_images(path: String) -> bool:
	return path.get_extension().to_lower() == "pdf"

## Why this file can't be opened, or "" when it can. Only pdf has a way to
## fail before parsing: it's the one format that needs an external tool.
static func unmet_requirement(path: String) -> String:
	if path.get_extension().to_lower() == "pdf" and PdfParser.poppler_missing():
		return PdfParser.MISSING_POPPLER_MESSAGE
	return ""
