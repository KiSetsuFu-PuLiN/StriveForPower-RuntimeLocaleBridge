extends Node

# 翻译顺序：Godot 缓存 -> 本地 JSON 缓存 -> DeepSeek。
# 网络请求只处理缓存缺失项，避免重复翻译和重复消耗 API 额度。
signal runtime_ready

var cache_path = ""
var settings_path = ""
var api_url = ""
var api_key = ""
var model = ""
var max_tokens = 4096
var temperature = 0.1
var api_key_missing_logged = false

var cache = {}
var fail_until = {}
var queue = []
var active_jobs = {}
var waiters = {}
var runtime_ready_flag = false

var settings = load("res://files/scripts/mods/chinese_runtime_cn_settings.gd").new()
var tools = load("res://files/scripts/mods/chinese_runtime_cn_text_tools.gd").new()
var translation_resource = Translation.new()

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS

	cache_path = globals.modfolder + "RuntimeLocaleBridge/cache/translations.json"
	settings_path = globals.modfolder + "RuntimeLocaleBridge/settings.json"
	settings.setup(settings_path)
	_reload_settings_from_store()

	_ensure_cache_dir()
	_load_cache()

	# 把缓存挂进 Godot 翻译系统，后续即使别处调用 tr() 也能复用。
	translation_resource.locale = "zh_CN"
	TranslationServer.add_translation(translation_resource)
	TranslationServer.set_locale("zh_CN")

	call_deferred("_install_http")

func _install_http():
	# 晚一帧再允许发请求，避免初始化阶段的 add_child 被树阻塞。
	yield(get_tree(), "idle_frame")
	if !is_inside_tree():
		return
	runtime_ready_flag = true
	emit_signal("runtime_ready")
	_pump_queue()

func is_ready():
	return runtime_ready_flag

func reload_settings():
	settings.load_settings()
	_reload_settings_from_store()
	fail_until.clear()
	api_key_missing_logged = false
	print("RuntimeLocaleBridge: DeepSeek settings reloaded")
	_pump_queue()

func get_retry_time(source):
	return int(fail_until.get(source, 0))

func translate_plain(source, callback_owner, callback_method, token = null):
	_queue_translation(source, source, null, callback_owner, callback_method, token)

func translate_bbcode(source, callback_owner, callback_method, token = null):
	# BBCode 走整句翻译：先把标签和变量罩住，再统一送去翻译并还原。
	var shield = tools.shield_tokens(source)
	_queue_translation(source, shield.text, shield.tokens, callback_owner, callback_method, token)

func _queue_translation(source, payload, tokens, callback_owner, callback_method, token):
	if callback_owner == null || !is_instance_valid(callback_owner):
		return

	if !tools.has_translatable_text(source):
		callback_owner.call(callback_method, source, source, token)
		return

	var cached = _lookup_cached(source)
	if cached != null:
		callback_owner.call(callback_method, source, cached, token)
		return

	if _api_key_missing():
		if !api_key_missing_logged:
			print("RuntimeLocaleBridge: DeepSeek API key is empty; edit settings.json or the Options panel.")
			api_key_missing_logged = true
		# 没有密钥时也记一次冷却，避免扫描器每一轮都重复撞同一条文本。
		_fail_current(source, 0)
		callback_owner.call(callback_method, source, source, token)
		return

	var retry_time = fail_until.get(source, 0)
	if retry_time > OS.get_unix_time():
		callback_owner.call(callback_method, source, source, token)
		return

	if waiters.has(source):
		waiters[source].append({owner = callback_owner, method = callback_method, token = token})
		return

	waiters[source] = [{owner = callback_owner, method = callback_method, token = token}]
	queue.append({source = source, payload = payload, tokens = tokens})
	_pump_queue()

func _lookup_cached(source):
	var translated = TranslationServer.translate(source)
	if translated != source && !_is_bad_translation(source, translated):
		return translated
	if cache.has(source):
		var cached = str(cache[source])
		if !_is_bad_translation(source, cached):
			return cached
	return null

func _remember_translation(source, translated):
	translated = _sanitize_translation(source, translated)
	if translated == null:
		return
	if cache.has(source) && cache[source] == translated:
		return

	cache[source] = translated
	translation_resource.add_message(source, translated)
	_save_cache()

func _pump_queue():
	if !runtime_ready_flag || queue.empty():
		return

	if _api_key_missing():
		while !queue.empty():
			var skipped_source = queue.pop_front()
			_emit_waiters(skipped_source, skipped_source)
		return

	# 不做单请求批量；队列里每条文本各起一个 HTTPRequest，并立即全部派发。
	while !queue.empty():
		var job = queue.pop_front()
		_start_request(job)

func _start_request(job):

	var headers = PoolStringArray()
	headers.append("Content-Type: application/json")
	headers.append("Accept: application/json")
	headers.append("Authorization: Bearer " + api_key)

	var request_node = HTTPRequest.new()
	request_node.connect("request_completed", self, "_on_request_completed", [request_node])
	add_child(request_node)

	var request_id = request_node.get_instance_id()
	active_jobs[request_id] = {source = job.source, tokens = job.tokens}

	var err = request_node.request(api_url, headers, true, HTTPClient.METHOD_POST, _build_payload(job.payload))
	if err != OK:
		print("RuntimeLocaleBridge: DeepSeek request failed, err=", err, ", text=", _trim_for_log(job.source))
		_dispose_request(request_node)
		_fail_current(job.source, 0)
		_emit_waiters(job.source, job.source)

func _on_request_completed(result, response_code, headers, body, request_node):
	if request_node == null || !is_instance_valid(request_node):
		return

	var request_id = request_node.get_instance_id()
	if !active_jobs.has(request_id):
		_dispose_request(request_node)
		return

	var job = active_jobs[request_id]
	var source = job.source
	var tokens = job.tokens
	_dispose_request(request_node)
	var response_text = body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS || response_code != 200:
		print("RuntimeLocaleBridge: DeepSeek bad response, code=", response_code, ", body=", _trim_for_log(response_text))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	var parsed = parse_json(response_text)
	if typeof(parsed) != TYPE_DICTIONARY || !parsed.has("choices"):
		print("RuntimeLocaleBridge: DeepSeek response parse failed, body=", _trim_for_log(response_text))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	var choices = parsed["choices"]
	if typeof(choices) != TYPE_ARRAY || choices.empty():
		print("RuntimeLocaleBridge: DeepSeek response has no choices, text=", _trim_for_log(source))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	var choice = choices[0]
	if typeof(choice) != TYPE_DICTIONARY || !choice.has("message"):
		print("RuntimeLocaleBridge: DeepSeek message missing, text=", _trim_for_log(source))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	if choice.has("finish_reason") && str(choice["finish_reason"]) == "length":
		print("RuntimeLocaleBridge: DeepSeek output truncated, increase max_tokens, text=", _trim_for_log(source))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	var message = choice["message"]
	if typeof(message) != TYPE_DICTIONARY || !message.has("content"):
		print("RuntimeLocaleBridge: DeepSeek content missing, text=", _trim_for_log(source))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	var translated = _sanitize_translation(source, message["content"], tokens)
	if translated == null:
		print("RuntimeLocaleBridge: DeepSeek returned unusable translation, text=", _trim_for_log(source))
		_fail_current(source, response_code)
		_emit_waiters(source, source)
		return

	_remember_translation(source, translated)
	_emit_waiters(source, translated)

func _emit_waiters(source, translated):
	if !waiters.has(source):
		return

	var items = waiters[source]
	waiters.erase(source)
	for item in items:
		if item.owner != null && is_instance_valid(item.owner):
			item.owner.call(item.method, source, translated, item.token)

func _dispose_request(request_node):
	if request_node == null:
		return

	if is_instance_valid(request_node):
		active_jobs.erase(request_node.get_instance_id())
		request_node.queue_free()

func _fail_current(source, response_code):
	var retry_delay = 300
	if response_code == 401 || response_code == 403 || response_code == 429:
		retry_delay = 3600
	fail_until[source] = OS.get_unix_time() + retry_delay

func _build_payload(text):
	var payload = {
		"model": model,
		"messages": [
			{"role": "system", "content": _system_prompt()},
			{"role": "user", "content": text}
		],
		"stream": false,
		"temperature": temperature,
		"max_tokens": max_tokens
	}
	if model.find("v4") >= 0:
		payload["thinking"] = {"type": "disabled"}
	return to_json(payload)

func _system_prompt():
	return "你是游戏文本翻译器。把用户给出的英文 UI 文本翻译为简体中文。只返回译文，不要解释。保持换行、数字、标点和占位符不变；形如 __CNUI_D_0__、__CNUI_B_0__ 的占位符必须原样保留。"

func _reload_settings_from_store():
	api_url = str(settings.get_value("deepseek_api_url")).strip_edges()
	if api_url == "":
		api_url = "https://api.deepseek.com/chat/completions"

	api_key = str(settings.get_value("deepseek_api_key")).strip_edges()
	model = str(settings.get_value("deepseek_model")).strip_edges()
	if model == "":
		model = "deepseek-v4-flash"

	max_tokens = int(settings.get_value("max_tokens"))
	if max_tokens < 256:
		max_tokens = 4096
	temperature = clamp(float(settings.get_value("temperature")), 0.0, 1.0)

func _api_key_missing():
	return api_key.strip_edges() == ""

func _sanitize_translation(source, translated, tokens = null):
	if typeof(translated) != TYPE_STRING:
		return null

	var text = str(translated).strip_edges()
	if text == "":
		return null

	if tokens != null:
		text = tools.unshield_tokens(text, tokens)
	text = _decode_entities(text)

	if text.to_upper().find("_CNUI_") >= 0:
		var shield = tools.shield_tokens(source)
		if shield.tokens.size() > 0:
			text = tools.unshield_tokens(text, shield.tokens)

	if _is_bad_translation(source, text):
		return null
	return text

func _is_bad_translation(source, translated):
	if typeof(translated) != TYPE_STRING:
		return true
	var text = str(translated).strip_edges()
	if text == "":
		return true
	if text.find("QUERY LENGTH LIMIT EXCEEDED") >= 0:
		return true
	if text.find("MAX ALLOWED QUERY") >= 0:
		return true
	if text.to_upper().find("_CNUI_") >= 0:
		return true
	if text == source && tools.has_translatable_text(source):
		return true
	return false

func _decode_entities(text):
	text = text.replace("&quot;", "\"")
	text = text.replace("&#39;", "'")
	text = text.replace("&apos;", "'")
	text = text.replace("&amp;", "&")
	text = text.replace("&lt;", "<")
	text = text.replace("&gt;", ">")
	text = text.replace("&nbsp;", " ")
	return text

func _trim_for_log(text):
	var value = str(text).replace("\n", "\\n")
	if value.length() > 240:
		return value.substr(0, 240) + "..."
	return value

func _ensure_cache_dir():
	var dir = Directory.new()
	dir.make_dir_recursive(cache_path.get_base_dir())

func _load_cache():
	var file = File.new()
	if !file.file_exists(cache_path):
		return

	var err = file.open(cache_path, File.READ)
	if err != OK:
		return

	var parsed = parse_json(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	cache = {}
	var removed_bad_entries = false
	for source in parsed.keys():
		var original = parsed[source]
		var translated = _sanitize_translation(source, original)
		if translated == null:
			removed_bad_entries = true
			continue
		if str(original).strip_edges() != translated:
			removed_bad_entries = true
		cache[source] = translated
		translation_resource.add_message(source, translated)

	if removed_bad_entries:
		_save_cache()

func _save_cache():
	var file = File.new()
	var err = file.open(cache_path, File.WRITE)
	if err != OK:
		return

	file.store_string(JSON.print(cache, "    "))
	file.close()
