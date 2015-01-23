#AHK-HID-Hotkeys
A class to replace AHK's hotkeys with a HID-based system not subject to the limitations of AHK's hotkeys.  
Specifically aimed at making dynamic hotkey solutions easier to write.

####Limitations of vanilla AHK that this class seeks to overcome:
* Maximum of 100 hotkeys  
This is not normally a problem, but in certain cases can be.
* Cannot fully remove hotkeys  
Only really an issue with the 1000 limit.
* Only down events supported for joystick buttons  
No up events for buttons, `GetKeyState()` must normally be used.
* No event-based mechanism for Joystick axis change.  
Again, endless `GetKeyState` loops must be used.
* No way of easily providing a "Bind" box that facilitates visually choosing of a hotkey, *that supports all input methods*.  
The `Hotkey` Gui item only supports certain keyboard keys.  
The `Input` command has limited support (No Joystick) and requires hacky `#if` statements to fully support some keys and combos.  

####How it works
All input is read via WM_INPUT messages.  
If a keyboard or mouse button needs to be blocked (eg a user wishes to do a mapping such as `a::b`), then the Windows API call `SetWindowsHookEx` is used to block the input from other applications.
