#include <AHKHID>

Class CHIDHotkeys {
	__New(){
		OnMessage(0x00FF, "_HIDHotkeysInputMsg")
	}
}

_HIDHotkeysInputMsg(wParam, lParam) {
	Local r, h, wwaswheel
	Critical    ;Or otherwise you could get ERROR_INVALID_HANDLE
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
