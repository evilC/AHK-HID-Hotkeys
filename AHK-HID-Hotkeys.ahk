;#include <AHKHID>
/*
ToDo:
* _StateIndex, _Bindings dynamic properties - set 0 on unset.
* HID input for joystick support
* Allow removal of bindings
* sanity check bindings on add (duplicates, impossible keys etc)

Bugs:
* Bind bug: Holding Ctrl + A, then hitting LShift does not clear common key "Shift" from the list.

*/
#SingleInstance force
OnExit, GuiClose

; Input types. These match HID input types
global HH_TYPE_M := 0
global HH_TYPE_K := 1
global HH_TYPE_O := 2
global HH_MOUSE_WPARAM_LOOKUP := {0x201: 1, 0x202: 1, 0x204: 2, 0x205: 2, 0x207: 3, 0x208: 3, 0x020B: 4, 0x020C: 4, 0x20A: 6, 0x20E: 7} ; No XButton 2 lookup as it lacks a unique wParam
global HH_MOUSE_NAME_LOOKUP := {LButton: 1, RButton: 2, MButton: 3, XButton1: 4, XButton2: 5, Wheel: 6, Tilt: 7}
global HH_MOUSE_BUTTON_NAMES := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "MWheel", "MTilt"]
global HH_INPUT_TYPES := {0: "Mouse", 1: "Keyboard", 2: "Other"}

HKHandler := new CHIDHotkeys()

fn := Bind("AsynchBeep", 1000)
HKHandler.Add({type: HH_TYPE_K, input: GetKeyVK("a"), modifiers: [{type: HH_TYPE_K, input: GetKeyVK("ctrl")}], callback: fn, modes: {passthru: 0, wild: 1}, event: 1})
fn := Bind("AsynchBeep", 500)
HKHandler.Add({type: HH_TYPE_K, input: GetKeyVK("a"), modifiers: [{type: HH_TYPE_K, input: GetKeyVK("ctrl")},{type: HH_TYPE_K, input: GetKeyVK("shift")}], callback: fn, modes: {passthru: 0}, event: 1})

mc := new CMainClass()

HKHandler.Bind("BindingDetected")

Return

; Test Bind ended
; data holds information about the key that triggered exit of Bind Mode
BindingDetected(binding, data){
	global HKHandler
	human_readable := HKHandler.GetBindingHumanReadable(binding, data)
	s := "You Hit " human_readable.endkey
	if (human_readable.modifiers){
		s .= " while holding " human_readable.modifiers
	}
	msgbox % s
}

Esc::ExitApp
GuiClose:
ExitApp

; Asynchronous Beeps for debugging or notification
AsynchBeep(freq){
	fn := Bind("Beep",freq)
	; Kick off another thread and continue execution.
	SetTimer, % fn, -0
}

Beep(freq){
	Soundbeep % freq, 250	
}

; Test functionality when callback bound to a class method
Class CMainClass {
	__New(){
		global HKHandler
		fn := Bind(this.DownEvent, this)
		HKHandler.Add({type: HH_TYPE_K, input: GetKeyVK("b"), modifiers: [], callback: fn, modes: {passthru: 1}, event: 1})
	}
	
	DownEvent(){
		AsynchBeep(750)
	}
}

; Test script end ==============================

; Only ever instantiate once!
Class CHIDHotkeys {
	_Bindings := []				; Holds list of bindings
	_BindMode := 0				; Whether we are currently making a binding or not
	_StateIndex := []			; State of inputs as of last event
	_BindModeCallback := 0		; Callback for BindMode
	_MAPVK_VSC_TO_VK := {}		; Holds lookup table for left / right handed keys (eg lctrl/rctrl) to common version (eg ctrl)
	_MAPVK_VK_TO_VSC := {}		; Lookup table for going the other way
	_MapTypes := { 0:"_MAPVK_VK_TO_VSC", 1:"_MAPVK_VSC_TO_VK"}	; VK to Scancode Lookup tables.

	; USER METHODS ================================================================================================================================
	; Stuff intended for everyday use by people using the class.
	
	; Add a binding. Input format is basically the same as the _Bindings data structure. See Docs\Bindings Structure.json
	Add(obj){
		;return new this._Binding(this,obj)
		this._Bindings.Insert(obj)
	}
	
	; Request a binding.
	; Returns 1 for OK, you have control of binding system, 0 for no.
	Bind(callback){
		; ToDo: need good way if check if valid callback
		if (this.BindMode || callback = ""){
			return 0
		}
		this._BindModeCallback := callback
		this._DetectBinding()
		return 1
	}
	
	; Converts an Input to a human readable format.
	GetInputHumanReadable(type, code) {
		if (type = HH_TYPE_K){
			vk := this.ToHex(code,2)
			keyname := GetKeyName("vk" vk)
		} else if (type = HH_TYPE_M){
			keyname := HH_MOUSE_BUTTON_NAMES[code]
		}
		StringUpper, keyname, keyname
		return keyname
	}
	
	; Converts a Binding, data pair into a human readable endkey and modifier strings
	GetBindingHumanReadable(binding, data) {
		endkey := this.GetInputHumanReadable(data.type, data.input.vk)	; ToDo: fix for stick?
		if (this.IsWheelType(data)){
			; Mouse wheel cannot be a modifier, as it releases immediately
			if (data.event < 0){
				endkey .= "_U"
			} else {
				endkey .= "_D"
			}
		}
		modifiers := ""
		count := 0
		Loop 2 {
			t := A_Index - 1
			for key, value in binding[t] {
				if (t = data.type && key = data.input.vk){
					; this is the end key - skip
					continue
				}
				if (count){
					modifiers .= " + "
				}
				modifiers .= this.GetInputHumanReadable(t,key)
				count++
			}
		}
		
		return {endkey: endkey, modifiers: modifiers}
	}
	
	; Adds the "common variant" (eg Ctrl) to ONE left/right variant (eg LCtrl) in a State object
	; ScanCode as input
	StateObjAddCommonVariant(obj, state, vk, sc := 0){
		translated_vk := this._MapVirtualKeyEx(sc)
		if ( translated_vk && (translated_vk != vk) ){
			; Has a left / right variant
			obj[HH_TYPE_K][translated_vk] := state
			return 1
		}
		return 0
	}
	
	; Removes a "Common Variant" (eg Ctrl) from ALL left/right variants (eg Lctrl) in a State object
	; Does not alter the object passed in, returns the new object out.
	StateObjRemoveCommonVariants(obj){
		; ToDo: Mouse, stick etc.
		out := {}
		for key, value in obj {
			out[key] := value	; add branch on
			; If this is a left / right version of a key, remove it
			; Convert VK into left / right indistinguishable SC
			res := this._MapVirtualKeyEx(key,0)
			; Convert non left/right sensitve SC back to VK
			res := this._MapVirtualKeyEx(res,1)
			
			; if key has left / right versions, result will be different to the original value
			if (res != key){
				out.Remove(key)
			}
		}
		return out
	}
	
	; Data packet is of mouse wheel motion
	IsWheelType(data){
		return (data.type = HH_TYPE_M) && (data.input.vk = HH_MOUSE_NAME_LOOKUP.Wheel)
	}
	
	; Data packet is an up event for a button or a mouse wheel move (Which does not have up events)
	IsUpEvent(data){
		return ( !data.event || this.IsWheelType(data) )
	}
	
	; INTERNAL / PRIVATE ==========================================================================================================================
	; Anything prefixed with an underscore ( _ ) is not intended for use by end-users.

	; Locks out input and prompts the user to hit the desired hotkey that they wish to bind.
	; Terminates on key up.
	; Returns a copy of the _StateIndex array just before the key release
	_DetectBinding(){
		Gui, New, HwndHwnd -Border
		this._BindPrompt := hwnd
		Gui, % Hwnd ":Add", Text, center w400,Please select what you would like to use for this binding`n`nCurrently, keyboard and mouse input is supported.`n`nHotkey is bound when you release the last key.
		Gui, % Hwnd ":Show", w400
	
		this._BindMode := 1
		return 1
	}

	; Up event or change happened in bind mode.
	; _Stateindex should hold state of desired binding.
	_BindingDetected(data){
		Gui, % this._BindPrompt ":Destroy"
		AsynchBeep(2000)
		
		; Discern End-Key from rest of State
		; "End Pair" (state + endkey data) starts here.
		input_state := {0: this._StateIndex[HH_TYPE_M], 1: this.StateObjRemoveCommonVariants(this._StateIndex[HH_TYPE_K]) }
		output_state := {0: {}, 1: {} }

		; Walk _StateIndex and copy where button is held.
		Loop 2 {
			t := A_Index-1
			s := ""
			for key, value in input_state[t] {
				if ( value && (value != 0) ){
					output_state[t][key] := value
				}
			}
		}
		; call callback, pass _StateIndex structure
		fn := Bind(this._BindModeCallback, output_state, data)
		SetTimer, % fn, -0
		return 1
	}

	; Constructor
	__New(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		
		this._StateIndex := []
		this._StateIndex[0] := {}
		this._StateIndex[1] := {0x10: 0, 0x11: 0, 0x12: 0, 0x5D: 0}	; initialize modifier states
		this._StateIndex[2] := {}
		;this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback("_HIDHotkeysKeyboardHook", "Fast"))
		fn := _BindCallback(this._ProcessKHook,"Fast",,this)
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, fn)
		fn := _BindCallback(this._ProcessMHook,"Fast",,this)
		this._hHookMouse := this._SetWindowsHookEx(WH_MOUSE_LL, fn)
		
		;OnMessage(0x00FF, Bind(this._ProcessHID, this))
		;this._HIDRegister()
	}
	
	; Destructor
	__Delete(){
		this._HIDUnRegister()
	}
	
	; Muster point for processing of incoming input - ALL INPUT SHOULD ULTIMATELY ROUTE THROUGH HERE
	; SetWindowsHookEx (Keyboard, Mouse) to route via here.
	; HID input (eg sticks) to be routed via here too.
	_ProcessInput(data){
		if (data.type = HH_TYPE_K || data.type = HH_TYPE_M){
			; Set _StateIndex to reflect state of key
			; lr_variant := data.input.flags & 1	; is this the left (0) or right (1) version of this key?
			if (data.input.vk = 65){
				a := 1	; Breakpoint - done like this so you can hold a modifier but not break.
			}
			if (data.event = 0){
				debug := "Exit Bind Mode Debug Point"
			}
			if ( this._BindMode && this.IsUpEvent(data) ){
				; Key up in Bind Mode - Fire _BindingDetected before updating _StateIndex, so it sees all the keys as down.
				; Pass data so it can see the End Key
				this._BindingDetected(data)
			}
			; Update _StateIndex array
			
			if (data.type = HH_TYPE_K){
				this.StateObjAddCommonVariant(this._StateIndex, data.event, data.input.vk, data.input.sc)
			}
			this._StateIndex[data.type][data.input.vk] := data.event
			
			; Exit bind Mode here, so we can be sure all input generated during Bind Mode is blocked, where possible.
			; ToDo data.event will not suffice for sticks?
			if ( this._BindMode && this.IsUpEvent(data) ){
				if (this.IsWheelType(data) && data.input.vk = HH_MOUSE_NAME_LOOKUP.Wheel){
					; Mouse Wheel has no up event, so release it now
					this._StateIndex[data.type][data.input.vk] := 0
				}
				this._BindMode := 0
			}
			
			; Do not process any further in Bind Mode
			if (this._BindMode){
				return 1
			}

			; find the total number of modifier keys currently held
			modsheld := this._StateIndex[data.type][0x10] + this._StateIndex[data.type][0x11] + this._StateIndex[data.type][0x5D] + this._StateIndex[data.type][0x12]
			
			; Find best match for binding
			best_match := {binding: 0, modcount: 0}
			Loop % this._Bindings.MaxIndex() {
				b := A_Index
				if (this._Bindings[b].type = data.type && this._Bindings[b].input = data.input.vk && this._Bindings[b].event = data.event){
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
			
			; Decide whether to fire callback
			if (best_match.binding){
				; A match was found, call
				fn := this._Bindings[best_match.binding].callback
				; Start thread for bound func
				SetTimer %fn%, -0
				; Block if needed.
				if (this._Bindings[best_match.binding].modes.passthru = 0){
					; Block
					return 1
				}
			}
		}
		return 0
	}

	; Process Keyboard messages from Hooks and feed _ProcessInput
	_ProcessKHook(nCode, wParam, lParam){
		Critical
		
		If ((wParam = 0x100) || (wParam = 0x101)) { ; WM_KEYDOWN || WM_KEYUP
			if (this._ProcessInput({type: HH_TYPE_K, input: { vk: NumGet(lParam+0, 0, "Uint"), sc: NumGet(lParam+0, 4, "Uint"), flags: NumGet(lParam+0, 8, "Uint")}, event: wParam = 0x100})){
				; Return 1 to block this input
				; ToDo: call _ProcessInput via another thread? We only have 300ms to return 1 else it wont get blocked?
				return 1
			}
		}
		Return this._CallNextHookEx(nCode, wParam, lParam)
	}
	
	; Process Mouse messages from Hooks and feed _ProcessInput
	_ProcessMHook(nCode, wParam, lParam){
		; Mouse callback struct: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644970(v=vs.85).aspx
		static WM_LBUTTONDOWN := 0x0201, WM_LBUTTONUP := 0x0202 , WM_RBUTTONDOWN := 0x0204, WM_RBUTTONUP := 0x0205, WM_MBUTTONDOWN := 0x0207, WM_MBUTTONUP := 0x0208, WM_MOUSEHWHEEL := x020E, WM_MOUSEWHEEL := 0x020A, WM_XBUTTONDOWN := 0x020B, WM_XBUTTONUP := 0x020C
		Critical
		
		; Filter out mouse move and other unwanted messages
		If ( wParam = WM_LBUTTONDOWN || wParam = WM_LBUTTONUP || wParam = WM_RBUTTONDOWN || wParam = WM_RBUTTONUP || wParam = WM_MBUTTONDOWN || wParam = WM_MBUTTONUP || wParam = WM_MOUSEWHEEL || wParam = WM_MOUSEHWHEEL || wParam = WM_XBUTTONDOWN || wParam = WM_XBUTTONUP ) {
			; ToDo: Some of these numgets and bit comparison seem a little dodgy. Can be improved.
			mouseData := NumGet(lParam+0, 8, "Uint")
			flags := NumGet(lParam+0, 12, "Uint")
			
			vk := HH_MOUSE_WPARAM_LOOKUP[wParam]
			if (wParam = WM_LBUTTONUP || wParam = WM_RBUTTONUP || wParam = WM_MBUTTONUP ){
				; Normally supported up event
				event := 0
			} else if (wParam = WM_MOUSEWHEEL || wParam = WM_MOUSEHWHEEL) {
				; Mouse wheel has no up event
				vk := HH_MOUSE_WPARAM_LOOKUP[wParam]
				; event = 1 for up, -1 for down
				; wheel vector is stored as signed. For now, just look at 2`s compliment bit to see if negative. Could be >1 tick though? Do we care?
				if (this.IsBitSet(mouseData,23)){
					event := 1
				} else {
					event := -1
				}
			} else if (wParam = WM_XBUTTONDOWN || wParam = WM_XBUTTONUP ){
				; Bit 18 identifies XButton 1/2 instead of a unique wParam
				if (wParam = WM_XBUTTONUP){
					debug := "me"
				}
				vk := this.IsBitSet(mouseData,18) + 4
				event := (wParam = WM_XBUTTONDOWN)
			} else {
				; Only down left
				event := 1
			}
			;tooltip % "type: " HH_INPUT_TYPES[HH_TYPE_M] "`ncode: " vk "`nevent: " event
			if (this._ProcessInput({type: HH_TYPE_M, input: { vk: vk}, event: event})){
				; Return 1 to block this input
				; ToDo: call _ProcessInput via another thread? We only have 300ms to return 1 else it wont get blocked?
				return 1
			}
		} else if (wParam != 0x200){
			debug := "here"
		}
		Return this._CallNextHookEx(nCode, wParam, lParam)
	}
	
	IsBitSet(n,bit){
		return ( (n & ( 1 << (bit-1) ) ) != 0)
		/*
		; Create a number with just the bit we want set to 1
		mask := 1 << (bit-1)
		; Bitwise AND
		res := n & mask
		; If bit was set, will contain a number, else will be empty
		return (res != 0)
		*/
	}
	
	/*
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

	*/

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

	; https://msdn.microsoft.com/en-us/library/windows/desktop/ms646307(v=vs.85).aspx
	; scan code is translated into a virtual-key code that does not distinguish between left- and right-hand keys
	_MapVirtualKeyEx(nCode, uMapType := 1){ ; MAPVK_VSC_TO_VK
		; Get locale
		static dwhkl := DllCall("GetKeyboardLayout", "uint", 0)
		
		ret := 0
		; MAPVK_VSC_TO_VK - The uCode parameter is a scan code and is translated into a virtual-key code
		; Check cache
		if (!this[this._MapTypes[uMapType]][nCode]){
			; Populate cache
			ret := DllCall("MapVirtualKeyEx", "Uint", nCode, "Uint", uMapType, "Ptr", dwhkl, "Uint")
			if (ret = ""){
				ret := 0
			}
			this[this._MapTypes[uMapType]][nCode] := ret
		} else {
			; cache hit
			ret := this[this._MapTypes[uMapType]][nCode]
		}
		; Return result
		return ret
	}
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

; _BindCallback by GeekDude
_BindCallback(Params*)
{
    if IsObject(Params)
    {
        this := {}
        this.Function := Params[1]
        this.Options := Params[2]
        this.ParamCount := Params[3]
        Params.Remove(1, 3)
        this.Params := Params
        if (this.ParamCount == "")
            this.ParamCount := IsFunc(this.Function)-1 - Floor(Params.MaxIndex())
        return RegisterCallback(A_ThisFunc, this.Options, this.ParamCount, Object(this))
    }
    else
    {
        this := Object(A_EventInfo)
        MyParams := [this.Params*]
        Loop, % this.ParamCount
            MyParams.Insert(NumGet(Params+0, (A_Index-1)*A_PtrSize))
        return this.Function.(MyParams*)
    }
}
