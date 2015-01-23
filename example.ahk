; AHKHID test script
#include <AHK-HID-Hotkeys>
#SingleInstance force
OnExit, GuiClose

GUI_WIDTH := 600
GUI_HEIGHT := 400

HIDHotkeys := new CHIDHotkeys()

Gui, +Resize -MaximizeBox -MinimizeBox +LastFound

Gui, Show, % "w" GUI_WIDTH + 20 " h" GUI_HEIGHT + 50


;Keep handle
GuiHandle := WinExist()

Gosub, Register
Return

Register:
	Gui, Submit, NoHide    ;Put the checkbox in associated var

	count := 0
	for key, value in joysticks {
		count++
	}
	AHKHID_AddRegister(2 + count)
	AHKHID_AddRegister(1,2,GuiHandle,RIDEV_INPUTSINK)
	AHKHID_AddRegister(1,6,GuiHandle,RIDEV_INPUTSINK)
	for name, obj in joysticks {
		;msgbox % obj.human_name
		AHKHID_AddRegister(obj.page, obj.usage, GuiHandle, RIDEV_INPUTSINK)
	}
	AHKHID_Register()
Return

Unregister:
	AHKHID_Register(1,2,0,RIDEV_REMOVE)    ;Although MSDN requires the handle to be 0, you can send GuiHandle if you want.
Return                                    ;AHKHID will automatically put 0 for RIDEV_REMOVE.

Clear:
	If A_GuiEvent = DoubleClick
		GuiControl,, %A_GuiControl%,|
Return


Esc::ExitApp

GuiClose:
Unhook:
ExitApp
