extends Node

var translator
var scanner
var settings_ui

func _ready():
	name = "RuntimeLocaleBridge"
	pause_mode = Node.PAUSE_MODE_PROCESS
	call_deferred("_install")

func _install():
	# 再等一帧，避免场景树还没完全放开就开始挂载。
	yield(get_tree(), "idle_frame")
	var translator_path = "res://files/scripts/mods/chinese_runtime_cn_translator.gd"
	var scanner_path = "res://files/scripts/mods/chinese_runtime_cn_scanner.gd"
	var settings_ui_path = "res://files/scripts/mods/chinese_runtime_cn_settings_ui.gd"
	if !ResourceLoader.exists(translator_path) || !ResourceLoader.exists(scanner_path):
		print("RuntimeLocaleBridge: runtime scripts missing")
		return

	# 先放翻译器，再放扫描器，结构简单，职责清楚。
	translator = load(translator_path).new()
	add_child(translator)

	scanner = load(scanner_path).new()
	scanner.setup(translator)
	add_child(scanner)

	# 设置面板只负责读写配置；缺失时不影响运行时翻译。
	if ResourceLoader.exists(settings_ui_path):
		settings_ui = load(settings_ui_path).new()
		settings_ui.setup(translator, scanner)
		add_child(settings_ui)

	if translator.is_ready():
		scanner.scan_now()
		print("RuntimeLocaleBridge: runtime translator started")
	else:
		translator.connect("runtime_ready", scanner, "scan_now")
		translator.connect("runtime_ready", self, "_on_runtime_ready")

func _on_runtime_ready():
	print("RuntimeLocaleBridge: runtime translator started")
