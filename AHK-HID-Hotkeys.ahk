#include <AHKHID>

; Only ever instantiate once!
Class CHIDHotkeys {
	__New(){
		CHIDHotkeys._Instance := this	; store reference to instantiated class in Class Definition, so non-class functions can find the instance.
		OnMessage(0x00FF, "_HIDHotkeysInputMsg")
		this._HIDRegister()
	}
	
	__Delete(){
		this._HIDUnRegister()
		CHIDHotkeys._Instance := ""	; remove reference to instantiated class from Class Definition
	}
	
	_HIDRegister(){
		global RIDEV_INPUTSINK
		joysticks := {} ; disable for now
		count := 0
		for key, value in joysticks {
			count++
		}
		AHKHID_AddRegister(2 + count)
		AHKHID_AddRegister(1,2,A_ScriptHwnd,RIDEV_INPUTSINK)
		AHKHID_AddRegister(1,6,A_ScriptHwnd,RIDEV_INPUTSINK)
		for name, obj in joysticks {
			AHKHID_AddRegister(obj.page, obj.usage, A_ScriptHwnd, RIDEV_INPUTSINK)
		}
		AHKHID_Register()
	}
	
	_HIDUnRegister(){
		global RIDEV_REMOVE
		AHKHID_Register(1,2,0,RIDEV_REMOVE)		;Although MSDN requires the handle to be 0, you can send A_ScriptHwnd if you want.
		Return									;AHKHID will automatically put 0 for RIDEV_REMOVE.
	}
	
	ProcessMessage(wParam, lParam){
		global RIM_TYPEMOUSE, RIM_TYPEKEYBOARD, RIM_TYPEHID
		global II_DEVTYPE, II_MSE_BUTTONFLAGS
		r := AHKHID_GetInputInfo(lParam, II_DEVTYPE)
		waslogged := 0
		waswheel := 0
		If (r = -1)
			OutputDebug %ErrorLevel%
		If (r = RIM_TYPEMOUSE) {
			; Mouse Input ==============
			; Filter mouse movement
			flags := AHKHID_GetInputInfo(lParam, II_MSE_BUTTONFLAGS)
			if (flags){
				; IMPORTANT NOTE!
				; EVENT COULD CONTAIN MORE THAN ONE BUTTON CHANGE!!!
				soundbeep
			}
		} Else If (r = RIM_TYPEKEYBOARD) {
		
		} Else If (r = RIM_TYPEHID) {
			
		}
	}
	
	Test(){
		msgbox here
		
	}
}

_HIDHotkeysInputMsg(wParam, lParam) {
	; Re-route messages into the class (Lex says he will be enhancing AHK to let OnMessage call a class method so this can go at some point)
	Critical    ;Or otherwise you could get ERROR_INVALID_HANDLE
	CHIDHotkeys._Instance.ProcessMessage(wParam, lParam)
}
