@echo off
rem Skips the menus and starts straight in a game. Edit the options on the last line.
rem   --nation=air|earth|water        your nation
rem   --mode=duel|bots                a duel against one enemy bender, or training bots
rem   --enemy=auto|air|earth|water    the duel enemy
rem   --bots=fighters|benders         training bots: dummies that punch, or benders
rem   --botnation=air|earth|water     the benders' nation
"%~dp0godot\Godot_v4.3-stable_win64.exe" --path "%~dp0avatar-game" -- --quick --nation=water --mode=bots --bots=fighters
