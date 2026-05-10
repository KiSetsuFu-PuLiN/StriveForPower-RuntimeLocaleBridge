extends Node

# 在原设置面板里动态加 DeepSeek 设置，不需要修改 options.tscn。
var translator = null
var scanner = null
var settings = load("res://files/scripts/mods/chinese_runtime_cn_settings.gd").new()
var settings_path = ""
var install_clock = 0.0
var installed_parent = null

func setup(translator_ref, scanner_ref):
	translator = translator_ref
	scanner = scanner_ref

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	settings_path = globals.modfolder + "RuntimeLocaleBridge/settings.json"
	settings.setup(settings_path)
	set_process(true)
	call_deferred("_install_or_update")

func _process(delta):
	install_clock += delta
	if install_clock < 1.0:
		return
	install_clock = 0.0
	_install_or_update()

func _install_or_update():
	var options = get_tree().get_root().find_node("options", true, false)
	if options == null || !options.has_node("TabContainer/Settings"):
		return

	var parent = options.get_node("TabContainer/Settings")
	if parent == installed_parent && parent.has_node("RuntimeLocaleBridgeDeepSeek"):
		_sync_controls(parent.get_node("RuntimeLocaleBridgeDeepSeek"))
		return

	if parent.has_node("RuntimeLocaleBridgeDeepSeek"):
		installed_parent = parent
		_sync_controls(parent.get_node("RuntimeLocaleBridgeDeepSeek"))
		return

	var box = VBoxContainer.new()
	box.name = "RuntimeLocaleBridgeDeepSeek"
	box.set_meta("cnui_skip", true)
	box.margin_left = 403.0
	box.margin_top = 225.0
	box.margin_right = 790.0
	box.margin_bottom = 380.0
	parent.add_child(box)

	var title = Label.new()
	title.name = "title"
	title.text = "Runtime Locale Bridge"
	box.add_child(title)

	var api_key = LineEdit.new()
	api_key.name = "api_key"
	api_key.secret = true
	api_key.placeholder_text = "DeepSeek API Key"
	api_key.rect_min_size = Vector2(360, 34)
	box.add_child(api_key)

	var model = LineEdit.new()
	model.name = "model"
	model.placeholder_text = "模型，例如 deepseek-v4-flash"
	model.rect_min_size = Vector2(360, 34)
	box.add_child(model)

	var save = Button.new()
	save.name = "save"
	save.text = "保存 DeepSeek 设置"
	save.rect_min_size = Vector2(180, 34)
	save.connect("pressed", self, "_on_save_pressed", [box])
	box.add_child(save)

	var status = Label.new()
	status.name = "status"
	status.text = ""
	status.autowrap = true
	status.rect_min_size = Vector2(360, 42)
	box.add_child(status)

	installed_parent = parent
	_sync_controls(box)

func _sync_controls(box):
	if box == null:
		return
	box.set_meta("cnui_skip", true)

	settings.load_settings()
	var api_key = box.get_node("api_key")
	var model = box.get_node("model")
	if api_key != null && !api_key.has_focus():
		api_key.text = str(settings.get_value("deepseek_api_key"))
	if model != null && !model.has_focus():
		model.text = str(settings.get_value("deepseek_model"))

func _on_save_pressed(box):
	settings.load_settings()
	settings.set_value("deepseek_api_key", box.get_node("api_key").text.strip_edges())
	settings.set_value("deepseek_model", box.get_node("model").text.strip_edges())
	settings.save_settings()

	if translator != null && is_instance_valid(translator):
		translator.reload_settings()
	if scanner != null && is_instance_valid(scanner):
		scanner.clear_state()
		scanner.scan_now()

	box.get_node("status").text = "已保存。可见文本会重新扫描，未缓存文本将使用 DeepSeek。"
	print("RuntimeLocaleBridge: DeepSeek settings saved")
