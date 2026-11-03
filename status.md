# Zip It: Status

Last updated: 2026-10-30

## Files
- `index.html`: original game (unchanged).
- `index-fixed.html`: revised version with the review fixes and the new snag behaviour.

## Done (in `index-fixed.html`)
- Snag behaviour: after hitting the denim, the slider returns to START as a ghost and the player moves the cursor back onto it to retry. The timer pauses while not in control.
- Timer no longer runs while paused.
- Levels are the same maze on every screen. Resizing keeps the run.
- Difficulty keeps rising past level 7 (the grid grows until level 12, then corridors narrow).
- Pointer lock removed. Large cursor jumps disarm the slider instead of killing the player.
- Esc, P, tab switch and window blur pause the game. Resuming asks the player to put the cursor back on the slider.
- Touch and pen support. The HUD wraps on narrow screens.
- Slider sprite and collision size now match.
- Zipping uses spatial buckets. `roundRect` fallback added. Sound ON/OFF chip in the HUD. Dead code removed.
- Added: best time per level (saved in the browser), star ratings, run total, reduced-motion support.

## Verification
- JavaScript syntax check passed.
- Not yet played in a browser. Needs a manual playtest.

## To check when playtesting
- Snag, return to START and retry flow feels right.
- Touch input works on a real phone or tablet.
- Corridor size and collision feel fair at levels 1, 6, 12 and 15+.
- Resizing the window mid-run keeps progress.

## Possible next steps
- Level select screen.
- Fog or limited-view mode.
- Moving hazards and pickups.
- Keyboard or gamepad steering.
- High-contrast mode.
- Publish to JSSI Pages for the team.
