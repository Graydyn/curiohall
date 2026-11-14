godot run .

godot --headless --export-debug "Android" build/curiohall.apk
adb install -r build/curiohall.apk
