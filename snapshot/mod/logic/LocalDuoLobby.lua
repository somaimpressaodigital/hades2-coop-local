local Players = ModRequire "CoopPlayers.lua"
local Context = ModRequire "HeroContext.lua"
local Native = ModRequire "HeroContextNative.lua"
local Control = ModRequire "CoopControl.lua"
local HeroEx = ModRequire "HeroEx.lua"
local Config = (ModRequire "../config.lua").LocalDuo
local PhysicalInput = ModRequire "LocalDuoInput.lua"
local Lobby = {}
local Character=ModRequire "LocalDuoCharacter.lua"
local Mirror=ModRequire "LocalDuoMirror.lua"
local PersonalWeapons=ModRequire "LocalDuoPersonalWeaponSelections.lua"
-- Eager main-init load: native ModRequire cannot first compile on an actor coroutine.
local ArcanaCoop=ModRequire "LocalDuoArcanaCoop.lua"
local inputSession = 0
local inputErrorReported = false -- One diagnostic per module lifetime, never per-frame.
local Group = "Combat_Menu_TraitTray"
local Labels = { WeaponStaffSwing="Bast\195\163o", WeaponDagger="L\195\162minas irm\195\163s", WeaponTorch="Chamas umbrais",
    WeaponAxe="Machado lunar", WeaponLob="Cr\195\162nio arg\195\170nteo", WeaponSuit="Manto negro" }
local Icons = { WeaponStaffSwing="Staff", WeaponDagger="Dagger", WeaponTorch="Torch",
    WeaponAxe="Axe", WeaponLob="Lob", WeaponSuit="Suit" }
local Colors = {{100,160,255,255},{205,135,255,255}}

function Lobby.IsWeaponAvailable(name)
    return Config.UnlockAllWeapons or name == WeaponSets.HeroPrimaryWeapons[1] or GameState.WeaponsUnlocked[name]
end

function Lobby.UnlockStartingWeapons()
    if not Config.UnlockAllWeapons then return end
    GameState.WeaponsUnlocked = GameState.WeaponsUnlocked or {}
    for _, name in ipairs(WeaponSets.HeroPrimaryWeapons) do
        GameState.WeaponsUnlocked[name] = true
        local data = WeaponData[name]
        if data and data.DummyTraitName then GameState.WeaponsUnlocked[data.DummyTraitName] = true end
    end
end
function Lobby.GetEligibleWeapons()
    local choices={};local seen={}
    for _,name in ipairs(WeaponSets.HeroPrimaryWeapons) do
        if not seen[name]and Labels[name]and Icons[name]and WeaponData[name]and Lobby.IsWeaponAvailable(name) then choices[#choices+1]=name;seen[name]=true end
    end
    return choices
end
function Lobby.IsDifficultyAvailable()
    if Config.DifficultyFromStart then return true end
    return IsGameStateEligible({}, { NamedRequirements={"ShrineUnlocked"} })
end
local function AddText(screen,key,text,x,y,size,color)
    local component=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=x,Y=y})
    screen.Components[key]=component
    CreateTextBox({Id=component.Id,Text=text,Font=size and size>=30 and "P22UndergroundSCMedium" or "LatoMedium",FontSize=size or 24,
        Color=color or Color.White,Width=(key=="Title" or key=="Help") and 1800 or 660,Justification="Center"})
    return component
end
local function AddButton(screen,key,text,x,y,callback,player,weapon)
    local button=CreateScreenComponent({Name="ButtonDefault",Group=Group,X=x,Y=y,Scale=0.8})
    button.OnPressedFunctionName=callback
    button.LocalDuoPlayer=player
    button.LocalDuoWeapon=weapon
    screen.Components[key]=button
    CreateTextBox({Id=button.Id,Text=text,Font="LatoMedium",FontSize=weapon and 19 or (key=="Difficulty" and 17 or 18),
        OffsetX=weapon and 22 or 0,Width=weapon and 205 or 230,Color=Color.White,Justification="Center"})
    if weapon then
        SetScaleX({Id=button.Id,Fraction=1.05})
        SetScaleY({Id=button.Id,Fraction=1.05})
    end
    return button
end
local function Close(screen)
    if screen.Closing then return end
    CloseScreenButton(screen)
    notifyExistingWaiters("ScreenInput"..screen.Name)
end

local mouseScopes=setmetatable({},{__mode='k'})
local function CanUseJ1Mouse(screen,component)
    if type(screen)~='table' or type(component)~='table' or type(screen.Components)~='table' or type(screen.Choices)~='table'
        or screen.Binding or screen.Closing or screen.MirrorPlayer
        or LocalDuoCoopModeActive~=true or screen.Name~='LocalDuoPreparation'
        or not ActiveScreens or ActiveScreens[screen.Name]~=screen or component.LocalDuoPlayer~=1 then return false end
    local current=Control.Schemas and Control.Schemas.Current
    local schema=current and current[1]
    local run=CurrentRun;local map=MapState;local hero=Players.GetHero(1)
    if not schema or schema.Device~='Keyboard' or not run or not run.CurrentRoom or not map or not hero
        or hero.IsDead or not hero.ObjectId or hero==Players.GetHero(2) then return false end
    local pin=mouseScopes[screen]
    if not pin then
        pin={Run=run,Room=run.CurrentRoom,Map=map,Hero=hero,Actor=hero.ObjectId,Current=current,Schema=schema}
        mouseScopes[screen]=pin
    end
    if run~=pin.Run or run.CurrentRoom~=pin.Room or map~=pin.Map or hero~=pin.Hero or hero.ObjectId~=pin.Actor
        or current~=pin.Current or schema~=pin.Schema then return false end
    local callback=component.OnPressedFunctionName
    if callback=='LocalDuoChooseWeapon' then
        local weapon=component.LocalDuoWeapon
        if type(weapon)~='string' or screen.Components['P1'..weapon]~=component then return false end
        local listed=false;for _,name in ipairs(screen.Choices)do if name==weapon then listed=true;break end end
        local ok,available=pcall(Lobby.IsWeaponAvailable,weapon)
        return listed and ok and available==true
    end
    local key=callback=='LocalDuoOpenUpgrades' and 'Upgrades1'
        or callback=='LocalDuoOpenAspects' and 'Aspects1'
        or callback=='LocalDuoReadyPlayer' and 'Ready1'
    return key~=nil and screen.Components[key]==component
end
local function NativeButtonAllowed(screen,button)
    -- Internal per-player input dispatch passes owner args without a native component.
    -- Engine HandleScreenInput passes the actual registered component (UILogic931).
    if type(button)~='table' then return false end
    if button.OnPressedFunctionName==nil then return true end
    return CanUseJ1Mouse(screen,button)
end

function Lobby.Render(screen)
    if screen.ArcanaCoop then return ArcanaCoop.Render(screen) end
    if screen.MirrorPlayer then return Mirror.Render(screen) end
    if screen.Binding then
        Control.SwitchControlForMenu(1)
        SetConfigOption({Name="AllowControlHotSwap",Value=true})
        ModifyTextBox({Id=screen.Components.Title.Id,Text="JOGADOR "..screen.BindPlayer..": CONFIRME COM SEU CONTROLE"})
        ModifyTextBox({Id=screen.Components.Help.Id,Text=screen.BindPlayer==1
            and "Pressione confirmar no primeiro controle" or "Confirme agora com o OUTRO controle"})
        ModifyTextBox({Id=screen.Components.Start.Id,Text="Confirmar controle "..screen.BindPlayer})
    else
        Control.ResetAllPlayers("Current")
        SetConfigOption({Name="AllowControlHotSwap",Value=false})
        DisableGamepadCursor(screen.Name)
        ModifyTextBox({Id=screen.Components.Title.Id,Text="ARSENAL DA NOITE"})
        ModifyTextBox({Id=screen.Components.Help.Id,Text=""})
        local action=screen.Args.RestartRoom and "Reiniciar fase" or (screen.ResumeRun and "Continuar corrida" or "Iniciar corrida")
        ModifyTextBox({Id=screen.Components.Start.Id,Text=action})
    end
    for player=1,2 do
        local focus=screen.Focus[player]
        local description=Labels[screen.Selected[player]] or screen.Selected[player]
        if focus==#screen.Choices+1 then description="Melhorias / Arcanos"
        elseif focus==#screen.Choices+2 then description="Aspectos da arma"
        elseif focus==#screen.Choices+3 then description="Dificuldade / Juramento"
        elseif focus==#screen.Choices+4 then description="Pronto para jogar" end
        local hero=Players.GetHero(player)
        local character=Character.Name(player)
        if screen.Components["CharacterPortrait"..player] then
            SetAnimation({DestinationId=screen.Components["CharacterPortrait"..player].Id,
                Name=character=="Zagreus" and "LocalDuoPortraitZagreus" or "LocalDuoPortraitMelinoe"})
        end
        if screen.Components["Heading"..player] then
            ModifyTextBox({Id=screen.Components["Heading"..player].Id,Text="JOGADOR "..player.."  -  "..
                (character=="Zagreus" and "ZAGREUS" or "MELINO\195\139")})
            ModifyTextBox({Id=screen.Components["Upgrades"..player].Id,
                Text="Arcanos e melhorias"})
        end
        ModifyTextBox({Id=screen.Components["Status"..player].Id,
            Text=hero and hero.IsDead and "CA\195\141DO \226\128\148 O PARCEIRO PODE CONTINUAR"
                or (screen.Ready[player] and "PRONTO PARA PARTIR" or description),Color=Colors[player]})
        SetAnimation({DestinationId=screen.Components["Portrait"..player].Id,
            Name="GUI\\Screens\\WeaponShop\\Icon-"..Icons[screen.Selected[player]]})
        for _,name in ipairs(screen.Choices) do
            local key="P"..player..name
            ModifyTextBox({Id=screen.Components[key].Id,Color=screen.Selected[player]==name and Colors[player] or Color.White})
            SetColor({Id=screen.Components[key].Id,Color=screen.Selected[player]==name and Colors[player] or {180,180,195,255}})
            SetAlpha({Id=screen.Components[key].Id,Fraction=screen.Selected[player]==name and 1.0 or 0.65})
            UseableOff({Id=screen.Components[key].Id})
        end
        if screen.Components["Ready"..player] then
            ModifyTextBox({Id=screen.Components["Ready"..player].Id,
                Text=screen.Ready[player] and "PRONTO" or "Confirmar escolha",Color=Colors[player]})
        end
        for _,entry in ipairs({{"Upgrades",#screen.Choices+1},{"Aspects",#screen.Choices+2},{"Ready",#screen.Choices+4}})do
            local button=screen.Components[entry[1]..player]
            if button then
                local active=focus==entry[2] or (entry[1]=="Ready" and screen.Ready[player])
                SetColor({Id=button.Id,Color=active and Colors[player] or {180,180,195,255}})
                SetAlpha({Id=button.Id,Fraction=active and 1 or 0.7})
            end
        end
    end
    if not screen.Binding then
        -- The single cursor belongs only to the current J1 keyboard/mouse role.
        -- J2, shared actions and unavailable weapons remain controlled by owner input.
        for _,component in pairs(screen.Components) do
            if component.OnPressedFunctionName then
                if CanUseJ1Mouse(screen,component) then UseableOn({Id=component.Id})
                else UseableOff({Id=component.Id}) end
            end
        end
    end
    -- Bounded existing-log diagnostic, Profile3 and this current Lua screen only.
    do
        local scoped=screen.Name=='LocalDuoPreparation' and ActiveScreens and ActiveScreens[screen.Name]==screen
            and LocalDuoCoopModeActive==true and CurrentRun and MapState
        local tested,profile=false,false
        if scoped then tested,profile=pcall(function()return (ModRequire 'LocalDuoRenderProbe.lua').IsTestProfile()end) end
        if tested and profile==true then
            local ready=screen.Components.Ready1
            local ok,allowed=pcall(CanUseJ1Mouse,screen,ready)
            local function queried(fn,args)
                if type(fn)~='function' then return 'unavailable' end
                local good,value=pcall(fn,args)
                if not good then return 'error:'..tostring(value) end
                return type(value)=='boolean' and tostring(value) or 'unavailable:'..type(value)
            end
            local usable=ready and queried(IsUseable,{Id=ready.Id}) or 'unavailable:Ready1'
            local current=Control.Schemas and Control.Schemas.Current;local schema=current and current[1]
            local hero=Players.GetHero(1);local pin=mouseScopes[screen];local last=screen.PreviousInput and screen.PreviousInput[1]
            local function same(key,value)return pin and tostring(pin[key]==value) or 'unavailable:pin' end
            local text='[LOCAL_DUO_READY_DIAG] Phase=render Profile=Profile3 Provenance=actualLuaRender'
                ..' CanUse='..(ok and tostring(allowed) or ('error:'..tostring(allowed)))..' IsUseable='..usable
                ..' ReadyId='..tostring(ready and ready.Id)..' ReadyOwner='..tostring(ready and ready.LocalDuoPlayer)
                ..' ReadyCallback='..tostring(ready and ready.OnPressedFunctionName)..' Binding='..tostring(screen.Binding)
                ..' Closing='..tostring(screen.Closing)..' Mirror='..tostring(screen.MirrorPlayer)
                ..' ActiveScreenMatch='..tostring(ActiveScreens[screen.Name]==screen)..' Role='..tostring(schema and schema.Device)
                ..' UseMouse='..queried(GetConfigOptionValue,{Name='UseMouse'})
                ..' LastInputConnected='..tostring(last and last.Connected)..' LastInputFocused='..tostring(last and last.Focused)
                ..' LastInputConfirm='..tostring(last and last.Confirm)..' InputInitialized='..tostring(screen.InputInitialized and screen.InputInitialized[1])
                ..' Ready1='..tostring(screen.Ready[1])..' Ready2='..tostring(screen.Ready[2])
                ..' PinPresent='..tostring(pin~=nil)..' RunMatch='..same('Run',CurrentRun)..' RoomMatch='..same('Room',CurrentRun.CurrentRoom)
                ..' MapMatch='..same('Map',MapState)..' HeroMatch='..same('Hero',hero)..' ActorMatch='..same('Actor',hero and hero.ObjectId)
                ..' CurrentSchemasMatch='..same('Current',current)..' SchemaMatch='..same('Schema',schema)
            text=text:gsub('%c','_')
            Lobby.MouseDiagnosticStates=Lobby.MouseDiagnosticStates or setmetatable({},{__mode='k'})
            if Lobby.MouseDiagnosticStates[screen]~=text then
                Lobby.MouseDiagnosticStates[screen]=text
                if type(DebugPrint)=='function' then pcall(DebugPrint,{Text=text})
                elseif type(Log)=='function' then pcall(Log,text) end
            end
        end
    end
end

function LocalDuoChooseWeapon(screen,button)
    if screen.Binding or not NativeButtonAllowed(screen,button) then return end
    local player=button.LocalDuoPlayer
    screen.Selected[player]=button.LocalDuoWeapon
    screen.Ready[player]=false
    for i,name in ipairs(screen.Choices) do if name==button.LocalDuoWeapon then screen.Focus[player]=i end end
    Lobby.Render(screen)
end
function LocalDuoReturnToHub(screen) screen.StartRun=false;Close(screen) end
function LocalDuoChooseDifficulty(screen)
    if screen.Binding or not Lobby.IsDifficultyAvailable() then return end
    screen.OpenDifficulty=true;Close(screen)
end
function LocalDuoOpenUpgrades(screen,button)
    if screen.Binding or not NativeButtonAllowed(screen,button) then return end
    screen.OpenUpgrades=button.LocalDuoPlayer;Close(screen)
end
function LocalDuoOpenAspects(screen,button)
    if screen.Binding or screen.Closing or not NativeButtonAllowed(screen,button) then return end
    local player=button.LocalDuoPlayer
    if player~=1 and player~=2 then return end
    local hero=Players.GetHero(player)
    if not hero or hero.IsDead then return end
    if not PersonalWeapons.Ensure() or not PersonalWeapons.IsActive() then
        ModifyTextBox({Id=screen.Components.Help.Id,Text="Aspectos pessoais: Perfil 3 em coop"});return
    end
    local weapon=screen.Selected[player]
    if type(HasAnyAspectUnlocked)~="function" then
        ModifyTextBox({Id=screen.Components.Help.Id,Text="Consulta de aspectos indisponível"});return
    end
    -- Same progression gate as stock UseWeaponKit; do not grant/equip an aspect.
    if not HasAnyAspectUnlocked(weapon) then
        ModifyTextBox({Id=screen.Components.Help.Id,Text="J"..player..": desbloqueie os aspectos desta arma para acessá-los"});return
    end
    screen.OpenAspects={Player=player,Hero=hero,Actor=hero.ObjectId,Run=CurrentRun,Room=CurrentRun.CurrentRoom,Weapon=screen.Selected[player]}
    Close(screen)
end

function LocalDuoReadyPlayer(screen,button)
    -- Record actual function entry/outcome before existing guards; never invoke a callback.
    do
        local scoped=screen and screen.Name=='LocalDuoPreparation' and ActiveScreens and ActiveScreens[screen.Name]==screen
            and LocalDuoCoopModeActive==true and CurrentRun and MapState
        local tested,profile=false,false
        if scoped then tested,profile=pcall(function()return (ModRequire 'LocalDuoRenderProbe.lua').IsTestProfile()end) end
        if tested and profile==true then
            local ok,allowed=pcall(NativeButtonAllowed,screen,button)
            local text='[LOCAL_DUO_READY_DIAG] Phase=callback-entry Profile=Profile3 Provenance=actualLocalDuoReadyPlayerEntry'
                ..' Owner='..tostring(type(button)=='table' and button.LocalDuoPlayer or nil)
                ..' CallbackMetadata='..tostring(type(button)=='table' and button.OnPressedFunctionName or nil)
                ..' RegisteredReady1='..tostring(type(screen.Components)=='table' and screen.Components.Ready1==button)
                ..' NativeButtonAllowed='..(ok and tostring(allowed) or ('error:'..tostring(allowed)))
                ..' Binding='..tostring(screen.Binding)..' Closing='..tostring(screen.Closing)
                ..' BeforeReady1='..tostring(screen.Ready and screen.Ready[1])..' BeforeReady2='..tostring(screen.Ready and screen.Ready[2])
                ..' ClickOriginVerified=false'
            text=text:gsub('%c','_')
            Lobby.MouseCallbackDiagnosticStates=Lobby.MouseCallbackDiagnosticStates or setmetatable({},{__mode='k'})
            if Lobby.MouseCallbackDiagnosticStates[screen]~=text then
                Lobby.MouseCallbackDiagnosticStates[screen]=text
                if type(DebugPrint)=='function' then pcall(DebugPrint,{Text=text})
                elseif type(Log)=='function' then pcall(Log,text) end
            end
        end
    end
    if screen.Binding or not NativeButtonAllowed(screen,button) then return end
    screen.Ready[button.LocalDuoPlayer]=true
    Lobby.Render(screen)
    if screen.Ready[1] and screen.Ready[2] then screen.StartRun=true;Close(screen) end
end
function LocalDuoConfirmPreparation(screen)
    if screen.Binding then
        local controller=CoopGetPlayerGamepad(1)
        if GetConfigOptionValue({Name="UseMouse"}) or controller<0 or controller>=5 then
            ModifyTextBox({Id=screen.Components.Help.Id,Text="Confirme usando um controle conectado"});return
        end
        if screen.BindPlayer==2 and controller==screen.Controllers[1] then
            ModifyTextBox({Id=screen.Components.Help.Id,Text="Use o segundo controle; este j\195\161 pertence ao jogador 1"});return
        end
        screen.Controllers[screen.BindPlayer]=controller
        if screen.BindPlayer==1 then screen.BindPlayer=2
        else
            local schema={{Device="Gamepad",ControllerId=screen.Controllers[1]},
                {Device="Gamepad",ControllerId=screen.Controllers[2]}}
            Control.Schemas.UserDefined=DeepCopyTable(schema)
            Control.Schemas.Current=DeepCopyTable(schema)
            SetTempRuntimeData("TN_Coop:control",schema)
            screen.Args.ControllersConfirmed=true
            screen.Binding=false
        end
        Lobby.Render(screen);return
    end
    if screen.Ready[1] and screen.Ready[2] then screen.StartRun=true;Close(screen)
    else ModifyTextBox({Id=screen.Components.Help.Id,Text="Cada jogador deve confirmar PRONTO no pr\195\179prio painel"}) end
end

local ConfirmH2Equipment = ModRequire "LocalDuoConfirmH2Equipment.lua"
Lobby.ConfirmH2Equipment = ConfirmH2Equipment.New{Game=_G,Players=Players,Context=Context}

function Lobby.ApplyWeapons(selected,confirmH2Equipment,onlyPlayer)
    for player=1,2 do
        if not Players.GetHero(player) or not Lobby.IsWeaponAvailable(selected[player]) then return false end
        local hero=Players.GetHero(player)
        if hero.LocalDuoOriginalActor==hero.ObjectId and hero.LocalDuoUsesLegacySwordMechanics~=true
            and type(confirmH2Equipment or Lobby.ConfirmH2Equipment)~='function' then return false end
    end
    for player=1,2 do
        local hero=Players.GetHero(player)
        if (not onlyPlayer or onlyPlayer==player)and not hero.IsDead then Context.RunWithHeroContextAwait(hero,function()
            if hero.LocalDuoUsesLegacySwordMechanics~=true then
                local reskin=hero.LocalDuoOriginalActor==hero.ObjectId
                local actor=hero.ObjectId
                local health,maxHealth,mana,maxMana=hero.Health,hero.MaxHealth,hero.Mana,hero.MaxMana
                local reserveMana,reserveHealth=hero.ReserveManaSources,hero.ReserveHealthSources
                local traits,traitDictionary=hero.Traits,hero.TraitDictionary
                local ok,why=pcall(function()
                    if UnequipWeaponUpgrade then UnequipWeaponUpgrade() end
                    EquipPlayerWeapon(WeaponData[selected[player]],{SkipPresentation=true,LoadPackages=true})
                    EquipWeaponUpgrade(hero,{SkipNewTraitHighlight=true,SkipUIUpdate=true})
                    if reskin then
                        -- Only the five proven legacy Sword kit names, on this exact actor.
                        local legacyNames={'LocalDuoH1_SwordWeapon','LocalDuoH1_SwordWeapon2',
                            'LocalDuoH1_SwordWeapon3','LocalDuoH1_SwordWeaponDash','LocalDuoH1_SwordParry'}
                        local map=MapState
                        local equipped=map and map.EquippedWeapons
                        assert(type(hero.Weapons)=='table'and type(equipped)=='table','Owned equipment bookkeeping unavailable')
                        local removed={}
                        for _,name in ipairs(legacyNames)do
                            if hero.Weapons[name]or equipped[name]then
                                assert(Players.GetHero(player)==hero and hero.ObjectId==actor
                                    and CurrentRun.Hero==hero and MapState==map and map.EquippedWeapons==equipped,
                                    'Legacy cleanup actor/context changed; conversion incomplete')
                                local done,failure=pcall(UnequipWeapon,{DestinationId=actor,Name=name,UnloadPackages=false})
                                assert(done and failure~=false,'Legacy cleanup failed/uncertain: '..name
                                    ..' after '..table.concat(removed,',')..'; flags retained')
                                assert(Players.GetHero(player)==hero and hero.ObjectId==actor
                                    and CurrentRun.Hero==hero and MapState==map and map.EquippedWeapons==equipped,
                                    'Legacy cleanup changed scope after native call; conversion incomplete')
                                hero.Weapons[name]=nil;equipped[name]=nil
                                removed[#removed+1]=name
                            end
                        end
                    end
                    if reskin then
                        local verify=confirmH2Equipment or Lobby.ConfirmH2Equipment
                        assert(Players.GetHero(player)==hero and hero.ObjectId==actor
                            and verify(hero,selected[player],player)==true,
                            'H2 equipment not confirmed for reskin owner; legacy flags retained')
                        assert(Players.GetHero(player)==hero and hero.ObjectId==actor,'Reskin actor changed during verification')
                        hero.LocalDuoUsesLegacySwordMechanics=false
                        hero.LocalDuoOriginalSword=nil
                    end
                end)
                if reskin then
                    -- Stock EquipPlayerWeapon calls RefillMana. Preserve actor-transfer resources.
                    hero.Health=health;hero.MaxHealth=maxHealth;hero.Mana=mana;hero.MaxMana=maxMana
                    hero.ReserveManaSources=reserveMana;hero.ReserveHealthSources=reserveHealth
                    -- Keep outer mutable build-table references while retaining native content updates.
                    if traits and hero.Traits~=traits then
                        for k in pairs(traits)do traits[k]=nil end
                        for k,v in pairs(hero.Traits or{})do traits[k]=v end
                        hero.Traits=traits
                    end
                    if traitDictionary and hero.TraitDictionary~=traitDictionary then
                        for k in pairs(traitDictionary)do traitDictionary[k]=nil end
                        for k,v in pairs(hero.TraitDictionary or{})do traitDictionary[k]=v end
                        hero.TraitDictionary=traitDictionary
                    end
                end
                if not ok then error(why,0) end
            end
            Character.Apply(player,hero)
        end) end
    end
    if PersonalWeapons.IsActive() then
        for player=1,2 do if not onlyPlayer or onlyPlayer==player then PersonalWeapons.Get(player).PrimaryWeaponName=selected[player]end end
    elseif not onlyPlayer or onlyPlayer==1 then GameState.PrimaryWeaponName=selected[1] end
    GameState.LocalDuoWeapons={selected[1],selected[2]}
    return true
end

function Lobby.HandlePlayerInput(screen,player,input)
    if screen.ArcanaCoop then return ArcanaCoop.HandleInput(screen,player,input) end
    if screen.MirrorPlayer then return Mirror.HandleInput(screen,player,input) end
    if screen.Binding or screen.Closing then return end
    local hero=Players.GetHero(player)
    if hero and hero.IsDead then return end
    local previous=screen.PreviousInput[player] or {}
    if player==1 and Character.Name(1)~=Character.Name(2) and input.Character and not previous.Character then
        Character.Swap(Players.GetHero(Character.Name(1)=="Melinoe" and 1 or 2))
        screen.Selected[1],screen.Selected[2]=screen.Selected[2],screen.Selected[1]
        screen.Focus[1],screen.Focus[2]=screen.Focus[2],screen.Focus[1]
        screen.Args.SelectedWeapons={screen.Selected[1],screen.Selected[2]}
        GameState.LocalDuoWeapons={screen.Selected[1],screen.Selected[2]}
        Lobby.ApplyWeapons(screen.Selected)
        screen.Ready={false,false}
        for p=1,2 do
            local h=Players.GetHero(p)
            if h then Context.RunWithHeroContextAwait(h,Character.Apply,p,h) end
        end
        Lobby.Render(screen)
    end
    local focus=screen.Focus[player]
    local move
    if input.Right and not previous.Right then
        move=focus<=#screen.Choices and focus%2==1 and 1 or 0
    elseif input.Left and not previous.Left then
        move=focus<=#screen.Choices and focus%2==0 and -1 or 0
    elseif input.Down and not previous.Down then
        move=focus<=#screen.Choices and (focus+2<=#screen.Choices and 2 or (#screen.Choices+1-focus)) or 1
    elseif input.Up and not previous.Up then
        move=focus<=#screen.Choices and (focus>2 and -2 or 0) or -1
    elseif not (input.Right or input.Left or input.Down or input.Up) then
        move=(input.Next and not previous.Next and 1) or (input.Previous and not previous.Previous and -1)
    end
    if move and move~=0 then
        screen.Focus[player]=(screen.Focus[player]-1+move)%(#screen.Choices+4)+1
        local name=screen.Choices[screen.Focus[player]]
        if name then screen.Selected[player]=name end
        screen.Ready[player]=false
        Lobby.Render(screen)
    end
    if input.Cancel and not previous.Cancel then screen.Ready[player]=false;Lobby.Render(screen) end
    if input.Start and not previous.Start then LocalDuoReturnToHub(screen);return end
    if input.Confirm and not previous.Confirm then
        local focus=screen.Focus[player]
        if focus==#screen.Choices+1 then LocalDuoOpenUpgrades(screen,{LocalDuoPlayer=player})
        elseif focus==#screen.Choices+2 then LocalDuoOpenAspects(screen,{LocalDuoPlayer=player})
        elseif focus==#screen.Choices+3 then LocalDuoChooseDifficulty(screen)
        else LocalDuoReadyPlayer(screen,{LocalDuoPlayer=player}) end
    end
    screen.PreviousInput[player]=input
end

local function ReadPreparationInput(player,schema)
    if schema and schema.Device=="Keyboard" then
        local ok,input=pcall(function()
            if not Lobby.KeyboardRead then
                local keyboard=assert(loadfile("<WORKSPACE>/work/duo-runtime-6/modules/HadesKeyboardRead.lua","t",_G))()
                Lobby.KeyboardRead=keyboard.New{Game=_G,Context=Context,NativeContext=Native,Players=Players,
                    GetSchemas=function()return Control.Schemas.Current end,
                    HasFocus=function()return PhysicalInput.Native.read(-1).Focused==true end}
            end
            return Lobby.KeyboardRead(player,{Focused=PhysicalInput.Native.read(-1).Focused==true,Device="Keyboard"})
        end)
        return ok and input or {Connected=false,Focused=false,Reason=tostring(input)}
    end
    return PhysicalInput.Read(schema and schema.ControllerId or player-1)
end

local function ArcanaSchemasCurrent(screen)
    local schemas=Control.Schemas.Current;local pins=screen.ArcanaInputBindings
    if not pins or type(schemas)~="table"or schemas~=pins.Current or not schemas[1]or not schemas[2]
        or CurrentRun~=screen.Run or CurrentRun.CurrentRoom~=screen.Room or MapState~=screen.Map
        or CurrentHubRoom~=screen.HubRoom or not ActiveScreens or ActiveScreens[screen.Name]~=screen then return false end
    if schemas[2].Device~="Gamepad"or(schemas[1].Device~="Keyboard"and schemas[1].Device~="Gamepad")then return false end
    for p=1,2 do
        local pin=pins[p];local schema=schemas[p];local hero=Players.GetHero(p)
        if not pin or pin.Schema~=schema or pin.Device~=schema.Device or pin.ControllerId~=schema.ControllerId
            or hero~=screen.Heroes[p]or Players.GetPlayerByHero(hero)~=p or hero.IsDead or hero.ObjectId~=screen.Actors[p]then return false end
        if schema.Device=="Gamepad"and(type(schema.ControllerId)~="number"or schema.ControllerId<0
            or schema.ControllerId>254 or schema.ControllerId%1~=0)then return false end
    end
    return not(schemas[1].Device=="Gamepad"and schemas[1].ControllerId==schemas[2].ControllerId)
end
local function ReadArcanaOwnerInput(screen,player,schema)
    if not ArcanaSchemasCurrent(screen)then return {Connected=false,Focused=false}end
    local input=ReadPreparationInput(player,schema)
    if not ArcanaSchemasCurrent(screen)or not input or input.Connected~=true or input.Focused~=true then return {Connected=false,Focused=false}end
    if schema.Device=="Keyboard" then
        -- Existing SDL keyboard state, only the current focused Hades process.
        -- Semantic keyboard ownership/connection above remains authoritative.
        local ok,keys=pcall(PhysicalInput.Native.read,-1)
        if not ok or type(keys)~="table" or keys.Focused~=true then return {Connected=false,Focused=false}end
        input.Upgrade=keys.Upgrade==true;input.Limit=keys.Limit==true
    end
    if schema.Device=="Gamepad"then
        local native=PhysicalInput.Native
        if not native or type(native.devices)~="function"then return {Connected=false,Focused=false}end
        local ok,catalog=pcall(native.devices);if not ok or type(catalog)~="table"then return {Connected=false,Focused=false}end
        local found
        for _,device in ipairs(catalog)do
            if type(device)~="table"then return {Connected=false,Focused=false}end
            if device.Index==schema.ControllerId then
                if found then return {Connected=false,Focused=false}end
                found=device
            end
        end
        if not found or input.Index~=schema.ControllerId or input.Instance==nil or input.Instance~=found.Instance then
            return {Connected=false,Focused=false}
        end
        for other=1,2 do
            if other~=player and Control.Schemas.Current[other].Device=="Gamepad"
                and screen.ArcanaInputBindings[other].Instance==input.Instance then return {Connected=false,Focused=false}end
        end
    end
    local pin=screen.ArcanaInputBindings[player]
    if pin.Instance~=input.Instance then
        local wasReady=screen.Ready[player]
        pin.Instance=input.Instance;screen.InputInitialized[player]=false;screen.PreviousInput[player]={}
        screen.Ready[player]=false
        if wasReady then ArcanaCoop.Render(screen)end
    end
    screen.ArcanaInputSnapshots[player]=input -- Exact validated read ref; not a native event certificate.
    return input
end
local function ArcanaReleased(input)
    return not(input.Confirm or input.Cancel or input.Upgrade or input.Limit or input.Up or input.Down or input.Left or input.Right or input.Next or input.Previous)
end
function Lobby.PollInputs(screen)
    if screen.Binding or screen.Closing or screen.Processing then return end
    for player=1,2 do
        local hero=Players.GetHero(player)
        if hero and hero.IsDead then
            screen.Ready[player]=true
            goto continueInput
        end
        do
        local schema=Control.Schemas.Current[player]
        local input=screen.ArcanaCoop and ReadArcanaOwnerInput(screen,player,schema)or ReadPreparationInput(player,schema)
        local deviceText=schema and schema.Device=="Keyboard" and (input.Connected and "Teclado Hades" or "Teclado indisponível")
            or (input.Connected and (input.Name or "Controle conectado") or "Controle desconectado")
        if screen.Components["Device"..player] and screen.DeviceText[player]~=deviceText then
            screen.DeviceText[player]=deviceText
            ModifyTextBox({Id=screen.Components["Device"..player].Id,Text=deviceText})
        end
        if not input.Connected or not input.Focused then
            screen.InputInitialized[player]=false
            if screen.Ready[player] then
                screen.Ready[player]=false
                if screen.ArcanaCoop then
                    if ArcanaSchemasCurrent(screen)then ArcanaCoop.Render(screen)end
                else Lobby.Render(screen)end
            end
        elseif not screen.InputInitialized[player] then
            screen.InputInitialized[player]=not screen.ArcanaCoop or ArcanaReleased(input)
            screen.PreviousInput[player]=input
        else
            if screen.PreviousInput[player].Instance~=input.Instance then
                screen.PreviousInput[player]=input
                screen.Ready[player]=false
            end
            Lobby.HandlePlayerInput(screen,player,input)
        end
        end
        if screen.Closing then break end
        ::continueInput::
    end
end

function Lobby.StartPlayerInputListeners(screen)
    Lobby.ActiveScreen=screen
    if screen.ArcanaCoop then
        local current=Control.Schemas.Current
        screen.ArcanaInputBindings={Current=current};screen.ArcanaInputSnapshots={}
        for player=1,2 do
            local schema=current and current[player]
            screen.ArcanaInputBindings[player]={Schema=schema,Device=schema and schema.Device,
                ControllerId=schema and schema.ControllerId}
            screen.InputInitialized[player]=false;screen.PreviousInput[player]={}
        end
        -- The stock shared cursor has no sender identity. Only owner readers activate Arcana.
        for _,component in pairs(screen.Components)do
            if(component.LocalDuoPlayer==1 or component.LocalDuoPlayer==2)and component.ArcanaIndex then
                UseableOff({Id=component.Id})
            end
        end
    end
    if PhysicalInput.Error then
        ModifyTextBox({Id=screen.Components.Help.Id,Text="N\195\163o foi poss\195\173vel ler os controles"})
        if not inputErrorReported then
            inputErrorReported=true
            local text="[LOCAL_DUO_INPUT] "..tostring(PhysicalInput.Error)
            if type(DebugPrint)=="function" then pcall(DebugPrint,{Text=text})
            elseif type(Log)=="function" then pcall(Log,text) end
        end
    end
end

function Lobby.UpdateInput()
    local screen=Lobby.ActiveScreen
    if not screen or screen.Closing or screen.Processing then return end
    screen.Processing=true
    thread(function()
        screen.Processing=false
        Lobby.PollInputs(screen)
    end)
end

function Lobby.RestartCurrentRoom()
    local old=CurrentRun.CurrentRoom
    for name in pairs(GameState.ShrineUpgrades) do ShrineUpgradeExtractValues(name) end
    local overrides={ChosenRewardType=old.ChosenRewardType,ForceLootName=old.ForceLootName,
        RewardStoreName=old.RewardStoreName,RoomSetName=old.RoomSetName,Flipped=old.Flipped}
    local fresh=CreateRoom(RoomData[old.Name],{SkipChooseReward=true,RoomOverrides=overrides})
    CurrentRun.CurrentRoom=fresh
    CurrentRun.MapStates[old.Name]=nil
    CurrentRun.ShrineUpgradesCache=DeepCopyTable(GameState.ShrineUpgrades)
    CurrentRun.ShrinePointsCache=GetTotalSpentShrinePoints()
    CurrentRun.StoredHeroLocation=nil
    CurrentRun.StoredHeroAngle=nil
    FadeOut({Duration=0.3,Color=Color.Black});wait(0.3)
    RequestSave({StartNextMap=fresh.Name,SaveName="_Temp"})
    ValidateCheckpoint({Value=true})
    LoadMap({Name=fresh.Name,ResetBinks=true})
end

local function DifficultyChanged(before,after)
    for key,value in pairs(before) do if value~=(after[key] or 0) then return true end end
    for key,value in pairs(after) do if value~=(before[key] or 0) then return true end end
    return false
end

function Lobby.Open(args)
    if LocalDuoCoopModeActive==true then
        -- Preparation now belongs to real hub interactables, never this legacy overlay.
        PersonalWeapons.Ensure()
        return false,"Use as interações nativas do hub"
    end
    args=args or {StartingBiome="F"}
    if IsScreenOpen("LocalDuoPreparation") then return end
    PersonalWeapons.Ensure() -- installed state contract; no temporary global map swap
    Lobby.UnlockStartingWeapons()
    -- Hub UI assets are not resident when a save starts in a combat room.
    LoadPackages({Name="BiomeHub"})
    LoadPackages({Name="Zagreus"})
    local choices=Lobby.GetEligibleWeapons()
    assert(#choices>0,'No supported preparation weapon; no UI or input lease was acquired')
    local remembered=args.SelectedWeapons or GameState.LocalDuoWeapons or {}
    local screen={Name="LocalDuoPreparation",Components={},Choices=choices,Selected={},Focus={1,1},
        Ready={false,false},PreviousInput={{},{}},InputInitialized={},DeviceText={},Controllers={},BindPlayer=1,Args=args,
        Binding=Config.RequireControllerConfirmation==true and not args.ControllersConfirmed,
        ResumeRun=args.ResumeRun,IgnoreOtherScreenInput=true,SkipQuestStatusCheck=true,
        FreezePlayerArgs={DisableTray=true}}
    for player=1,2 do
        local hero=Players.GetHero(player)
        if hero and hero.IsDead then screen.Ready[player]=true end
        local name=remembered[player] or (hero and HeroEx.GetMainWeapon(hero))
        local listed=false;for _,candidate in ipairs(choices)do if candidate==name then listed=true;break end end
        screen.Selected[player]=listed and name or choices[1]
        for i,weapon in ipairs(choices) do if weapon==screen.Selected[player] then screen.Focus[player]=i end end
    end
    HideCombatUI(screen.Name);Control.SwitchControlForMenu(1);OnScreenOpened(screen)
    local cx,cy=ScreenCenterX,ScreenCenterY
    screen.Components.Background=CreateScreenComponent({Name="rectangle01",Group=Group,X=cx,Y=cy,Scale=10})
    SetColor({Id=screen.Components.Background.Id,Color={6,8,17,255}})
    SetAlpha({Id=screen.Components.Background.Id,Fraction=1.0})
    AddText(screen,"Title","",cx,cy-430,36,{224,205,161,255})
    AddText(screen,"Subtitle","ARMAS  -  ARCANOS  -  JURAMENTO",cx,cy-370,17,{150,159,182,255})
    AddText(screen,"Help","",cx,cy+490,17,{170,179,197,255})
    for player=1,2 do
        local x=cx+(player==1 and -480 or 480)
        local frame=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=x,Y=cy+10,Scale=0.95})
        screen.Components["Frame"..player]=frame
        SetAnimation({DestinationId=frame.Id,Name="MythmakerBoxDefault"})
        SetScaleX({Id=frame.Id,Fraction=0.8})
        SetScaleY({Id=frame.Id,Fraction=1.20})
        SetColor({Id=frame.Id,Color=player==1 and {125,165,230,255} or {190,135,235,255}})
        local hero=Players.GetHero(player)
        local name=Character.Name(player)=="Zagreus" and "ZAGREUS" or "MELINO\195\139"
        AddText(screen,"Heading"..player,"JOGADOR "..player.."  -  "..name,x,cy-300,25,Colors[player])
        AddText(screen,"Device"..player,"Detectando controle...",x,cy+378,14,{150,159,182,255})
        AddText(screen,"Status"..player,"",x,cy-255,22,{222,229,240,255})
        screen.Components["CharacterPortrait"..player]=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=x-155,Y=cy-160,Scale=0.16})
        screen.Components["Portrait"..player]=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=x+155,Y=cy-160,Scale=0.85})
        AddText(screen,"WeaponSection"..player,"ARSENAL DESBLOQUEADO",x,cy-37,15,{165,169,185,255})
        for i,name in ipairs(choices) do
            local column=(i-1)%2
            local row=math.floor((i-1)/2)
            local cardX=x-170+340*column
            local cardY=cy+15+77*row
            AddButton(screen,"P"..player..name,Labels[name],cardX,cardY,
                "LocalDuoChooseWeapon",player,name)
            local art=CreateScreenComponent({Name="BlankObstacle",Group=Group,X=cardX-95,Y=cardY,Scale=0.27})
            screen.Components["Art"..player..name]=art
            SetAnimation({DestinationId=art.Id,Name="GUI\\Screens\\WeaponShop\\Icon-"..Icons[name]})
        end
        AddButton(screen,"Upgrades"..player,"Arcanos e melhorias",x+125,cy+225,"LocalDuoOpenUpgrades",player)
        AddButton(screen,"Aspects"..player,"Aspectos",x-125,cy+225,"LocalDuoOpenAspects",player)
        AddButton(screen,"Ready"..player,"Confirmar escolha",x,cy+275,"LocalDuoReadyPlayer",player)
    end
    local fear=GetTotalSpentShrinePoints()
    local difficulty=AddButton(screen,"Difficulty",Lobby.IsDifficultyAvailable() and "Juramento \226\128\148 Medo "..fear
        or "Juramento \226\128\148 bloqueado",cx-340,cy+432,"LocalDuoChooseDifficulty")
    if not Lobby.IsDifficultyAvailable() then UseableOff({Id=difficulty.Id}) end
    AddButton(screen,"Start","",cx+340,cy+432,"LocalDuoConfirmPreparation")
    local back=AddButton(screen,"Back",args.ResumeRun and "Voltar ao jogo" or "Acessar hub",cx,cy+432,"LocalDuoReturnToHub")
    if screen.Binding then back.ControlHotkey="Cancel" end
    SetGamepadNavigation(screen)
    SetConfigOption({Name="ExclusiveInteractGroup",Value=Group})
    Lobby.Render(screen)
    TeleportCursor({DestinationId=screen.Components.Start.Id,ForceUseCheck=true})
    if not screen.Binding then Lobby.StartPlayerInputListeners(screen) end
    HandleScreenInput(screen)
    if Lobby.ActiveScreen==screen then Lobby.ActiveScreen=nil end
    SetConfigOption({Name="ExclusiveInteractGroup",Value=nil})
    Control.ExitMenuControl();ShowCombatUI(screen.Name)
    args.SelectedWeapons=screen.Selected
    if screen.OpenAspects then
        local request=screen.OpenAspects;local hero=Players.GetHero(request.Player)
        assert(PersonalWeapons.Ensure()and PersonalWeapons.IsActive(),'Personal aspect state unavailable')
        assert(CurrentRun==request.Run and CurrentRun.CurrentRoom==request.Room and hero==request.Hero
            and hero.ObjectId==request.Actor and not hero.IsDead,'Aspect owner/room changed')
        if HeroEx.GetMainWeapon(hero)~=request.Weapon then
            assert(Lobby.ApplyWeapons(screen.Selected,nil,request.Player),'Owned H2 root equip failed')
        end
        PersonalWeapons.Get(request.Player).PrimaryWeaponName=request.Weapon
        Context.RunWithHeroContextAwait(hero,function()
            LoadPackages({Name=request.Weapon}) -- stock weapon-kit package; selected H2 root only
            OpenWeaponUpgradeScreen({WeaponName=request.Weapon})
        end)
        assert(CurrentRun==request.Run and CurrentRun.CurrentRoom==request.Room and Players.GetHero(request.Player)==hero
            and hero.ObjectId==request.Actor,'Aspect owner/room changed during stock menu')
        return Lobby.Open(args)
    elseif screen.OpenDifficulty then
        local before=DeepCopyTable(GameState.ShrineUpgrades)
        Context.RunWithHeroContextAwait(Players.GetFirstAliveHero() or Players.GetMainHero(),OpenShrineScreen,{})
        if args.ResumeRun and DifficultyChanged(before,GameState.ShrineUpgrades) then args.RestartRoom=true end
        return Lobby.Open(args)
    elseif screen.OpenUpgrades then
        ArcanaCoop.Open(Lobby,args)
        return Lobby.Open(args)
    end
    if screen.StartRun and Lobby.ApplyWeapons(screen.Selected) then
        if args.ResumeRun or args.RestartRoom then CurrentRun.LocalDuoPreparationCompleted=true
        else LocalDuoPreparationStartsNextRun=true end
        -- LoadMap kills the parent preparation coroutine. Release its guard
        -- before transitioning; its caller cannot run cleanup afterward.
        LocalDuoPreparationPending=false
        if args.RestartRoom then Lobby.RestartCurrentRoom()
        elseif args.ResumeRun then RequestSave({})
        else FadeOut({Duration=0.3,Color=Color.Black});wait(0.3);StartOver(args) end
    end
end

return Lobby
