<AddTo 2>
func _ready():
	call_deferred("_cnui_install")

func _cnui_install():
	# 晚一帧再挂载，避开主菜单初始化阶段的树阻塞。
	var cnui_root = get_tree().get_root()
	if cnui_root == null:
		return
	if cnui_root.has_node("ChineseRuntimeCN"):
		return
	if cnui_root.has_meta("ChineseRuntimeCN_installing") && cnui_root.get_meta("ChineseRuntimeCN_installing"):
		return
	cnui_root.set_meta("ChineseRuntimeCN_installing", true)
	yield(get_tree(), "idle_frame")
	var bootstrap_path = "res://files/scripts/mods/chinese_runtime_cn_bootstrap.gd"
	if !ResourceLoader.exists(bootstrap_path):
		cnui_root.set_meta("ChineseRuntimeCN_installing", false)
		print("ChineseRuntimeCN: bootstrap script missing")
		return
	if cnui_root.has_node("ChineseRuntimeCN"):
		cnui_root.set_meta("ChineseRuntimeCN_installing", false)
		return
	var cnui = load(bootstrap_path).new()
	cnui.name = "ChineseRuntimeCN"
	cnui_root.add_child(cnui)
	cnui_root.set_meta("ChineseRuntimeCN_installing", false)
	print("ChineseRuntimeCN: bootstrap installed")
