#include <AHKHID>
; AHKHID test script, included in main script for now for easy debugging =====================================================================================
#SingleInstance force
OnExit, GuiClose

HKHandler := new CHIDHotkeys()

fn := Bind("DownEvent", "a")
;hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}, modifiers: {type: "keyboard", key: "ctrl"}}, fn)
hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}, modes: {passthru: 0}}, fn)
;hk1 := HKHandler.Add({ input: {type: "keyboard", key: "a"}}, fn)

c1 := new CMainClass()

Return

Esc::ExitApp
GuiClose:
ExitApp

DownEvent(key){
	;msgbox DOWNEVENT %key%
	soundbeep
}
	
Class CMainClass {
	__New(){
		global HKHandler
		fn := Bind(this.DownEvent, this, "b")
		this.hk1 := HKHandler.Add({ input: {type: "keyboard", key: "b"}}, fn)
	}
	
	DownEvent(key){
		;msgbox DOWNEVENT %key%
		soundbeep
	}
}

; Test script end ==============================

; Only ever instantiate once!
Class CHIDHotkeys {
	_Bindings := {keyboard: {}, mouse: {}, other: {}}
	_StateIndex := {keyboard: {}, mouse: {}, other: {}}
	__New(){
		CHIDHotkeys._Instance := this	; store reference to instantiated class in Class Definition, so non-class functions can find the instance.
		OnMessage(0x00FF, Bind(this._ProcessHID, this))
		this._HIDRegister()
	}
	
	__Delete(){
		this._HIDUnRegister()
		CHIDHotkeys._Instance := ""	; remove reference to instantiated class from Class Definition
	}
	
	; Add a binding
	Add(binding, callback){
		return new this._Binding(this, binding, callback)
	}
	
	; Register with AHKHID
	_HIDRegister(){
		global RIDEV_INPUTSINK
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		static WH_CALLWNDPROC := 4, WH_GETMESSAGE := 3

		; Register with HID
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
		
		; Register global hooks
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback("_HIDHotkeysKeyboardHook", "Fast"))
		;this._hHookMouse := SetWindowsHookEx(WH_MOUSE_LL, RegisterCallback("MouseMove", "Fast"))

	}
	
	; Unregister with AHKDID
	_HIDUnRegister(){
		global RIDEV_REMOVE
		AHKHID_Register(1,2,0,RIDEV_REMOVE)		;Although MSDN requires the handle to be 0, you can send A_ScriptHwnd if you want.
		this._UnhookWindowsHookEx(this._hHookKeybd)
		this._UnhookWindowsHookEx(this._hHookMouse)
		Return									;AHKHID will automatically put 0 for RIDEV_REMOVE.
	}
	
	; Final stage of input processing. _ProcessHook and _ProcessHID both call this
	; ALL INPUT MUST FLOW THROUGH HERE
	; Type = RIM_TYPEMOUSE, RIM_TYPEKEYBOARD or RIM_TYPEHID (Joysticks)
	; Key = Name of key or button (key, mouse) or object like {device: blah, axis: 2} for joysticks.
	; Event = 0 (up) / 1 (down) for buttons, new value for axes
	_ProcessInput(type, key, event){
		global RIM_TYPEMOUSE, RIM_TYPEKEYBOARD, RIM_TYPEHID
		if (type = RIM_TYPEKEYBOARD){
			if (this._Bindings.keyboard[key].isbound){
				fn := this._Bindings.keyboard[key].callback
				fn.()
			}
		}
	}

	; Process messages from Hooks
	_ProcessHook(nCode, wParam, lParam){
		Critical
		global RIM_TYPEMOUSE, RIM_TYPEKEYBOARD, RIM_TYPEHID 
		SetFormat, Integer, H
		If ((wParam = 0x100) || (wParam = 0x101))  ;   ; WM_KEYDOWN || WM_KEYUP
		{
			KeyName := GetKeyName("vk" NumGet(lParam+0, 0, "Uint"))
			if (this._Bindings.keyboard[KeyName].modes.passthru = 0){
				; This input needs to be blocked from apps / the OS as it is remapped
				Tooltip, % "KBHook: Blocking " ((wParam = 0x100) ? KeyName " Down" :	KeyName " Up")
				; Allow script to see the input so it can perform remapping
				this._ProcessInput(RIM_TYPEKEYBOARD, KeyName, wParam = 0x100)
				; Return 1 to block this input
				; ToDo: call _ProcessInput via another thread? We only have 300ms to return 1 else it wont get blocked?
				return 1
			}
		}
		Return this._CallNextHookEx(nCode, wParam, lParam)
	}
	
	; Process messages from HID
	_ProcessHID(wParam, lParam){
		Critical
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
				;soundbeep
				a := 1
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
			this._ProcessInput(r, keyname, !flags)
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
	
	Class _Binding {
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
		{ input: {type: "joystick_button", id: 1, key: "12"}, modifiers: [{type: "keyboard", key: "ctrl"}, {type: "mouse", key: "rbutton"}]
		
		Joystick 1, Axis 2
		{ input: {type: "joystick_axis", id: 1, key: "2"}}
		*/
		__New(parent, binding, callback){
			this._parent := parent
			if (IsObject(!binding.input)){
				return 0
			}
			; Force modifiers to be array
			if (!binding.modifiers.MaxIndex()){
				binding.modifiers := [binding.modifiers]
			}
			; bindings.keyboard.a : {modifiers: [...]}
			; bindings.joystick[1].1 : {modifiers: [...]}
			if (binding.input.type = "keyboard" || binding.input.type = "mouse"){
				this._parent._Bindings[binding.input.type][binding.input.key] := {isbound: 1, callback: callback, modes: binding.modes}
				;this._parent._Bindings[binding.input.type][binding.input.key] := 1
			}
			; binding.input is the "End" key that can fire the binding
			; binding.modifiers is an object (or array of objects) specifiying keys that also need to be held for the binding to fire
			Loop % binding.modifiers.MaxIndex() {
				
			}
			return this
		}
	}
	
	_SetWindowsHookEx(idHook, pfn){
		Return DllCall("SetWindowsHookEx", "int", idHook, "Uint", pfn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")
	}

	_UnhookWindowsHookEx(hHook){
		Return DllCall("UnhookWindowsHookEx", "Uint", hHook)
	}

	_CallNextHookEx(nCode, wParam, lParam, hHook = 0){
		Return DllCall("CallNextHookEx", "Uint", hHook, "int", nCode, "Uint", wParam, "Uint", lParam)
	}

}

_HIDHotkeysKeyboardHook(nCode, wParam, lParam){
	Critical
	return CHIDHotkeys._Instance._ProcessHook(nCode, wParam, lParam)
}

; bind by Lexikos
; Requires test build of AHK? Will soon become part of AHK
; See http://ahkscript.org/boards/viewtopic.php?f=24&t=5802
bind(fn, args*) {  ; bind v1.2
    try bound := fn.bind(args*)  ; Func.Bind() not yet implemented.
    return bound ? bound : new BoundFunc(fn, args*)
}

class BoundFunc {
    __New(fn, args*) {
        this.fn := IsObject(fn) ? fn : Func(fn)
        this.args := args
    }
    __Call(callee, args*) {
        if (callee = "" || callee = "call" || IsObject(callee)) {  ; IsObject allows use as a method.
            fn := this.fn, args.Insert(1, this.args*)
            return %fn%(args*)
        }
    }
}