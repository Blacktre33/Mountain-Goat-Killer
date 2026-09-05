#!/bin/zsh
set -eu
game_directory="${0:A:h}"
exec /Applications/Godot.app/Contents/MacOS/Godot --path "$game_directory" "$@"
