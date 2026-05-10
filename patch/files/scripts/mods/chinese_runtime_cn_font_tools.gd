extends Reference

const FONT_DATA_PATH = "res://Roundo-Medium.otf"
const DEFAULT_SIZE = 18

var font_data = null
var font_cache = {}

func _init():
	# Roundo-Medium.otf 已由 mod 覆盖为中文字体；这里复用它生成运行时字体。
	if ResourceLoader.exists(FONT_DATA_PATH):
		font_data = load(FONT_DATA_PATH)

func apply_to(node):
	if font_data == null || node == null || !(node is Control):
		return
	if node.has_meta("cnui_font_checked"):
		return
	node.set_meta("cnui_font_checked", true)

	# 只替换 BitmapFont。DynamicFont 会自然吃到被 mod 覆盖后的字体文件。
	if node is RichTextLabel:
		for slot in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			_replace_bitmap_font(node, slot)
	else:
		_replace_bitmap_font(node, "font")
		if node is Tree:
			_replace_bitmap_font(node, "title_button_font")

func _replace_bitmap_font(node, slot):
	var current_font = node.get_font(slot)
	if current_font == null || !(current_font is BitmapFont):
		return

	var size = _font_size(current_font)
	node.add_font_override(slot, _font_for_size(size))

func _font_size(source_font):
	var size = DEFAULT_SIZE
	if source_font != null:
		size = int(source_font.get_height())
	if size < 10:
		size = DEFAULT_SIZE
	if size > 64:
		size = 64
	return size

func _font_for_size(size):
	if font_cache.has(size):
		return font_cache[size]

	var font = DynamicFont.new()
	font.size = size
	font.use_filter = true
	font.font_data = font_data
	font_cache[size] = font
	return font
