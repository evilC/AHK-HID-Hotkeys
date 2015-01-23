; AHKHID test script
#include <AHK-HID-Hotkeys>
#SingleInstance force
OnExit, GuiClose

HIDHotkeys := new CHIDHotkeys()
Return

Esc::ExitApp
GuiClose:
ExitApp
