# Checking a change and reporting back

## Before you check

- Rebuild and relaunch the app the way the project normally does, and wait until its window is showing.
- `inspect_element` and `find_elements` read the app selected in Loupe. If they say no app is selected, or nothing is at the note's spot, call `get_status` and ask the person to select the relaunched app in Loupe's toolbar.
- The element has to be visible. A note about a sheet, popover, or menu needs that part of the app open. Loupe never clicks, so you can't open it yourself: ask the person to open it, or check the code instead and say in your message that you couldn't see it on screen.

## What to check

- `inspect_element` with the note's `number` reads what is at the note's spot now, following the window if it moved. Compare it with what the note asked for: a new title, value, role, or size (`frame`).
- If your change moved the element, the note's spot may now hold something else. Use `find_elements` with the element's new label to find it.
- Some visual changes (color, font weight, spacing) don't show up in what Loupe reads. Check what you can, such as the frame for size and spacing, and tell the person what to look at.

## Writing the message

Messages appear in a small window on the note's badge. One or two plain sentences: what changed, where, and anything to try. Skip code blocks, lists, and long explanations.

- Done: "Renamed the button to Export in `ExportToolbar.swift`."
- Done, with something to try: "Made the sidebar 40 points wider in `SidebarView.swift`. Try it with a long project name."
- Dismissed: "Left this as it is. The close button is drawn by macOS, not by this app."
- Partly done (leave the note open): "Bolded the title in `HeaderView.swift`. The subtitle color comes from the system theme, so I haven't changed it yet. Should it always be gray?"
