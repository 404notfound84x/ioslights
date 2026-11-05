Lights: an iPhone app for LED Studio
=====================================

What it has (same layout as the LED Studio page)
  Home       big brightness bar, power, what's playing, scenes, solid colors and gradients
  Effects    the built-in effects, with sliders/colors for the one that's playing
  Create     AI: describe an effect (with its own controls or as layers), its controls,
             "not quite right? say what to change", undo
  Saved      save what's playing, play or delete saved effects
  Settings   which LED Studio it found, the address list, fade/smoothing/frame rate,
             the disconnect fallback color, status

  Siri       "Lights fire", "Lights movie mode", "Turn Lights blue", "Make my Lights red",
             "Play my Cozy evening on Lights", "Set Lights brightness", "Make an effect on Lights"
             For plain light commands without saying "Lights" ("make my lights red", "dim the bedroom
             lights to 20%"), use the HomeKit bridge in LED Studio (homekit_bridge.py). See below.
  Widgets    small: power + dimmer/brighter    medium: that + 4 scenes    Lock Screen: power
  Control Center   "Room Lights" toggle and "Movie Mode" button (also for the Action button)

Finding LED Studio
  It tries these in order and uses the first one that answers (all at once, so it's quick):
    http://lights.local
    http://192.168.50.111      http://192.168.50.111:8000      (server)
    http://192.168.50.65       http://192.168.50.65:8000       (PC)
  If the one it's using stops answering, it looks again by itself. Change the list in the app's
  Settings (the app and Siri use that), or in project.yml / the build's "servers" box (widgets too).

Build it (no Mac needed)
  1. Upload everything in this folder to your GitHub repo (replace the old files), including .github.
  2. Actions -> Build Lights -> Run workflow. Leave "servers" empty to use the list above.
  3. Download "Lights-ipa" from the finished run, unzip, install Lights.ipa with your PC app.
  If it fails: open the run -> build -> Build step, copy the lines with "error:".

Needs LED Studio 4.1 or newer.

First run
  - Allow "Local Network" when it asks.
  - Widgets: long-press the home screen -> Edit -> Add Widget -> Lights.
  - Control Center: swipe down -> Edit -> Add a Control -> Lights.
