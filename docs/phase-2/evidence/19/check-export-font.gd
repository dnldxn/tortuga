extends SceneTree
func _initialize():
 var pack := "/private/tmp/tortuga-19/after-release/tortuga-0.999-macos.pck"
 if not ProjectSettings.load_resource_pack(pack):
  quit(1)
  return
 var font = load("res://assets/fonts/DejaVuSerif-headings.ttf")
 var source := FileAccess.get_file_as_bytes("/Users/ddixon/projects/tortuga/game/assets/fonts/DejaVuSerif-headings.ttf")
 print("EXPORTED_FONT_BYTES=", font.data.size(), " EXACT_SOURCE_MATCH=", font.data == source)
 quit(0 if font.data == source else 1)
