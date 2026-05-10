extends Reference

# 只保存本 mod 的运行配置，不写入游戏主设置，避免污染原项目。
const DEFAULTS = {
	"deepseek_api_key": "",
	"deepseek_api_url": "https://api.deepseek.com/chat/completions",
	"deepseek_model": "deepseek-v4-flash",
	"max_tokens": 4096,
	"temperature": 0.1,
}

var settings_path = ""
var data = {}

func setup(path):
	settings_path = path
	load_settings()
	return self

func load_settings():
	data = DEFAULTS.duplicate(true)

	var file = File.new()
	if !file.file_exists(settings_path):
		save_settings()
		return data

	var err = file.open(settings_path, File.READ)
	if err != OK:
		return data

	var parsed = parse_json(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in DEFAULTS.keys():
			if parsed.has(key):
				data[key] = parsed[key]

	save_settings()
	return data

func save_settings():
	_ensure_settings_dir()
	var file = File.new()
	var err = file.open(settings_path, File.WRITE)
	if err != OK:
		print("ChineseRuntimeCN: settings save failed, err=", err)
		return

	file.store_string(to_json(data))
	file.close()

func get_value(key):
	return data.get(key, DEFAULTS.get(key, ""))

func set_value(key, value):
	data[key] = value

func has_api_key():
	return str(get_value("deepseek_api_key")).strip_edges() != ""

func _ensure_settings_dir():
	var dir = Directory.new()
	dir.make_dir_recursive(settings_path.get_base_dir())
