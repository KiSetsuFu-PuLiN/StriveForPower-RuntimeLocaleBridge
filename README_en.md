English | [中文](README.md)

![Translation Preview](Snipaste_2026-05-11_01-54-10.png)

# RuntimeLocaleBridge

Runtime text translation bridge. This version is designed for `Strive for Power 1.0d` UI localization, with simplified Chinese as the default translation target.

## Supported Targets

- Game: `Strive for Power 1.0d` Windows 64-bit public build
- Mod folder: `RuntimeLocaleBridge`
- In-game recognition: the mod list shows the folder name, so keep this directory name when releasing
- Translation scope: visible runtime UI text, including `Label`, `BaseButton`, `RichTextLabel`, `LineEdit` hints, `hint_tooltip`, `window_title`, `dialog_text`, and entries in `MenuButton`, `OptionButton`, `PopupMenu`, `ItemList`, `TabContainer`

## Key Features

- Scan visible text components on the current UI
- Automatically switch fonts to ensure Chinese text displays correctly
- Cache translations locally to avoid repeat requests
- Shield BBCode tags and placeholders before translation, then restore them afterward
- Translation backend uses DeepSeek Chat Completions
- Supports custom API URL, model, `max_tokens`, and `temperature`

## Usage

1. Clone the entire project into the `mods` folder; you can find this location in the game's mod settings
2. Start the game and enable this mod
3. Open `Options -> Settings` inside the game
4. Fill in the `DeepSeek API Key`
5. Return to the game or restart once to let the runtime scanner take effect

## Configuration Files

- `cache/translations.json`: translation cache reused automatically later

## Notes

- The first run needs time to build the cache, and later runs will be noticeably faster
- This mod only processes text actually displayed on screen, not text inside images
- If the game's UI structure changes after an update, scanner rules may need to be adjusted accordingly
- The current backend is configured for Chinese translation, but the overall structure can be easily changed to other target languages

## Change the Translation Target Language

This project defaults to simplified Chinese translation. To change to another language, update the translation script's locale and DeepSeek system prompt, then clear the old cache.

1. Edit `patch/files/scripts/mods/chinese_runtime_cn_translator.gd`
   1. Locate these two lines in `_ready()`:
      ```gdscript
      translation_resource.locale = "zh_CN"
      TranslationServer.set_locale("zh_CN")
      ```
      Change `zh_CN` to the target Godot locale, for example:
      - Spanish: `"es"`
      - French: `"fr"`
      - Japanese: `"ja"`
      - Korean: `"ko"`
      - Russian: `"ru"`
   2. Find `_system_prompt()` and change the prompt to the target language, for example:
      ```gdscript
      return "You are a game text translator. Translate the given English UI text into Japanese. Return only the translation, no explanation. Preserve line breaks, numbers, punctuation, and placeholders exactly; placeholders like __CNUI_D_0__ and __CNUI_B_0__ must remain unchanged."
      ```
2. Delete `cache/translations.json` or clear its contents to avoid using the previous Chinese translation cache.
3. If the target language uses non-Latin characters, you may need to replace font files such as `BLKCHCRY.TTF` and `Roundo-Medium.otf` to ensure the needed glyphs are available (do not change the font file names).
4. Install and use the mod normally.
