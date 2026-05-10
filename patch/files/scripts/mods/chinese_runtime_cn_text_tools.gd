extends Reference

# 保护 $name 变量和 BBCode 标签，避免翻译服务改坏游戏标记。
var dollar_regex = RegEx.new()
var bracket_regex = RegEx.new()

func _init():
	dollar_regex.compile("\\$[A-Za-z_][A-Za-z0-9_]*")
	bracket_regex.compile("\\[[^\\[\\]]+\\]")

func has_translatable_text(text):
	var stripped = dollar_regex.sub(text, "", true)
	stripped = bracket_regex.sub(stripped, "", true)
	return stripped.to_lower() != stripped.to_upper()

func shield_tokens(text):
	var tokens = []
	var result = _shield_with_regex(text, dollar_regex, "__CNUI_D_", tokens)
	result = _shield_with_regex(result, bracket_regex, "__CNUI_B_", tokens)
	return {text = result, tokens = tokens}

func unshield_tokens(text, tokens):
	var result = text
	for item in tokens:
		result = result.replace(item.token, item.source)
	return result

func _shield_with_regex(text, regex, prefix, tokens):
	var result = ""
	var offset = 0
	var index = tokens.size()

	while true:
		var found = regex.search(text, offset)
		if found == null:
			break

		result += text.substr(offset, found.get_start() - offset)
		var token = prefix + str(index) + "__"
		result += token
		tokens.append({token = token, source = found.get_string()})
		offset = found.get_end()
		index += 1

	result += text.substr(offset, text.length() - offset)
	return result
