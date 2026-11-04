Lights: an iPhone app for LED Studio
=====================================

What it has
  App               big brightness bar, power, live strip preview, scenes, colors, AI "make an effect", saved effects
  Siri              "Turn off Lights", "Lights movie mode", "Set Lights to evening", "Turn Lights blue",
                    "Play Cozy evening on Lights", "Set Lights brightness", "Make an effect on Lights"
                    (These also appear in the Shortcuts app for automations: alarm, sunset, arriving home...)
  Widgets           small: power + dimmer/brighter    medium: that + 4 scenes    Lock Screen: power
  Control Center    "Room Lights" on/off toggle and a "Movie Mode" button (also usable on the Action button)

It talks to LED Studio 4.1 or newer (it needs the new /api/scene endpoint), only on your home Wi-Fi.

Build it (no Mac needed)
  1. Make a new GitHub repo and upload everything in this folder, including the hidden .github folder.
     (Easiest: GitHub Desktop, or "Add file -> Upload files" and drag the folder contents in.)
  2. Every push builds it. To set the address: Actions -> Build Lights -> Run workflow -> server.
     Default is http://lights.local. If you haven't set that name up yet, use your server's address,
     e.g. http://192.168.50.111:8000 (whatever you type into Safari to open LED Studio).
  3. When the run finishes, open it and download "Lights-ipa" at the bottom. Unzip it to get Lights.ipa.
  4. Install Lights.ipa with the same PC app you used last time.

If the build fails, open the failed run, click the "Build" step and copy the lines with "error:".

First run
  - Open the app once. Allow "Local Network" when it asks; without it nothing can reach LED Studio.
  - Long-press the home screen -> Edit -> Add Widget -> Lights.
  - Control Center: swipe down -> Edit (top left) -> Add a Control -> Lights.
  - Siri learns the app's phrases on its own; give it a minute after the first launch.

Notes
  - The app's Settings (gear icon) can change the address for the app and Siri. Widgets and Control Center
    always use the address it was built with, so rebuild if that changes.
  - If Siri sends "turn off lights" to the Home app instead, say "Room Lights" (e.g. "Turn off Room Lights").
  - Making an AI effect through Siri takes as long as it does in the app (5-15 s with the 27B).
