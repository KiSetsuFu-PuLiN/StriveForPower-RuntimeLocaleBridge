<AddTo 2>
func _ready():
	call_deferred("_cnui_install")

func _cnui_install():
	# 晚一帧再挂载，避开主菜单初始化阶段的树阻塞。
	var cnui_root = get_tree().get_root()
	if cnui_root == null:
		return
	if cnui_root.has_node("RuntimeLocaleBridge"):
		return
	if cnui_root.has_meta("RuntimeLocaleBridge_installing") && cnui_root.get_meta("RuntimeLocaleBridge_installing"):
		return
	cnui_root.set_meta("RuntimeLocaleBridge_installing", true)
	yield(get_tree(), "idle_frame")
	var bootstrap_path = "res://files/scripts/mods/chinese_runtime_cn_bootstrap.gd"
	if !ResourceLoader.exists(bootstrap_path):
		cnui_root.set_meta("RuntimeLocaleBridge_installing", false)
		print("RuntimeLocaleBridge: bootstrap script missing")
		return
	if cnui_root.has_node("RuntimeLocaleBridge"):
		cnui_root.set_meta("RuntimeLocaleBridge_installing", false)
		return
	var cnui = load(bootstrap_path).new()
	cnui.name = "RuntimeLocaleBridge"
	cnui_root.add_child(cnui)
	cnui_root.set_meta("RuntimeLocaleBridge_installing", false)
	print("RuntimeLocaleBridge: bootstrap installed")
