#!/bin/sh
cd "$(dirname "$0")"
# Cold checkouts need one import pass to build the script class registry.
if [ ! -d .godot ]; then
  godot --headless --import > /dev/null 2>&1
fi
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://test/unit -ginclude_subdirs -gexit
