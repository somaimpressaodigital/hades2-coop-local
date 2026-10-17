-- Local adaptation: quick loadout, personal rewards, and duo encounter tuning.
local Hook = (ModRequire "../utils/SimpleHook.lua").New()
local Players = ModRequire "../logic/CoopPlayers.lua"
local Context = ModRequire "../logic/HeroContext.lua"
local Control = ModRequire "../logic/CoopControl.lua"
local PersonalWeapons=ModRequire "../logic/LocalDuoPersonalWeaponSelections.lua"
local Prep = ModRequire "../logic/LocalDuoLobby.lua"
local Loot = ModRequire "../logic/loot/LootIndividual.lua"
local Rooms = ModRequire "../logic/LocalDuoRooms.lua"
local Safety = ModRequire "../logic/LocalDuoMenuSafety.lua"
local Diagnostics = ModRequire "../logic/LocalDuoDiagnostics.lua"
local Config = (ModRequire "../config.lua").LocalDuo
local Scaling = ModRequire "../logic/LocalDuoScalingReconcile.lua"
local Events=ModRequire "../logic/Events.lua"
local Fountains=ModRequire "../logic/LocalDuoFountains.lua"
local Rescue=ModRequire "../logic/LocalDuoRescue.lua"
local Character=ModRequire "../logic/LocalDuoCharacter.lua"
local Mirror=ModRequire "../logic/LocalDuoMirror.lua"
local Ally=ModRequire "../logic/LocalDuoAllyTargeting.lua"
local RenderProbe=ModRequire "../logic/LocalDuoRenderProbe.lua"
local OriginalScene=ModRequire "../logic/LocalDuoOriginalScene.lua"
local OriginalBindingTest=ModRequire "../logic/LocalDuoOriginalBindingTest.lua"
local ActionCapture=ModRequire "../logic/LocalDuoActionCapture.lua"
local OperationalBoon=ModRequire "../logic/LocalDuoOperationalBoonRuntime.lua"
function LocalDuoTrySingleVisibleBoonPair(rewards,room,bundle)
    if LocalDuoCoopModeActive~=true or RenderProbe.IsTestProfile()~=true or Players.GetPlayersCount()~=2 then return end
    local runtime=OperationalBoon.Ensure()
    if runtime and runtime.Enabled and runtime.PrepareVisiblePair then
        return runtime:PrepareVisiblePair(rewards,room,bundle)
    end
end
local CentaurModule=ModRequire "../logic/LocalDuoSharedCentaurHeart.lua"
local Centaur=CentaurModule.New{Game=_G,Players=Players,Context=Context,Gate=RenderProbe}
CentaurModule.Runtime=Centaur
local ManaModule=ModRequire "../logic/LocalDuoSharedMaxManaDrop.lua"
local Mana=ManaModule.New{Game=_G,Players=Players,Context=Context,Gate=RenderProbe}
ManaModule.Runtime=Mana
local HealingModule=ModRequire "../logic/LocalDuoSharedHealing.lua"
local Healing=HealingModule.New{Game=_G,Players=Players,Context=Context,Gate=RenderProbe}
local NpcPom=(ModRequire "../logic/LocalDuoNarcissusPersonalPom.lua").New{Game=_G,Players=Players,Context=Context,Gate=RenderProbe}
local audioProbeCounts={}
function Hook.wrap.PlaySound(base,args)
    local result=base(args)
    if args and args.Id and args.Name and (args.Name:find('Zagreus',1,true) or args.Name:find('MelinoeEmotes',1,true))then
        local hero=Players.GetHeroByUnit(args.Id)
        if hero and hero.LocalDuoOriginalActor==hero.ObjectId then
            audioProbeCounts[args.Name]=(audioProbeCounts[args.Name] or 0)+1
            if audioProbeCounts[args.Name]<=4 then
                Diagnostics.Write('originalAudio','actor='..args.Id..' cue='..args.Name..' soundId='..tostring(result))
            end
        end
    end
    return result
end
local recordedAppearanceWrites={}
function Hook.wrap.SetThingProperty(base,args)
    if args and (args.Property=="GrannyTexture" or args.Property=="GrannyModel" or args.Property=="Material") then
        for p=1,2 do
            local hero=Players.GetHero(p)
            if hero and hero.ObjectId==args.DestinationId and hero.LocalDuoCharacter=="Zagreus" then
                local key=tostring(CurrentRun)..":"..p..":"..args.Property..":"..tostring(args.Value)
                if not recordedAppearanceWrites[key] then
                    recordedAppearanceWrites[key]=true
                    Diagnostics.Write("appearanceWrite","J"..p.." id="..hero.ObjectId
                        .." property="..args.Property.." value="..tostring(args.Value)
                        .." caller="..debug.traceback("",2))
                end
            end
        end
    end
    return base(args)
end
function Hook.wrap.TyphonChronosStageTransition(base,typhon,args)
    local chronos=ActiveEnemies and ActiveEnemies[793226]
    if not chronos or chronos.IsDead then
        Diagnostics.Write("typhonTransition","Chronos absent; optional actor transition skipped")
        return
    end
    return base(typhon,args)
end
local preparationShown = false
local preparationRequest
local PollPreparation
function Hook.wrap.DoPatches(base,...)
    local selected=Config.DifficultyFromStart and GameState and DeepCopyTable(GameState.ShrineUpgrades or {})
    local result=table.pack(base(...))
    -- Vanilla clears fear before the story unlock. The duo lobby permits an
    -- early choice without marking story events or boss victories complete.
    if selected then
        GameState.ShrineUpgrades=selected
        GameState.SpentShrinePointsCache=GetTotalSpentShrinePoints()
        for name in pairs(selected)do ShrineUpgradeExtractValues(name)end
    end
    return table.unpack(result,1,result.n)
end
-- Resolve once while the module is loaded. The native current-mod helper
-- inspects the main Lua state and is unsafe inside gameplay callbacks.
local logPath = GetScriptDir() .. "/../LocalDuo.log"
local function Log(message)
    if io and io.open then
        local file = io.open(logPath, "a")
        if file then file:write(message .. "\n"); file:close() end
    end
end

function Hook:InitGameHooks()
    Log("Hooks da adaptaÃ§Ã£o instalados")
    Events.engine:on("tick", Safety.Update)
    Events.engine:on("tick",function() if PollPreparation then PollPreparation() end end)
    Events.engine:on("tick", Prep.UpdateInput)
    Events.engine:on("tick", Diagnostics.Update)
    Events.engine:on("tick", ActionCapture.Update)
    Events.engine:on("tick",function()OriginalBindingTest.Update(Diagnostics.Write)end)
    local lastSceneTime
    Events.engine:on("tick",function()
        -- The scene can only be created behind the Profile3 gate. Do not read
        -- the activeProfile file every frame, particularly during light tests.
        if not SessionMapState or not SessionMapState.LocalDuoOriginalScene then return end
        local now=_worldTimeUnmodified
        if type(now)~="number"then return end
        local delta=lastSceneTime and math.max(0,math.min(now-lastSceneTime,0.1))or 0
        lastSceneTime=now
        local ok,problem=pcall(OriginalScene.Update,delta)
        if not ok then
            if SessionMapState then SessionMapState.LocalDuoOriginalScene=nil end
            Diagnostics.Write("originalVisualError",problem)
        end
    end)
    Diagnostics.Write("session","Independent SDL input; nearest living hero AI; recovery on save load")
    Events.run:on("mapLoaded", function(name)
        if preparationRequest and preparationRequest.Source~=(CurrentHubRoom or (CurrentRun and CurrentRun.CurrentRoom)) then preparationRequest=nil;preparationShown=false end
        LocalDuoPreparationPending=preparationRequest~=nil
        Rescue.ClearTemporary(CurrentRun,Players.PlayersIterator())
        thread(function()
            wait(0.2)
            Log("Mapa " .. tostring(name) .. "; jogadores=" .. Players.GetPlayersCount()
                .. "; controles=" .. tostring(CoopGetPlayerGamepad(1)) .. "," .. tostring(CoopGetPlayerGamepad(2)))
            Diagnostics.Snapshot("mapLoaded",name)
        end)
    end)
end

local function QueuePreparation(source, args)
    if args.ResumeRun and CurrentRun and CurrentRun.LocalDuoPreparationCompleted then return end
    if not Config.QuickPreparation or preparationShown or Players.GetPlayersCount()<2 then return end
    preparationShown=true
    preparationRequest={Source=source,Run=CurrentRun,Session=SessionMapState,Args=args}
    LocalDuoPreparationPending=true
    Log("Preparation queued for existing introduction/actor readiness: "..tostring(source.Name))
end
local function preparationCurrent(r)
    return LocalDuoCoopModeActive==true and CurrentRun==r.Run and SessionMapState==r.Session
        and (CurrentHubRoom or (CurrentRun and CurrentRun.CurrentRoom))==r.Source
end
local function preparationReady(r)
    if not preparationCurrent(r) or AreScreensActive() or PlayingTextLines then return false end
    if type(SessionMapState.PlayingCues)~='table' or next(SessionMapState.PlayingCues) then return false end
    if AudioState and AudioState.ActiveSpeechIds and next(AudioState.ActiveSpeechIds) then return false end
    if SessionMapState.QueuedVoiceLines and next(SessionMapState.QueuedVoiceLines) then return false end
    local a,b=Players.GetHero(1),Players.GetHero(2)
    if not a or not b or a==b or not a.ObjectId or not b.ObjectId or a.ObjectId==b.ObjectId then return false end
    if a.PlayingVoiceLine~=nil or b.PlayingVoiceLine~=nil then return false end
    if type(LocalDuoNativeBindingProbe)~='function' then return false end
    local ok,read=pcall(LocalDuoNativeBindingProbe,a.ObjectId,b.ObjectId)
    return ok and read and read.Validated==true and read.Player1NativeId==a.ObjectId and read.Player2NativeId==b.ObjectId
end
local actorBirthNeeded=assert(loadfile('<WORKSPACE>/work/integration/MissingAdditionalActor.lua','t',_G))()
PollPreparation=function()
    local r=preparationRequest
    if not r or r.Scheduled then return end
    if not preparationCurrent(r) or (r.Args.ResumeRun and r.Run.LocalDuoPreparationCompleted) then
        preparationRequest=nil;preparationShown=false;LocalDuoPreparationPending=false
        return
    end
    -- This actual preparation request occurs after the hub room/main hero exists.
    -- Birth precedes the introduction gate; opening UI still requires both real actors.
    local main,draft=Players.GetHero(1),Players.GetHero(2)
    if not r.ActorInitAttempted and not AreScreensActive()
        and actorBirthNeeded(main,draft,Safety.ValidUnit,LocalDuoNativeBindingProbe)
        and main and main.ObjectId and not main.IsDead and Safety.ValidUnit(main.ObjectId) then
        r.ActorInitAttempted=true
        local scheduled,problem=pcall(Context.ScheduleServiceThread,function()
            if preparationRequest~=r or not preparationCurrent(r) or Players.GetHero(1)~=main
                or Players.GetHero(2)~=draft or not actorBirthNeeded(main,draft,Safety.ValidUnit,LocalDuoNativeBindingProbe) or AreScreensActive() then return end
            local ok,result=pcall(Context.RunWithHeroContextAwait,main,Players.InitCoopUnit,2)
            r.ActorInitResult={Returned=ok,Value=result}
            Diagnostics.Write("preparationActorInit","returned="..tostring(ok).." actor="..
                tostring(type(result)=="table" and result.ObjectId or result))
        end)
        if not scheduled then Diagnostics.Write("preparationActorInit",tostring(problem)) end
        return
    end
    if not preparationReady(r) then return end
    local a,b=Players.GetHero(1),Players.GetHero(2)
    r.Heroes={a,b};r.ActorIds={a.ObjectId,b.ObjectId}
    -- Existing service dispatcher keeps a yielding Lobby.Open outside the native draw callback.
    r.Scheduled=true
    local scheduled,scheduleError=pcall(Context.ScheduleServiceThread,function()
        if preparationRequest~=r then return end
        if not preparationReady(r) then r.Scheduled=false;return end
        for p=1,2 do if Players.GetHero(p)~=r.Heroes[p] or r.Heroes[p].ObjectId~=r.ActorIds[p] then r.Scheduled=false;return end end
        local hero=r.Heroes[1]
        local ok,problem=pcall(Context.RunWithHeroContextAwait,hero,function()
            if not preparationReady(r) then r.Scheduled=false;return end
            -- Keep actor birth/readiness and personal selections; never open the
            -- legacy Arsenal overlay, including when resuming an existing run.
            PersonalWeapons.Ensure()
            -- Existing completion below releases only this request and its protection.
        end)
        if ok and r.Scheduled==false then return end
        if preparationRequest==r then preparationRequest=nil;LocalDuoPreparationPending=false end
        Safety.Update()
        if not ok then Diagnostics.Write("error",tostring(problem));error(problem,0) end
        Log("Preparation finished")
    end)
    if not scheduled then r.Scheduled=false;Diagnostics.Write("error",tostring(scheduleError)) end
end

-- A saved flashback can enter here without passing through KillHero's destination choice.
-- Redirect before SetupHeroObject/SetupFlashback01; never award or complete its story.
function Hook.wrap.DeathAreaRoomTransition(baseFun,source,...)
    if source and source.Name=="Flashback_Hub_Main" and LocalDuoCoopModeActive==true
        and type(CoopGetPlayersCount)=="function" then
        local ok,count=pcall(CoopGetPlayersCount)
        if ok and count==2 then
            -- Native ConcludeFlashback clears these transient presentation fields too.
            -- No RequestSave: let the destination's ordinary save flow own persistence.
            CurrentHubRoom=nil
            if SessionState then SessionState.InFlashback=false end
            return LoadMap({Name=GameData.HubMapName,ResetBinks=false})
        end
    end
    return baseFun(source,...)
end

function Hook.post.DeathAreaRoomTransition(source)
    if not Config.QuickPreparation or Players.GetPlayersCount() < 2 then return end
    if source.Name ~= "Hub_Main" and source.Name ~= "Hub_PreRun" then return end
    if SessionMapState.LocalDuoPreparationShown then return end
    SessionMapState.LocalDuoPreparationShown = true
    -- Initialize the second actor, then leave the native hub freely accessible.
    preparationShown = false
    QueuePreparation(source, { StartingBiome = "F", NativeHub = true })
end

function Hook.post.StartRoomPresentation(run, room)
    if CurrentHubRoom then return end
    for player,hero in Players.PlayersIterator()do
        if not hero.IsDead then Context.RunWithHeroContextAwait(hero,function()
            Character.Apply(player,hero)
            Mirror.EnterRoom(hero,room)
            Ally.Apply(hero)
        end)end
    end
    Rescue.UpdateHud()
    if false then -- reference scene suspended during performance recovery
        local ok,created,message=pcall(RenderProbe.Create,Players.GetHero(1))
        Diagnostics.Write("renderReference",ok and (tostring(created).." "..tostring(message)) or tostring(created))
        local sceneOk,sceneCreated,sceneId=pcall(OriginalScene.Start,Players.GetHero(1))
        Diagnostics.Write("originalVisualScene",sceneOk and (tostring(sceneCreated).." id="..tostring(sceneId))or tostring(sceneCreated))
    end
    if not run.LocalDuoPreparationCompleted then QueuePreparation(room, { ResumeRun = true })end
end

function Hook.post.RestoreUnlockRoomExits(run, room)
    if CurrentHubRoom then return end
    Rooms.ShowTurn()
    QueuePreparation(room, { ResumeRun = true })
end

function Hook.post.DoUnlockRoomExits()
    Rooms.ShowTurn()
end

function Hook.wrap.AttemptUseDoor(base, door, args)
    Diagnostics.Snapshot("doorAttempt","id="..tostring(door.ObjectId).." ready="..tostring(door.ReadyToUse)
        .." chooser="..tostring(Rooms.GetChooser()))
    if CurrentHubRoom or Players.GetPlayersCount() < 2 then return base(door, args) end
    local player=Players.GetCurrentPlayerId()
    if not Rooms.CanChoose(player) then
        Rooms.ShowTurn()
        return false
    end
    -- Claim only a real transition, after all vanilla readiness checks.
    -- Doors that start an encounter must remain usable after that fight.
    if door.ReadyToUse and not door.InUse and not door.EncounterCost
        and CheckRoomExitsReady(CurrentRun.CurrentRoom)
        and CheckSpecialDoorRequirement(door)==nil then
        if not Rooms.TryClaim(player,door.ObjectId)then return false end
        Rooms.ShowTurn()
    end
    return base(door, args)
end

function Hook.wrap.KillHero(base,...)
    Diagnostics.Snapshot("deathBefore","victim="..tostring(Players.GetCurrentPlayerId()))
    local result=base(...)
    if Players.HasAlivePlayers() then Rooms.ShowTurn() end
    Diagnostics.Snapshot("deathAfter")
    return result
end

function Hook.wrap.AttemptUseAutoExitDoor(base, door, args)
    local hero=Players.GetHeroByUnit(args and (args.UserId or args.triggeredById))
        or Players.GetHero(Players.GetCurrentPlayerId())
    if hero then return Context.RunWithHeroContextAwait(hero, base, door, args) end
    return base(door, args)
end

function Hook.post.SetTargetable(args)
    if args and args.Id and Players.IsPlayerUnit(args.Id) then Ally.Apply(Players.GetHeroByUnit(args.Id))end
end

function Hook.pre.LeaveRoom(run)
    Rooms.CommitChoice(run)
end

function Hook.wrap.UseEscapeDoor(base, door, args)
    -- The native exit owns its real presentation, requirements and StartOver.
    return base(door, args)
end

function Hook.post.SetupUnit(unit)
    -- Repair only our own factors; never run SetupUnit again or reset HP.
    Scaling.Reconcile(unit, Players.GetPlayersCount(), Config)
end

-- Read-only diagnostic, once per actual pickup/Run/Map/actor tuple; no new probe/input calls.
local boonFallbackSeen=setmetatable({},{__mode='k'})
local function TraceBoonFallback(loot,ensured,ensureReason,routing,decision)
    if LocalDuoCoopModeActive~=true or RenderProbe.IsTestProfile()~=true
        or type(loot)~='table' or not loot.LocalDuoOwner or not loot.LocalDuoBundle then return end
    -- Diagnostic failures must never change the original pickup route.
    pcall(function()
        local h1,h2=Players.GetHero(1),Players.GetHero(2)
        local run,map=CurrentRun,MapState
        local signature=tostring(run)..':'..tostring(map)..':'..tostring(h1 and h1.ObjectId)..':'..tostring(h2 and h2.ObjectId)
        if boonFallbackSeen[loot]==signature then return end
        boonFallbackSeen[loot]=signature
        local reason=decision and decision.Reason
        if type(reason)=='table'then reason=reason.Reason or reason.State end
        local parts={'ensure='..tostring(ensured~=nil),'ensureReason='..tostring(ensureReason),
            'moduleError='..tostring(OperationalBoon.Error),'moduleRunCurrent='..tostring(OperationalBoon.Run==run),
            'routingCurrent='..tostring(routing==OperationalBoon.Runtime),
            'routingEnabled='..tostring(routing and routing.Enabled),'routingError='..tostring(routing and routing.Error),
            'reason='..tostring(reason),'run='..tostring(run),'map='..tostring(map),
            'source='..tostring(loot.ObjectId),'name='..tostring(loot.Name),
            'owner='..tostring(loot.LocalDuoOwner),'bundle='..tostring(loot.LocalDuoBundle),
            'sameHeroRef='..tostring(h1==h2),'sameActor='..tostring(h1 and h2 and h1.ObjectId==h2.ObjectId)}
        for _,s in pairs(map and map.RoomRequiredObjects or{})do
            if s.LocalDuoBundle==loot.LocalDuoBundle then
                parts[#parts+1]='pair{id='..tostring(s.ObjectId)..',owner='..tostring(s.LocalDuoOwner)
                    ..',name='..tostring(s.Name)..',pool='..tostring(s.UpgradeOptions)
                    ..',count='..tostring(type(s.UpgradeOptions)=='table'and #s.UpgradeOptions or nil)..'}'
            end
        end
        for p=1,2 do
            local schema=Control.Schemas.Current[p]
            parts[#parts+1]='deviceJ'..p..'='..tostring(schema and schema.Device)..':'..tostring(schema and schema.ControllerId)
        end
        for key,record in pairs(OperationalBoon.Runtime and OperationalBoon.Runtime.Host.Records or{})do
            local session=record.Handle and record.Handle.Session
            if (session and session.State~='closed')or(record.EntryFault and not record.EmergencyDone)then
                parts[#parts+1]='oldRecord{key='..tostring(key)..',session='..tostring(session and session.State)
                    ..',entryFault='..tostring(record.EntryFault)..',emergencyDone='..tostring(record.EmergencyDone)
                    ..',room='..tostring(record.Scope and record.Scope.Room)..'}'
            end
        end
        Diagnostics.Snapshot('DUO_BOON_STOCK_FALLBACK',table.concat(parts,' '))
    end)
end

function Hook.wrap.UseLoot(base, loot, args, user)
    if LocalDuoCoopModeActive==true and RenderProbe.IsTestProfile()==true and loot.LocalDuoCommonCarrier then return false end
    -- Optional Profile3 pilot service, before native payment/pickup side effects.
    local ensured,ensureReason=OperationalBoon.Ensure()
    local routing=LocalDuoRewardRouting;local decision
    if routing and RenderProbe.IsTestProfile() then
        decision=routing:BeforeUseLoot(loot,user or CurrentRun.Hero)
    end
    if LocalDuoCoopModeActive==true and RenderProbe.IsTestProfile()==true and loot.LocalDuoCommonRoot and (not decision or not decision.Handled or decision.Route=='waiting')then
        TraceBoonFallback(loot,ensured,ensureReason,routing,decision)
        loot.LocalDuoCommonBlockedReason=(decision and decision.Reason) or ensureReason or 'Interface da dupla indisponível.'
        thread(InCombatTextArgs,{TargetId=(user or CurrentRun.Hero).ObjectId,Text=tostring(loot.LocalDuoCommonBlockedReason),Duration=2.0})
        return false -- Common reward never falls back to sequential stock/automatic partner pickup.
    end
    local single=LocalDuoSingleVisibleBoonPickup
    if single and type(single.BeforeStockOrDecision)=='function' then
        local restored,value=pcall(single.BeforeStockOrDecision,loot,decision or {Handled=false})
        if not restored then return false end
        decision=value
    end
    if decision and decision.Handled then return decision.Route=='duo' end
    TraceBoonFallback(loot,ensured,ensureReason,routing,decision)
    if not Loot.CanUseHeroLoot(loot, CurrentRun.Hero) then return false end
    if loot.LocalDuoOwner then DestroyTextBox({ Id = loot.ObjectId }) end
    local result=base(loot, args, user)
    if routing and decision and decision.AllowLegacy then routing:LegacyFinished(decision,loot,result==true)end
    if result and loot.LocalDuoBundle and not AreScreensActive() then
        for _,other in pairs(MapState.RoomRequiredObjects or {}) do
            if other~=loot and other.LocalDuoBundle==loot.LocalDuoBundle
                and other.OnUsedFunctionName=="UseLoot" then
                local hero=Players.GetHero(other.LocalDuoOwner)
                if hero and not hero.IsDead then
                    waitUnmodified(0.1)
                    Context.RunWithHeroContextAwait(hero,UseLoot,other,{SkipInteractAnim=true},hero)
                    break
                end
            end
        end
    end
    return result
end

function Hook.post.CreateScreenFromData(screen)
    local source=screen.Source
    if not source or not source.LocalDuoOwner then return end
    local player=Players.GetCurrentPlayerId() or source.LocalDuoOwner
    local component=CreateScreenComponent({Name="BlankObstacle",Group="Combat_Menu_Overlay",
        X=ScreenCenterX,Y=36})
    screen.Components.LocalDuoOwner=component
    CreateTextBox({Id=component.Id,Text="JOGADOR "..player.." â€” SUA ESCOLHA",
        Font="LatoMedium",FontSize=22,Color=player==1 and {100,160,255,255} or {205,135,255,255},
        Justification="Center"})
end

function Hook.wrap.CreateLoot(base, args)
    local reward = base(args)
    if LocalDuoCoopModeActive==true and RenderProbe.IsTestProfile()==true and reward and reward.ResourceCosts and reward.BoughtFromShop then OperationalBoon.Ensure() end
    local routing=LocalDuoRewardRouting
    if routing and routing.Enabled and routing.Shop then
        reward=routing.Shop:AfterCreateLoot(base,args,reward)
        if routing.Shop:Owns(reward)then
            local pair=routing.Shop:SourcesFor(reward)
            if pair and pair[1]and pair[2]and routing.PrepareVisiblePair then
                local ok,problem=pcall(routing.PrepareVisiblePair,routing,pair,CurrentRun.CurrentRoom,pair[1].LocalDuoBundle)
                if not ok then routing.Shop.PresentationError=tostring(problem)end
            end
            return reward
        end
    end
    if not reward or args.LocalDuoCopy or Loot.PersonalSpawnDepth > 0
        or reward.ResourceCosts or reward.BoughtFromShop or Players.GetPlayersCount() < 2 then return reward end
    local owner = Players.GetCurrentPlayerId() or 1
    reward.LocalDuoOwner = owner
    for player = 1, 2 do
        local hero = Players.GetHero(player)
        if player ~= owner and hero and not hero.IsDead then
            local options = DeepCopyTable(args)
            options.LocalDuoCopy = true
            options.SpawnPoint = hero.ObjectId
            options.OffsetX = (args.OffsetX or 0) + (player == 1 and -180 or 180)
            local copy = Context.RunWithHeroContextAwait(hero, base, options)
            if copy then copy.LocalDuoOwner = player end
        end
    end
    return reward
end

function Hook.wrap.CreateConsumableItem(base,id,name,cost,args)
    return NpcPom.Create(function(...)return Healing.Create(base,...)end,id,name,cost,args)
end
function Hook.wrap.Heal(base,victim,args)
    return Healing.Heal(base,victim,args)
end
function Hook.wrap.UseConsumableItem(base, item, args, user)
    if not Loot.CanUseHeroLoot(item, CurrentRun.Hero) then return false end
    if item.LocalDuoOwner then DestroyTextBox({ Id = item.ObjectId }) end
    if NpcPom.Owns(item) then return NpcPom.Use(base,item,args,user) end
    if Healing.Owns(item) then return Healing.Use(base,item,args,user) end
    if Mana.Owns(item) then return Mana.Use(base,item,args,user) end
    return Centaur.Use(base,item,args,user)
end
function Hook.wrap.AddMaxHealth(base,amount,source,args)
    return Centaur.AddMaxHealth(base,amount,source,args)
end
function Hook.wrap.AddMaxMana(base,amount,source,args)
    return Mana.AddMaxMana(base,amount,source,args)
end
function Hook.wrap.GiveRandomConsumables(base,args,trait,contextArgs)
    return NpcPom.Give(base,args,trait,contextArgs)
end
function Hook.wrap.UseStoreRewardRandomStack(base,args)
    return NpcPom.UseRandomPom(base,args)
end
function Hook.wrap.AddStackToTraits(base,source,args)
    return NpcPom.Stacks(base,source,args)
end
function Hook.wrap.UseHealthFountain(base,used,user)
    if used.LocalDuoUsed then return false end
    used.LocalDuoUsed=true
    local owner=CurrentRun.Hero
    for _,hero in ipairs(Players.GetAliveHeroes())do
        if hero~=owner then Context.RunWithHeroContextAwait(hero,Fountains.Apply,used,hero)end
    end
    return base(used,user)
end

function Hook.wrap.EquipPlayerWeapon(base, weapon, args)
    local primary = GameState.PrimaryWeaponName
    local player = Players.GetCurrentPlayerId()
    local result = base(weapon, args)
    if player and player > 1 and not PersonalWeapons.IsActive() then GameState.PrimaryWeaponName = primary end
    return result
end

function Hook.wrap.RequestPreRunLoadoutChangeSave(base)
    if CurrentHubRoom then return base() end
    -- The base menus assume the altar is in the hub; a lobby inside a loaded
    -- combat room must save the current room without accessing a hub name.
    return RequestSave({})
end

return Hook
