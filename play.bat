@echo off
rem Launches the Avatar game straight from its source files (no build needed).
rem Edit any .gd file in avatar-game\scripts, close the game, and run this again.
"%~dp0godot\Godot_v4.3-stable_win64.exe" --path "%~dp0avatar-game"
