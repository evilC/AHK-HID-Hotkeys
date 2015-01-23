; AHKHID test script
#include <AHK-HID-Hotkeys>
#SingleInstance force
OnExit, GuiClose

HKHandler := new CHIDHotkeys()

;HKHandler.RegisterInput({ input: {type: "keyboard", key: "a"}, modifiers: {type: "keyboard", key: "ctrl"}}, "test")
Return

Class CMainClass {
	__New(){
		this.hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}, modifiers: {type: "keyboard", key: "ctrl"}}, "DownEvent")
	}
	
	DownEvent(){
		
	}
}

Esc::ExitApp
GuiClose:
ExitApp
