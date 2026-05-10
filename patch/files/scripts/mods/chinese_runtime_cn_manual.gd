extends Reference

# 高频短文本先手工翻译，减少启动初期的网络请求。
var exact = {
	"Add": "添加",
	"Abilities": "能力",
	"Apply": "应用",
	"Back": "返回",
	"Cancel": "取消",
	"Choose target: ": "选择目标：",
	"Close": "关闭",
	"Confirm": "确认",
	"Constants": "常量",
	"Continue": "继续",
	"Credits": "制作人员",
	"Custom Start": "自定义开局",
	"Delete": "删除",
	"End Turn (F)": "结束回合 (F)",
	"Exit": "退出",
	"Finish Day": "结束一天",
	"Load": "载入",
	"Load Game": "读取游戏",
	"Main Menu": "主菜单",
	"New Game": "新游戏",
	"No": "否",
	"Remove": "移除",
	"Reset Selected": "重置所选",
	"Save": "保存",
	"Save Game": "保存游戏",
	"Save/Load": "存档/读档",
	"Sandbox": "沙盒",
	"Search": "搜索",
	"Select amount": "选择数量",
	"Select target: ": "选择目标：",
	"Select Subject": "选择对象",
	"Deselect": "取消选择",
	"Select name for...": "为...选择名称",
	"Options": "选项",
	"Settings": "设置",
	"Start": "开始",
	"Story": "剧情",
	"Virgin": "处女",
	"Use": "使用",
	"No scenes found": "未找到场景",
	"No Trait Selected": "未选择特质",
	"This will rewrite your save": "这会重写你的存档",
	"Test text": "测试文本",
	"Yes": "是",
}

var prefix_map = [
	{src = "Available Attribute Points : ", dst = "可用属性点："},
	{src = "Available upgrade points:", dst = "可用升级点："},
	{src = "Day: ", dst = "天数："},
	{src = "Experience: ", dst = "经验："},
	{src = "Free Attribute Points : ", dst = "可用属性点："},
	{src = "Free upgrade points:", dst = "可用升级点："},
	{src = "Gold: ", dst = "金币："},
	{src = "Health: ", dst = "生命："},
	{src = "Mana: ", dst = "法力："},
	{src = "Learning points per attribute: ", dst = "每项属性所需学习点："},
	{src = "Reputation: ", dst = "声望："},
	{src = "Weight: ", dst = "重量："},
	{src = "Energy: ", dst = "能量："},
]

func translate(text):
	if exact.has(text):
		return exact[text]

	var trimmed = text.strip_edges()
	if trimmed != text && exact.has(trimmed):
		return exact[trimmed]

	for item in prefix_map:
		if text.begins_with(item.src):
			var suffix = text.substr(item.src.length(), text.length() - item.src.length())
			return item.dst + suffix

	return null
