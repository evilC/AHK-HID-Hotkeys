; AHKHID test script
#include <AHK-HID-Hotkeys>
#SingleInstance force
OnExit, GuiClose

HKHandler := new CHIDHotkeys()

fn := Bind("DownEvent", "a")
;hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}, modifiers: {type: "keyboard", key: "ctrl"}}, fn)
;hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}, modes: {passthru: 1}}, fn)
hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}}, fn)

c1 := new CMainClass()

Return

DownEvent(key){
	msgbox DOWNEVENT %key%
}
	
Class CMainClass {
	__New(){
		global HKHandler
		fn := Bind(this.DownEvent, this, "b")
		this.hk1 := HKHandler.Add({ input: {type: "keyboard", key: "b"}}, fn)
	}
	
	DownEvent(key){
		msgbox DOWNEVENT %key%
	}
}

Esc::ExitApp
GuiClose:
ExitApp
