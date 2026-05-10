extends Node

# 轮询可见 UI；用节点 meta 记录 source/translated/pending/retry_at，避免重复请求。
var translator = null
var scan_interval = 0.45
var scan_clock = 0.0
var font_tools = load("res://files/scripts/mods/chinese_runtime_cn_font_tools.gd").new()
var text_tools = load("res://files/scripts/mods/chinese_runtime_cn_text_tools.gd").new()

func setup(translator_ref):
	translator = translator_ref

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)

func scan_now():
	if translator == null || !translator.is_ready() || !is_inside_tree():
		return
	scan_clock = 0.0
	_scan_node(get_tree().get_root())

func clear_state():
	# DeepSeek 设置变化后清掉节点状态，让失败/未翻译文本能重新入队。
	if !is_inside_tree():
		return
	_clear_node_state(get_tree().get_root())

func _process(delta):
	if translator == null || !translator.is_ready():
		return

	scan_clock += delta
	if scan_clock < scan_interval:
		return
	scan_clock = 0.0
	_scan_node(get_tree().get_root())

func _scan_node(node):
	if node == null:
		return
	if node.get_name() == "ChineseRuntimeCN":
		return
	if node.has_meta("cnui_skip") && node.get_meta("cnui_skip"):
		return
	if node is Control && !node.is_visible_in_tree():
		return

	if node is MenuButton:
		_prepare_text_node(node)
		_scan_string_property(node, "text")
		var popup = node.get_popup()
		if popup != null:
			_prepare_text_node(popup)
			_scan_indexed_texts(popup, "items", "get_item_count", "get_item_text", "set_item_text")
	elif node is OptionButton:
		_prepare_text_node(node)
		_scan_indexed_texts(node, "items", "get_item_count", "get_item_text", "set_item_text")
	elif node is PopupMenu:
		_prepare_text_node(node)
		_scan_indexed_texts(node, "items", "get_item_count", "get_item_text", "set_item_text")
	elif node is ItemList:
		_prepare_text_node(node)
		_scan_indexed_texts(node, "items", "get_item_count", "get_item_text", "set_item_text")
	elif node is TabContainer:
		_prepare_text_node(node)
		_scan_indexed_texts(node, "tabs", "get_tab_count", "get_tab_title", "set_tab_title")
	elif node is RichTextLabel:
		_prepare_text_node(node)
		_scan_string_property(node, "bbcode_text", true)
	elif node is Label || node is BaseButton:
		_prepare_text_node(node)
		_scan_string_property(node, "text")

	if node is LineEdit:
		_prepare_text_node(node)
		_scan_string_property(node, "placeholder_text")

	_scan_string_property(node, "hint_tooltip")
	_scan_string_property(node, "window_title")
	_scan_string_property(node, "dialog_text")

	for child in node.get_children():
		_scan_node(child)

func _prepare_text_node(node):
	# 字体检查只做一次，用来兜住 mainfont.font 这类不含中文字形的 BitmapFont。
	if font_tools != null:
		font_tools.apply_to(node)

func _scan_string_property(node, prop, bbcode = false):
	var value = node.get(prop)
	if typeof(value) != TYPE_STRING || value == "":
		return

	if !_needs_translation(value):
		_mark_translated(node, prop, value)
		return

	var state = _get_state(node)
	if !state.has(prop):
		state[prop] = {}

	var entry = state[prop]
	if _entry_is_translated(entry, value):
		return
	if entry.has("source") && entry.source == value:
		if entry.get("pending", false):
			return
		if _entry_has_translation(entry, value):
			node.set(prop, entry.translated)
			return
		if _entry_is_locked(entry, value):
			return

	entry.source = value
	entry.pending = true
	entry.erase("translated")
	entry.erase("done")
	entry.erase("retry_at")
	state[prop] = entry
	node.set_meta("cnui_state", state)

	if bbcode:
		translator.translate_bbcode(value, self, "_on_string_ready", {node = node, prop = prop, source = value})
	else:
		translator.translate_plain(value, self, "_on_string_ready", {node = node, prop = prop, source = value})

func _scan_indexed_texts(node, state_key, count_name, getter_name, setter_name):
	var count = int(node.call(count_name))
	var state = _get_state(node)
	if !state.has(state_key):
		state[state_key] = {}

	var bucket = state[state_key]
	var touched = false
	for idx in range(count):
		var value = str(node.call(getter_name, idx))
		if value == "":
			continue

		var item_key = str(idx)
		if !_needs_translation(value):
			bucket[item_key] = {source = value, translated = value, pending = false, done = true}
			touched = true
			continue

		if bucket.has(item_key):
			var entry = bucket[item_key]
			if _entry_is_translated(entry, value):
				continue
			if entry.has("source") && entry.source == value:
				if entry.get("pending", false):
					continue
				if _entry_has_translation(entry, value):
					node.call(setter_name, idx, entry.translated)
					continue
				if _entry_is_locked(entry, value):
					continue

		bucket[item_key] = {source = value, pending = true}
		touched = true
		translator.translate_plain(value, self, "_on_indexed_ready", {
			node = node,
			state_key = state_key,
			setter = setter_name,
			index = idx,
			source = value
		})

	if touched:
		state[state_key] = bucket
		node.set_meta("cnui_state", state)

func _on_string_ready(source, translated, token):
	var node = token.node
	if node == null || !is_instance_valid(node):
		return

	var state = _get_state(node)
	if !state.has(token.prop):
		return

	var entry = state[token.prop]
	if !entry.has("source") || entry.source != token.source:
		return

	if translated == source:
		# 原文原样返回时，当作暂时失败，留给后续轮询或下次状态变化重试。
		_mark_retry(entry, source)
		state[token.prop] = entry
		node.set_meta("cnui_state", state)
		return

	entry.translated = translated
	entry.pending = false
	entry.done = true
	entry.erase("retry_at")
	state[token.prop] = entry
	node.set_meta("cnui_state", state)
	node.set(token.prop, translated)

func _on_indexed_ready(source, translated, token):
	var node = token.node
	if node == null || !is_instance_valid(node):
		return

	var state = _get_state(node)
	if !state.has(token.state_key):
		return

	var bucket = state[token.state_key]
	var item_key = str(token.index)
	if !bucket.has(item_key):
		return

	var entry = bucket[item_key]
	if !entry.has("source") || entry.source != token.source:
		return

	if translated == source:
		# 原文原样返回时不算成功，避免把失败结果锁进缓存状态。
		_mark_retry(entry, source)
		bucket[item_key] = entry
		state[token.state_key] = bucket
		node.set_meta("cnui_state", state)
		return

	entry.translated = translated
	entry.pending = false
	entry.done = true
	entry.erase("retry_at")
	bucket[item_key] = entry
	state[token.state_key] = bucket
	node.set_meta("cnui_state", state)
	node.call(token.setter, token.index, translated)

func _entry_is_translated(entry, value):
	return entry.get("done", false) && entry.has("translated") && entry.translated == value

func _entry_has_translation(entry, value):
	return entry.get("done", false) && entry.has("translated") && entry.translated != value

func _entry_is_locked(entry, value):
	if !entry.has("retry_at"):
		return false
	return int(entry.retry_at) > OS.get_unix_time()

func _needs_translation(text):
	return text_tools != null && text_tools.has_translatable_text(text)

func _mark_translated(node, prop, value):
	var state = _get_state(node)
	state[prop] = {
		source = value,
		translated = value,
		pending = false,
		done = true
	}
	node.set_meta("cnui_state", state)

func _mark_retry(entry, source):
	var retry_at = 0
	if translator != null && translator.is_ready():
		retry_at = int(translator.get_retry_time(source))
	if retry_at <= OS.get_unix_time():
		retry_at = OS.get_unix_time() + 60
	entry.pending = false
	entry.done = false
	entry.erase("translated")
	entry.retry_at = retry_at

func _get_state(node):
	if node.has_meta("cnui_state"):
		var state = node.get_meta("cnui_state")
		if typeof(state) == TYPE_DICTIONARY:
			return state
	var state = {}
	node.set_meta("cnui_state", state)
	return state

func _clear_node_state(node):
	if node == null:
		return
	if node.has_meta("cnui_state"):
		node.remove_meta("cnui_state")
	for child in node.get_children():
		_clear_node_state(child)
