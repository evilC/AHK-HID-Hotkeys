;#include <AHKHID>
/*
ToDo:
_StateIndex, _Bindings dynamic properties - set 0 on unset.

*/
#SingleInstance force
OnExit, GuiClose

; Input types. These match HID input types
global HH_TYPE_M := 0
global HH_TYPE_K := 1
global HH_TYPE_O := 2

HKHandler := new CHIDHotkeys()

HKHandler.Add({type: HH_TYPE_K, input: GetKeyVK("a"), modifiers: [{type: HH_TYPE_K, input: GetKeyVK("ctrl")}], callback: "HighBeep", modes: {passthru: 0, wild: 1}, event: 1})
HKHandler.Add({type: HH_TYPE_K, input: GetKeyVK("a"), modifiers: [{type: HH_TYPE_K, input: GetKeyVK("ctrl")},{type: HH_TYPE_K, input: GetKeyVK("shift")}], callback: "LowBeep", modes: {passthru: 0}, event: 1})

mc := new CMainClass()

Return

Esc::ExitApp
GuiClose:
ExitApp

HighBeep(){
	soundbeep, 1000, 250
}
	
LowBeep(){
	soundbeep, 500, 250
}

; Test functionality when callback bound to a class method
Class CMainClass {
	__New(){
		global HKHandler
		fn := Bind(this.DownEvent, this)
		HKHandler.Add({type: HH_TYPE_K, input: GetKeyVK("b"), modifiers: [], callback: fn, modes: {passthru: 1}, event: 1})
	}
	
	DownEvent(){
		soundbeep
	}
}

; Test script end ==============================

; Only ever instantiate once!
Class CHIDHotkeys {
	_Bindings := []
	_StateIndex := []
	__New(){
		this._StateIndex := []
		this._StateIndex[0] := {}
		this._StateIndex[1] := {0x10: 0, 0x11: 0, 0x12: 0, 0x5D: 0}	; initialize modifier states
		this._StateIndex[2] := {}
		CHIDHotkeys._Instance := this	; store reference to instantiated class in Class Definition, so non-class functions can find the instance.
		OnMessage(0x00FF, Bind(this._ProcessHID, this))
		this._HIDRegister()
	}
	
	__Delete(){
		this._HIDUnRegister()
		CHIDHotkeys._Instance := ""	; remove reference to instantiated class from Class Definition
	}
	
	; Add a binding
	Add(obj){
		;return new this._Binding(this,obj)
		this._Bindings.Insert(obj)
	}
	
	_ProcessInput(data){
		if (data.type = HH_TYPE_K){
			; Set _StateIndex to reflect state of key
			if (data.input = 65){
				a := 1	; Breakpoint - done like this so you can hold a modifier but not break.
			}
			this._StateIndex[HH_TYPE_K][data.input] := data.event
			; If key has Left / Right variants (ie Modifiers), on event for variant, set state for common version (eg on LCtrl down, set Ctrl as down too)
			if (data.input = 0xA0 || data.input = 0xA1){		; VK_LSHIFT || VK_RSHIFT
				; L/R Shift
				this._StateIndex[HH_TYPE_K][0x10] := data.event	; VK_SHIFT
			} else if (data.input = 0xA2 || data.input = 0xA3){ ; VK_LCONTROL || VK_RCONTROL
				; L/R control
				this._StateIndex[HH_TYPE_K][0x11] := data.event	; VK_CONTROL
			} else if (data.input = 0x5B || data.input = 0x5C){	; VK_LWIN || VK_RWIN
				; L/R Win
				this._StateIndex[HH_TYPE_K][0x5D] := data.event	; VK_APPS
			} else if (data.input = 0xA4 || data.input = 0xA5){	; VK_LMENU || VK_RMENU
				; L/R Alt
				this._StateIndex[HH_TYPE_K][0x12] := data.event	; VK_MENU
			}
			; find the total number of modifier keys currently held
			modsheld := this._StateIndex[HH_TYPE_K][0x10] + this._StateIndex[HH_TYPE_K][0x11] + this._StateIndex[HH_TYPE_K][0x5D] + this._StateIndex[HH_TYPE_K][0x12]
			; Find best match for binding
			best_match := {binding: 0, modcount: 0}
			Loop % this._Bindings.MaxIndex() {
				b := A_Index
				if (this._Bindings[b].type = data.type && this._Bindings[b].input = data.input && this._Bindings[b].event = data.event){
					max := this._Bindings[b].modifiers.MaxIndex()
					if (!max){	; convert "" to 0
						max := 0
					}
					matched := 0

					if (!ObjHasKey(this._Bindings[b].modifiers[1], "type")){
						; If modifier array empty, match
						max := 0
						best_match.binding := b
						best_match.modcount := 0
					} else {
						Loop % max {
							m := A_Index
							if (this._StateIndex[this._Bindings[b].modifiers[m].type][this._Bindings[b].modifiers[m].input]){
								; Match on one modifier
								matched++
							}
						}
					}
					if (matched = max){
						; All modifiers matched - we have a candidate
						if (best_match.modcount < max){
							; If wild not set, check no other modifiers in addition to matched ones are set.
							if ((modsheld = max) || this._Bindings[b].modes.wild = 1){
								; No best match so far, or there is a match but it uses less modifiers - this is current best match
								best_match.binding := b
								best_match.modcount := max
							}
						}
					}
				}
			}
			
			if (best_match.binding){
				; A match was found, call
				fn := this._Bindings[best_match.binding].callback
				fn.()
				if (this._Bindings[best_match.binding].modes.passthru = 0){
					; Block
					return 1
				}
			}
		}
		return 0
	}

	; Process Keyboard and Mouse messages from Hooks
	_ProcessHook(nCode, wParam, lParam){
		Critical
		
		If ((wParam = 0x100) || (wParam = 0x101)) { ; WM_KEYDOWN || WM_KEYUP
			if (this._ProcessInput({type: HH_TYPE_K, input: NumGet(lParam+0, 0, "Uint"), event: wParam = 0x100})){
				; Return 1 to block this input
				; ToDo: call _ProcessInput via another thread? We only have 300ms to return 1 else it wont get blocked?
				return 1
			}
		}
		Return this._CallNextHookEx(nCode, wParam, lParam)
	}
	
	; Process Joystick messages from HID
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
			;keyname := GetKeyName("vk" this.ToHex(vk,2))
			flags := AHKHID_GetInputInfo(lParam, II_KBD_FLAGS)
			makecode := AHKHID_GetInputInfo(lParam, II_KBD_MAKECODE)
			meta := 0
			if (vk == 17) {
				; Control
				if (flags < 2){
					; LControl
					meta := "L"
				} else {
					; RControl
					meta := "R"
					flags -= 2
				
				}
				; One of the control keys
			} else if (vk == 18) {
				; Alt
				if (flags < 2){
					; LAlt
					meta := "L"
				} else {
					; RAlt
					meta := "R"
					flags -= 3	; RALT REPORTS DIFFERENTLY!
				
				}
			} else if (vk == 16){
				; Shift
				if (makecode == 42){
					; LShift
					meta := "L"
				} else {
					; RShift
					meta := "R"
				}
			} else if (vk == 91 || vk == 92) {
				; Windows key
				flags -= 2
				if (makecode == 91){
					; LWin
					meta := "L"
				} else {
					; RWin
					meta := "R"
				}
			}
			;this._ProcessInput(r, prefix keyname, !flags)
			return this._ProcessInput(r, meta, vk, !flags)
			;Tooltip % "Keyboard: " s (flags ? " Up" : " Down")
		} Else If (r = RIM_TYPEHID) {
			
		}
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
		;AHKHID_AddRegister(2 + count)
		;AHKHID_AddRegister(1,2,A_ScriptHwnd,RIDEV_INPUTSINK)
		;AHKHID_AddRegister(1,6,A_ScriptHwnd,RIDEV_INPUTSINK)
		;for name, obj in joysticks {
		;	AHKHID_AddRegister(obj.page, obj.usage, A_ScriptHwnd, RIDEV_INPUTSINK)
		;}
		;AHKHID_Register()
		
		; Register global hooks
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback("_HIDHotkeysKeyboardHook", "Fast"))
		;bound := new RegisterBind(this._ProcessHook, this)
		;addr := new Onject(bound)
		;this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback(bound.Callback,,, addr))
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
	; input_meta = meta-info about input.
	; 	Keyboard: l (left modifier), r (right modifier) or 0 (not a modifier)
	;	Mouse: Always 0
	; 	Joystick: Stick ID
	; input_code: The input that happened.
	; 	Keyboard: VK
	; 	Mouse: 
	; 	Joystick: Axis or Button # ?
	; Event
	;   Keyboard / Mouse / Joystick Button: = 0 (up) / 1 (down)
	; 	Joystick: Axis Value
	
	; FATAL FLAW in code:
	; If hook passes into here, but we do not block, this will be called again, as HID receives another message...

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

; RegisterBind by GeekDude
class RegisterBind
{
	__New(Function, Params*)
	{
		this.Function := Function
		this.Params := Params
	}
 
	Callback()
	{
		this := Object(A_EventInfo)
		this.Function.(this.Params*)
	}
}