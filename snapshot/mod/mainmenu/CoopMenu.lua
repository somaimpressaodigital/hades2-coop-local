--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type PlayerDeviceData[]
local SelectedGuiControl = {}
local ReadExplicitPad
local activeSelector
-- Preserve native initial navigation. Coop is selected only by the user's explicit action.

local function TostringPlayerConfiguration(playerId)
    if SelectedGuiControl[playerId].Device == "Keyboard" then
        return GetDisplayName { Text = "CoopMenu_KbAndMouse" }
    else
        local index = SelectedGuiControl[playerId].ControllerId
        --return "Gamepad " .. index .. " - " .. CoopGetGamepadName(index)
        local template = GetDisplayName { Text = "CoopMenu_Gamepad", ParamValue = index }
        return string.gsub(template, "{(%w+)}", { ParamValue = index } )
    end
end

-- We need set controller id for the keyboard player to avoid crashes
local function AssingKeyboardPlayerFreeControllerId()
    local kbPlayerData = SelectedGuiControl[1]

    if kbPlayerData.Device ~= "Keyboard" then
        return
    end

    if SelectedGuiControl[2].ControllerId == 4 then
        kbPlayerData.ControllerId = 3
    else
        kbPlayerData.ControllerId = 4
    end
end

local MENU_STATE = {
    START = 0;
    PLAYER_ONE_SELECTED = 1,
    PLAYER_TWO_SELECTED = 2,
    INVALID_STATE_SECOND_KEYBOARD = 3,
    INVALID_STATE_SAME_DEVICE = 4,
}

local CURRENT_MENU_STATE

local START_BUTTON_MESSAGES = {
    "Let's play",
    "Go, go, go",
    "Start",
    "Let the Carnage Begin!",
    "Next",
    "Let's Roll!",
    "Game On!",
    "Adventure Awaits",
    "Initiate Chaos!",
    "Begin the Hunt!",
    "It's Time to Kick Gum and Chew Ass",
    "Fus Ro Dah!",
    "Let's Cause Trouble",
    "Press Start to Change Everything"
}

local function GetRelativeScreenPath(filename)
    local modPath = GetCurrentModPath()
    local scriptDir = GetScriptDir()
    return scriptDir:sub(#modPath + 2) .. (filename or "ControllerSelectionMenuScreen.sjson")
end

-- Revalidate the event sender against the actual catalog; never infer a keyboard from pad absence.
ReadExplicitPad=function(index)
    local input=LocalDuoPhysicalInput
    if type(index)~='number' or index<0 or index>254 or index%1~=0
        or not input or type(input.devices)~='function' or type(input.read)~='function' then return nil end
    local ok,catalog=pcall(input.devices)
    if not ok or type(catalog)~='table' then return nil end
    local selected
    for _,device in ipairs(catalog)do
        if type(device)~='table' then return nil end
        if device.Index==index then
            if selected or device.Instance==nil then return nil end
            selected=device
        end
    end
    if not selected then return nil end
    local read,raw=pcall(input.read,index)
    if LocalDuoPhysicalInput~=input or not read or type(raw)~='table' or raw.Connected~=true or raw.Focused~=true
        or raw.Index~=index or raw.Instance~=selected.Instance then return nil end
    return {Device='Gamepad',ControllerId=index,NativeInstance=raw.Instance}
end

local function ReadExplicitKeyboard()
    -- Explicit J1 UI role, not a claim of SDL keyboard connection or native focus.
    return {Device='Keyboard',ControllerId=-1}
end

MainMenuAPIAddGamemode("Coop", function(name)
    SetConfigOption { Name = "AllowControlHotSwap", Value = true }
    if CoopHasPlayer(2) then CoopSetPlayerGamepad(2, 5) end
    SetTempRuntimeData("TN_Coop:disabled", false)
    SelectedGuiControl = {}
    -- Show the existing P1/P2 selection even when devices were detected.

    local explicitPicker = true -- normal Coop always uses explicit device selection
    local selectorToken={};activeSelector=selectorToken;local selectorIsOpen=true
    local deviceDisplay;local finalReceiptStates={}
    local menu = CreateMenuScreen()
    menu:CreateBack(0.8)
    menu:CreateBackground("")
    menu:CreateTitleText()
    menu:SetLowerInputBlock(true)

    local message = CreateGUIComponentTextBox(menu)

    menu:AddReflection("mMessageText", message)

    local btn = CreateGUIComponentButton(menu)

    local function SetStage(state)
        CURRENT_MENU_STATE = state

        if state == MENU_STATE.START then
            if deviceDisplay then deviceDisplay:SetText("Escolha um dispositivo para J1") end
            message:SetTextLocalizationKey("CoopMenu_StartMessage")
            btn:SetTextLocalizationKey("CoopMenu_P1Press")
        elseif state == MENU_STATE.PLAYER_ONE_SELECTED then
            local template = GetDisplayName { Text = "CoopMenu_PlayerController" }
            local text = string.gsub(template, "%$(%w+)", { PlayerIndex = 1, Controller = TostringPlayerConfiguration(1) })

            message:SetText(text)
            btn:SetTextLocalizationKey("CoopMenu_P2Press")
        elseif state == MENU_STATE.PLAYER_TWO_SELECTED then
            local template = GetDisplayName { Text = "CoopMenu_PlayerController" }
            local text = string.gsub(template, "%$(%w+)", { PlayerIndex = 1, Controller = TostringPlayerConfiguration(1) })
            local text2 = string.gsub(template, "%$(%w+)", { PlayerIndex = 2, Controller = TostringPlayerConfiguration(2) })
            message:SetText(text .. "   \n" .. text2)
            btn:SetText("INICIAR COOP LOCAL")
        elseif state == MENU_STATE.INVALID_STATE_SECOND_KEYBOARD then
            message:SetTextLocalizationKey("CoopMenu_ErrP1KBOnly")
            btn:SetTextLocalizationKey("CoopMenu_Again")
        elseif state == MENU_STATE.INVALID_STATE_SAME_DEVICE then
            message:SetTextLocalizationKey("CoopMenu_ErrDeviceCollision")
            btn:SetTextLocalizationKey("CoopMenu_Again")
        else
            message:SetText("Error description is missing :D")
            btn:SetTextLocalizationKey("CoopMenu_Again")
        end
    end

    SetStage(MENU_STATE.START)

    -- Actual observed event origin; preview and native current mapping are never senders.
    local originProvider;local originLease;local originSequence;local originHeld={}
    local primaryAction
    local lastArmReason=""
    local armChannels="unavailable"
    local function ReasonText(value)
        return tostring(value):gsub("%c"," "):sub(1,320)
    end
    local function EndOrigin()
        local provider,lease=originProvider,originLease
        originProvider=nil;originLease=nil;originSequence=nil;originHeld={}
        if provider and lease then pcall(provider.End,lease) end
    end
    local function ArmOriginImpl()
        EndOrigin()
        local provider=LocalDuoMenuOrigin
        if type(provider)~='table' or type(provider.Begin)~='function'
            or type(provider.Read)~='function' or type(provider.End)~='function' then
            lastArmReason="Provider="..type(provider).." Begin="..type(type(provider)=="table" and provider.Begin or nil)
                .." Read="..type(type(provider)=="table" and provider.Read or nil).." End="..type(type(provider)=="table" and provider.End or nil)
            return false
        end
        local ok,status=pcall(provider.Begin)
        if not ok or type(status)~='table' then
            lastArmReason=not ok and ("Begin error: "..ReasonText(status)) or ("Begin returned "..type(status))
            return false
        end
        if status.Active~=true or status.WindowChainOwned~=true
            or type(status.Lease)~='number' or status.Lease<=0 or status.Lease%1~=0
            or type(status.Sequence)~='number' or status.Sequence<0 or status.Sequence%1~=0
            or status.NativeGUIActivationProof~=false then
            lastArmReason=ReasonText(status.Reason).." Active="..tostring(status.Active)
                .." WindowChainOwned="..tostring(status.WindowChainOwned)
                .." LeaseType="..type(status.Lease).." SequenceType="..type(status.Sequence)
                .." NativeGUIActivationProof="..tostring(status.NativeGUIActivationProof)
            if type(status.Lease)=='number' then pcall(provider.End,status.Lease) end
            return false
        end
        lastArmReason=""
        armChannels="SDLControllerEventsState="..tostring(status.SDLControllerEventsState)
            .." SDLJoystickEventsState="..tostring(status.SDLJoystickEventsState)
            .." Provenance=actualBeginReturn"
        originProvider=provider;originLease=status.Lease;originSequence=status.Sequence
        return true
    end
    local armFailureReceipts={}
    local function LogOriginFailure(kind,reason)
        local key=kind..":"..reason
        if not armFailureReceipts[key] then
            local ok,wrote=pcall(function()
                if not io or type(io.open)~='function' or type(GetCurrentModPath)~='function' then return false end
                local root=GetCurrentModPath();if type(root)~='string' then return false end
                local file=io.open(root..'/LocalDuo.log','a');if not file then return false end
                local text=('[LOCAL_DUO_MENU_ORIGIN] '..kind..' Reason='..reason
                    ..' NativeGUIActivationProof=false'):gsub('%c',' '):sub(1,1536)
                local written,value=pcall(file.write,file,text..'\n')
                local closed,result=pcall(file.close,file)
                return written and value~=nil and closed and result==true
            end)
            if ok and wrote==true then armFailureReceipts[key]=true end
        end
    end
    local function ArmOrigin()
        local armed=ArmOriginImpl()
        if not armed then LogOriginFailure('ArmFailed',lastArmReason)
        else LogOriginFailure('ArmChannels',armChannels) end
        return armed -- Logging never changes admission, retries or existing lifecycle.
    end
    local function ResetOrigin(text)
        SelectedGuiControl={};SetStage(MENU_STATE.START)
        if deviceDisplay then deviceDisplay:SetText("Confirme com o dispositivo de J1") end
        LogOriginFailure('SelectorReset',text..' PreviousArmReason='..lastArmReason)
        local armed=ArmOrigin()
        if armed then
            message:SetText("Pronto. Solte os botões e confirme com J1.")
        else
            message:SetText("Entrada indisponível. Solte os botões e tente novamente.")
        end
    end
    local function ReadOrigin()
        if not originProvider then
            ResetOrigin("Nenhuma sessão de origem estava ativa.");return nil
        elseif LocalDuoMenuOrigin~=originProvider then
            ResetOrigin("O provider de origem mudou.");return nil
        end
        local ok,status=pcall(originProvider.Read,originLease,originSequence)
        if not ok or type(status)~='table' or status.Active~=true
            or status.Lease~=originLease or status.WindowChainOwned~=true
            or status.NativeGUIActivationProof~=false or type(status.Events)~='table'
            or type(status.Sequence)~='number' or status.Sequence<originSequence
            or status.Sequence%1~=0 then
            ResetOrigin("A sessão de entrada expirou ou o dispositivo/foco mudou. Read: "
                ..ReasonText(not ok and status or type(status)=='table' and status.Reason or type(status)));return nil
        end
        local sequence=originSequence;local readAfter=originSequence;local candidate;local downs=0;local releases=0
        for _,event in ipairs(status.Events)do
            local pad=type(event)=='table' and event.DeviceKind=='Gamepad'
            local keyboard=type(event)=='table' and event.DeviceKind=='Keyboard'
            local mouse=type(event)=='table' and event.DeviceKind=='Mouse'
            if type(event)~='table' or event.Lease~=originLease
                or type(event.Sequence)~='number' or event.Sequence<=sequence or event.Sequence%1~=0
                or event.Sequence>status.Sequence or type(event.Down)~='boolean'
                or type(event.Time)~='number' or event.Time~=event.Time
                or event.NativeGUIActivationProof~=false
                or (not pad and not keyboard and not mouse)
                or (pad and (event.Control~=0 or (event.Provenance~='ActualObservedSDLControllerEvent'
                    and event.Provenance~='ActualObservedSDLButtonStateTransition')
                    or type(event.Index)~='number' or event.Index<0 or event.Index>254 or event.Index%1~=0
                    or type(event.Instance)~='number' or event.Instance<0 or event.Instance%1~=0))
                or ((keyboard or mouse) and (event.Index~=-1 or event.Instance~=-1
                    or event.Provenance~='ActualOwnHadesWindowMessage'))
                or (keyboard and event.Control~=13 and event.Control~=32)
                or (mouse and event.Control~=1) then
                ResetOrigin("Evento de origem inválido.");return nil
            end
            sequence=event.Sequence
            local key=event.DeviceKind..':'..tostring(event.Instance)
            if event.Down then
                downs=downs+1
                local held=originHeld[key] or {}
                if next(held)~=nil then downs=downs+1 end -- same device needs observed release
                held[event.Control]=true;originHeld[key]=held;candidate=event
            else
                releases=releases+1
                local held=originHeld[key]
                if held then held[event.Control]=nil end
            end
        end
        originSequence=sequence -- Consume ALL observed edges, including mouse browsing/releases.
        if sequence~=status.Sequence or downs>1 then
            ResetOrigin("Entradas simultâneas ou repetidas: origem ambígua.");return nil
        end
        if downs~=1 then
            local function channel(value)
                if value==-2 or value==0 or value==1 then return tostring(value) end
                return 'unavailable'
            end
            LogOriginFailure('NoConfirmEvent','Lease='..tostring(originLease)
                ..' SequenceBefore='..tostring(readAfter)..' SequenceAfter='..tostring(status.Sequence)
                ..' EventCount='..tostring(#status.Events)..' DownCount='..tostring(downs)
                ..' ReleaseCount='..tostring(releases)
                ..' SDLControllerEventsState='..channel(status.SDLControllerEventsState)
                ..' SDLJoystickEventsState='..channel(status.SDLJoystickEventsState)
                ..' Provenance=actualReadReturn')
            message:SetText("Solte o botão e confirme novamente.");return nil
        end
        return candidate
    end
    local function ReadMenuControl(event)
        if event.DeviceKind=='Keyboard' or event.DeviceKind=='Mouse' then
            if CURRENT_MENU_STATE~=MENU_STATE.START then return nil,'j2_requires_gamepad' end
            return ReadExplicitKeyboard()
        end
        local actual=ReadExplicitPad(event.Index)
        if not actual or actual.NativeInstance~=event.Instance then return nil,'device_changed' end
        return actual
    end
    local function Dispatch(action)
        local ok,result=pcall(action)
        if not ok then EndOrigin();error(result,0) end
    end
    if explicitPicker then
        local display=CreateGUIComponentTextBox(menu)
        deviceDisplay=display
        menu:AddReflection("mExplicitDevice",display)
    end

    primaryAction=function(event)
        if CURRENT_MENU_STATE == MENU_STATE.START then
            local selected,reason=ReadMenuControl(event)
            if not selected then
                ResetOrigin("O controle que confirmou mudou ou está indisponível.");return
            end
            SelectedGuiControl[1] = selected
            SetStage(MENU_STATE.PLAYER_ONE_SELECTED)
            if explicitPicker then deviceDisplay:SetText("Escolha um dispositivo para J2") end
        elseif CURRENT_MENU_STATE == MENU_STATE.PLAYER_ONE_SELECTED then
            local selected,reason=ReadMenuControl(event)
            if not selected then
                if reason=='j2_requires_gamepad' then
                    message:SetText("J2 precisa confirmar no próprio controle.")
                else ResetOrigin("O segundo controle mudou ou está indisponível.") end
                return
            end
            SelectedGuiControl[2] = selected

            if SelectedGuiControl[2].Device == "Keyboard" then
                SetStage(MENU_STATE.INVALID_STATE_SECOND_KEYBOARD)
            elseif SelectedGuiControl[1].Device == "Gamepad" and
                (SelectedGuiControl[1].ControllerId == SelectedGuiControl[2].ControllerId or SelectedGuiControl[1].NativeInstance == SelectedGuiControl[2].NativeInstance) then
                SetStage(MENU_STATE.INVALID_STATE_SAME_DEVICE)
            else
                SetStage(MENU_STATE.PLAYER_TWO_SELECTED)
            end
        elseif CURRENT_MENU_STATE == MENU_STATE.PLAYER_TWO_SELECTED then
            if event.DeviceKind=='Gamepad' then
                local actual=ReadExplicitPad(event.Index);local assigned=false
                for p=1,2 do
                    local selected=SelectedGuiControl[p]
                    if actual and selected.Device=='Gamepad' and selected.ControllerId==actual.ControllerId
                        and selected.NativeInstance==actual.NativeInstance and event.Instance==actual.NativeInstance then assigned=true end
                end
                if not assigned then ResetOrigin("A confirmação veio de um controle não selecionado.");return end
            elseif SelectedGuiControl[1].Device~='Keyboard' then
                message:SetText("Confirme com um dos controles selecionados.");return
            end
            local phase='entry'
            local function receipt(stage,detail)
                local text='[LOCAL_DUO_MENU_FINAL] Phase='..stage..' Detail='..tostring(detail or '')
                    ..' Provenance=actualFinalCallback ClickOriginVerified=false'
                text=text:gsub('%c','_'):sub(1,1536)
                if finalReceiptStates[stage]==text then return end
                local logged,wrote=pcall(function()
                    if not io or type(io.open)~='function' or type(GetCurrentModPath)~='function' then return false end
                    local root=GetCurrentModPath()
                    if type(root)~='string' then return false end
                    -- Reuse the same existing LocalDuo.log sink as init.lua's local logger.
                    local file=io.open(root..'/LocalDuo.log','a')
                    if not file then return false end
                    local written,value=pcall(file.write,file,text..'\n')
                    local closed,closeResult=pcall(file.close,file)
                    return written and value~=nil and closed and closeResult==true
                end)
                -- Memo suppresses log attempts only; never a native ACK/admission field.
                if logged and wrote==true then finalReceiptStates[stage]=text end
            end
            local function configuration()
                local a,b=SelectedGuiControl[1],SelectedGuiControl[2]
                return 'stage='..tostring(CURRENT_MENU_STATE)..' gamemode='..tostring(name)
                    ..' J1='..tostring(a and a.Device)..':'..tostring(a and a.ControllerId)..':'..tostring(a and a.NativeInstance)
                    ..' J2='..tostring(b and b.Device)..':'..tostring(b and b.ControllerId)..':'..tostring(b and b.NativeInstance)
            end
            receipt('entry',configuration())
            local function finish()
                for p=1,2 do
                    phase='revalidation-J'..p
                    local selected=SelectedGuiControl[p]
                    receipt(phase..'-before','Device='..tostring(selected and selected.Device)..' Index='..tostring(selected and selected.ControllerId)..' Instance='..tostring(selected and selected.NativeInstance))
                    if selected.Device=='Keyboard' and (p~=1 or not ReadExplicitKeyboard()) then
                        receipt(phase..'-reset','Keyboard role refused')
                        SelectedGuiControl={};SetStage(MENU_STATE.START);ArmOrigin()
                        message:SetText("Teclado indisponível. Escolha os dispositivos novamente.");return
                    elseif selected.Device=='Gamepad' then
                        local current=ReadExplicitPad(selected.ControllerId)
                        receipt(phase..'-observed','Returned='..tostring(current~=nil)..' Index='..tostring(current and current.ControllerId)..' Instance='..tostring(current and current.NativeInstance))
                        if not current or current.NativeInstance~=selected.NativeInstance then
                            receipt(phase..'-reset','Actual pad revalidation refused')
                            SelectedGuiControl={};SetStage(MENU_STATE.START);ArmOrigin()
                            message:SetText("Controle desconectado. Escolham os dispositivos novamente.");return
                        end
                    end
                    receipt(phase..'-accepted',configuration())
                end
                phase='temp-gamemode';receipt(phase..'-before',tostring(name))
                SetTempRuntimeData("Gamemode", name)
                receipt(phase..'-after','Existing call returned')
                phase='keyboard-reservation';receipt(phase..'-before',configuration())
                AssingKeyboardPlayerFreeControllerId()
                receipt(phase..'-after',configuration())
                phase='temp-controls';receipt(phase..'-before',configuration())
                SetTempRuntimeData("TN_Coop:control", SelectedGuiControl)
                receipt(phase..'-after','Existing call returned')
                phase='open-profiles';receipt(phase..'-before','Calling existing MainMenuOpenProfiles')
                selectorIsOpen=false
                EndOrigin() -- Close the exact selector observation before the native screen transition.
                local result=MainMenuOpenProfiles()
                receipt(phase..'-after','ResultType='..type(result)..' Result='..tostring(result)..' ProfilesVisibleProof=false')
            end
            local ok,result=pcall(finish)
            if not ok then
                receipt('error','Stage='..phase..' Error='..tostring(result))
                error(result,0) -- Preserve original error value; do not continue/reset or fabricate success.
            end
        else
            SelectedGuiControl={};SetStage(MENU_STATE.START);ArmOrigin()
        end
    end
    btn:AddActivationHandler(function()Dispatch(function()
        local event=ReadOrigin();if event then primaryAction(event) end
    end)end)

    menu:AddReflection("mControllerPress", btn)
    -- Create the primary action before Back, so it is the first selectable
    -- component when native gamepad navigation initializes this screen.
    menu:CreateCancelButton(function()
        selectorIsOpen=false
        EndOrigin()
        SetTempRuntimeData("Gamemode", nil)
        menu:ExitScreen()
    end)
    local layoutPath=GetRelativeScreenPath("ControllerSelectionExplicitDevices.sjson")
    menu:LoadDefenitions(layoutPath)
    if explicitPicker then
        deviceDisplay:SetText("Confirme com o dispositivo de J1")
    end
    if not ArmOrigin() then message:SetText("Entrada indisponível. Solte os botões e tente novamente.") end
    if TeleportCursor then TeleportCursor({ OffsetX=960, OffsetY=650, ForceUseCheck=true }) end
    -- Existing SDL recipe, OFF unless Main's one-shot arm is consumed by the helper.
    -- loadfile avoids the native lazy ModRequire coroutine-stack path.
    local recipePath='<WORKSPACE>/work/integration/autonomous-prejoin/MenuNativeSDL.lua'
    local recipeChunk=loadfile(recipePath,'t',_G)
    if recipeChunk then
        local loaded,recipe=pcall(recipeChunk)
        if loaded and type(recipe)=='table' and type(recipe.Start)=='function' then
            pcall(recipe.Start,{
                GetState=function()return CURRENT_MENU_STATE,SelectedGuiControl end,
                IsCurrent=function()return selectorIsOpen and activeSelector==selectorToken end,
                Rearm=ArmOrigin,
                Bypass=function(controls)
                    assert(selectorIsOpen and activeSelector==selectorToken,'Test selector closed/changed')
                    local pad=assert(LocalDuoTestPad,'SDK pad unavailable')
                    assert(type(controls)=='table' and #controls==2,'Two actual SDK test controls required')
                    for p=1,2 do
                        local selected=assert(controls[p])
                        assert(selected.Device=='Gamepad' and type(pad.testcreate)=='function'
                            and pad.testcreate(p-1)==selected.ControllerId,'SDK slot ownership changed')
                        local raw=pad.read(selected.ControllerId)
                        local actual=ReadExplicitPad(selected.ControllerId)
                        assert(raw.Connected==true and raw.Focused==true and raw.Neutral==true
                            and raw.Index==selected.ControllerId and raw.Instance==selected.NativeInstance
                            and actual and actual.NativeInstance==selected.NativeInstance,'SDK/physical identity or neutrality changed')
                    end
                    assert(controls[1].ControllerId~=controls[2].ControllerId
                        and controls[1].NativeInstance~=controls[2].NativeInstance,'Distinct SDK controls required')
                    message:SetText('TESTE: seletor pulado. Use somente o Perfil 3.')
                    SetTempRuntimeData('TN_Coop:test-selector-result',{NativeInputPass=false,TestSelectorBypassed=true,
                        NativeMenuSequenceObserved=false,SDKVirtual=true,Profile3ManualOnly=true})
                    SetTempRuntimeData('Gamemode',name)
                    SetTempRuntimeData('TN_Coop:control',controls)
                    selectorIsOpen=false;EndOrigin()
                    return MainMenuOpenProfiles()~=false -- Normal profile screen only; no profile is loaded here.
                end,
            })
        end
    end
end)
