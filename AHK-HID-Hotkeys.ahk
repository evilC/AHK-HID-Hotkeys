#include <AHKHID>

; Only ever instantiate once!
Class CHIDHotkeys {
	_Bindings := {}
	
	__New(){
		CHIDHotkeys._Instance := this	; store reference to instantiated class in Class Definition, so non-class functions can find the instance.
		OnMessage(0x00FF, "_HIDHotkeysInputMsg")
		this._HIDRegister()
	}
	
	__Delete(){
		this._HIDUnRegister()
		CHIDHotkeys._Instance := ""	; remove reference to instantiated class from Class Definition
	}
	
	; Makes a Binding
	/*
	Either Ctrl + a (Down event is assumed)
	{ input: {type: "keyboard", key: "a"}, modifiers: {type: "keyboard", key: "ctrl"}}
	
	Left Ctrl + a (Down event is assumed)
	{ input: {type: "keyboard", key: "a"}, modifiers: {type: "keyboard", key: "lctrl"}}
	
	Hold a, hit b
	{ input: {type: "keyboard", key: "b"}, modifiers: {type: "keyboard", key: "a"}}
	
	Ctrl+RButton
	{ input: {type: "mouse_button", key: "rbutton"}, modifiers: {type: "keyboard", key: "ctrl"}}
	
	Ctrl + Joystick 1, Button 12
	{ input: {type: "joystick_button", id: 1, key: "12"}, modifiers: {type: "keyboard", key: "ctrl"}}
	
	Ctrl + RButton + Joystick 1, Button 12
	{ input: {type: "joystick_button", id: 1, key: "12"}, modifiers: {type: "keyboard", key: "ctrl"}, {type: "mouse", key: "rbutton"}
	
	Joystick 1, Axis 2
	{ input: {type: "joystick_axis", id: 1, key: "2"}}
	*/
	RegisterInput(binding, callback){
		; Work in reverse order - final item = "end key"
		binding.key_down.MaxIndex()
		Loop % binding.key_down.MaxIndex() {
			;binding.key_down[A_Index]
		}
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
		global II_DEVTYPE, II_KBD_FLAGS, II_MSE_BUTTONFLAGS, II_KBD_VKEY, II_KBD_MAKECODE
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
			; Keyboard Input
			vk := AHKHID_GetInputInfo(lParam, II_KBD_VKEY)
			keyname := GetKeyName("vk" this.ToHex(vk,2))
			flags := AHKHID_GetInputInfo(lParam, II_KBD_FLAGS)
			makecode := AHKHID_GetInputInfo(lParam, II_KBD_MAKECODE)
			s := ""
			if (vk == 17) {
				; Control
				if (flags < 2){
					; LControl
					s := "Left "
				} else {
					; RControl
					s := "Right "
					flags -= 2
				
				}
				; One of the control keys
			} else if (vk == 18) {
				; Alt
				if (flags < 2){
					; LAlt
					s := "Left "
				} else {
					; RAlt
					s := "Right "
					flags -= 3	; RALT REPORTS DIFFERENTLY!
				
				}
			} else if (vk == 16){
				; Shift
				if (makecode == 42){
					; LShift
					s := "Left "
				} else {
					; RShift
					s := "Right "
				}
			} else if (vk == 91 || vk == 92) {
				; Windows key
				flags -= 2
				if (makecode == 91){
					; LWin
					s := "Left "
				} else {
					; RWin
					s := "Right "
				}
			}
			s .= keyname
			;Tooltip % "Keyboard: " s (flags ? " Up" : " Down")
		} Else If (r = RIM_TYPEHID) {
			
		}
	}
	
	; converts to hex, pads to 4 digits, chops off 0x
	ToHex(dec, padding := 4){
		return Substr(this.Convert2Hex(dec,padding),3)
	}

	Convert2Hex(p_Integer,p_MinDigits=0) {
		;-- Workaround for AutoHotkey Basic
		PtrType:=(A_PtrSize=8) ? "Ptr":"UInt"
	 
		;-- Negative?
		if (p_Integer<0)
			{
			l_NegativeChar:="-"
			p_Integer:=-p_Integer
			}
	 
		;-- Determine the width (in characters) of the output buffer
		nSize:=(p_Integer=0) ? 1:Floor(Ln(p_Integer)/Ln(16))+1
		if (p_MinDigits>nSize)
			nSize:=p_MinDigits+0
	 
		;-- Build Format string
		l_Format:="`%0" . nSize . "I64X"
	 
		;-- Create and populate l_Argument
		VarSetCapacity(l_Argument,8)
		NumPut(p_Integer,l_Argument,0,"Int64")
	 
		;-- Convert
		VarSetCapacity(l_Buffer,A_IsUnicode ? nSize*2:nSize,0)
		DllCall(A_IsUnicode ? "msvcrt\_vsnwprintf":"msvcrt\_vsnprintf"
			,"Str",l_Buffer             ;-- Storage location for output
			,"UInt",nSize               ;-- Maximum number of characters to write
			,"Str",l_Format             ;-- Format specification
			,PtrType,&l_Argument)       ;-- Argument
	 
		;-- Assemble and return the final value
		Return l_NegativeChar . "0x" . l_Buffer
	}

}

_HIDHotkeysInputMsg(wParam, lParam) {
	; Re-route messages into the class (Lex says he will be enhancing AHK to let OnMessage call a class method so this can go at some point)
	Critical    ;Or otherwise you could get ERROR_INVALID_HANDLE
	CHIDHotkeys._Instance.ProcessMessage(wParam, lParam)
}
