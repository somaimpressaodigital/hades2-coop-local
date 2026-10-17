--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../logic/HeroContext.lua"
---@type HookUtils
local HookUtils = ModRequire "../utils/HookUtils.lua"
---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type SecondPlayerUi
local SecondPlayerUi = ModRequire "../logic/SecondPlayerUI.lua"
---@type RunEx
local RunEx = ModRequire "../logic/RunEx.lua"
---@type PlayerVisibilityHelper
local PlayerVisibilityHelper = ModRequire "../logic/PlayerVisibilityHelper.lua"
---@type HeroEx
local HeroEx = ModRequire "../logic/HeroEx.lua"
---@type CoopControl
local CoopControl = ModRequire "../logic/CoopControl.lua"
---@type Events
local Events = ModRequire "../logic/Events.lua"
local CoopRun=ModRequire "../logic/CoopRun.lua"
local Rescue=ModRequire "../logic/LocalDuoRescue.lua"
local RescueExpiry=ModRequire "../logic/LocalDuoRescueExpiry.lua"
local Diagnostics=ModRequire "../logic/LocalDuoDiagnostics.lua"
local PreTransition=ModRequire "../logic/LocalDuoPreTransition.lua"
local Rooms=ModRequire "../logic/LocalDuoRooms.lua"
local CampaignEnd=ModRequire "../logic/LocalDuoCampaignEnd.lua"

---@class RunHooks : SimpleHook
local RunHooks = SimpleHook.New()
local terminalVisualScope
local sharedTerminalByRun=setmetatable({},{__mode='k'})
-- Read-only Lua presentation identity. No native receipt, actor generation or persistence API.
function RunHooks.GetTerminalVisualScope()
    local s=terminalVisualScope
    if not s or LocalDuoCoopModeActive~=true or CurrentHubRoom or CurrentRun~=s.Run
        or CurrentRun.CurrentRoom~=s.Room or MapState~=s.Map or SessionMapState~=s.Session
        or CurrentRun.LocalDuoEnding~=true then return nil end
    for p=1,2 do
        local hero=CoopPlayers.GetHero(p)
        if hero~=s.HeroRefs[p] or hero.ObjectId~=s.Ids[p] or hero.IsDead~=true then return nil end
    end
    if CoopPlayers.GetHero(s.TerminalVictimOwner)~=s.TerminalVictimRef then return nil end
    return {Run=s.Run,Room=s.Room,Map=s.Map,Session=s.Session,HeroRefs={s.HeroRefs[1],s.HeroRefs[2]},
        Ids={s.Ids[1],s.Ids[2]},TerminalVictimOwner=s.TerminalVictimOwner,TerminalVictimRef=s.TerminalVictimRef}
end

local function drainBeforeTransition(reason)
    if not PreTransition.HasPending(_G) then return true end
    return HeroContext.RunWithHeroContextAwait(CoopPlayers.GetMainHero(),PreTransition.Wait,_G,CoopPlayers,reason,Diagnostics.Write)
end
function RunHooks:InitGameHooks()
    -- GamemodeInit emits this AFTER all game/engine/camera hooks and CoopGame.Init.
    -- Thus cleanup precedes LeaveRoom prehooks and StartNewRun's stock mutation.
    Events.engine:once("hooksInicialized",function()
        for _,name in ipairs({"StartOver","StartNewRun","LeaveRoom","LoadMap"})do
            HookUtils.wrap(name,function(base,...)
                local ok,why=drainBeforeTransition(name)
                if not ok then return false,why end
                return base(...)
            end)
        end
    end)
end


function RunHooks.pre.DeathAreaRoomTransition()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
end

function RunHooks.wrap.CheckDistanceTrigger(CheckDistanceTriggerFun, ...)
    -- TODO
    -- This hack fixes crashes like Hades 1 #21 when the player 1 is dead.
    -- The crash is caused by invalid reference to the second player.
    -- The game cannot find a player unit and triggers NotifyWithinDistance instantly without result
    HeroContext.RunWithHeroContext(CoopPlayers.GetMainHero(), CheckDistanceTriggerFun, ...)
end

function RunHooks.wrap.SetupHeroObject(SetupHeroObjectFun, ...)
    local mainHero = CoopPlayers.GetMainHero()

    HeroContext.RunWithHeroContext(mainHero, SetupHeroObjectFun, ...)
    -- Fix unit -> hero table here
    CoopPlayers.UpdateMainHero()

    PlayerVisibilityHelper.AddPlayerMarkers(1, mainHero.ObjectId)

    if mainHero.IsDead and not RunEx.IsRunEnded() then
        HeroEx.HideHero(mainHero)
    end
end

function RunHooks.wrap.StartRoom(StartRoomFun, run, currentRoom)
    Rooms.ResetRuntime(currentRoom)
    -- Narrative maps use a single native protagonist. Select J1 before the
    -- entrance captures an actor, then restore both players on the next hub.
    if RunEx.IsMetaStoryRoom(currentRoom.Name) then CoopRun.MakeFirstPlayerOnlyMode() end
    -- Fixes mouse disappearing after level transiction
    CoopControl.ResetAllPlayers("Current")

    -- Initialization after save loading when encounter is active
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
        CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
    end

    if currentRoom.RoomSetName == "Surface" then
        RunHooks.HandleSurfaceRoom(StartRoomFun, run, currentRoom)
    else
        RunHooks.HandleGenericRoom(StartRoomFun, run, currentRoom)
    end
end

---@private
function RunHooks.HandleGenericRoom(StartRoomFun, run, currentRoom)
    HookUtils.onPostFunctionOnce("SwitchActiveUnit", function()
        SwitchActiveUnit { PlayerIndex = 1, Id = CoopPlayers.GetMainHero().ObjectId }
    end)

    if RunEx.IsRunEnded() then
        HeroContext.RunWithHeroContext(CoopPlayers.GetMainHero(), StartRoomFun, run, currentRoom)
    else
        local hero = CoopPlayers.GetAliveHeroes()[1] or CoopPlayers.GetMainHero()
        HeroContext.RunWithHeroContext(hero, StartRoomFun, run, currentRoom)
    end
end

---@private
function RunHooks.HandleSurfaceRoom(StartRoomFun, run, currentRoom)
    return RunHooks.HandleGenericRoom(StartRoomFun,run,currentRoom)
end

function RunHooks.post.StartNewRun()
    CurrentRun.LocalDuoPreparationCompleted=LocalDuoPreparationStartsNextRun==true
    LocalDuoPreparationStartsNextRun=nil
    CurrentRun.LocalDuoRescuesUsed=0
    sharedTerminalByRun[CurrentRun]=nil
    CurrentRun.LocalDuoEnding=nil
    CurrentRun.LocalDuoMirrorPurseApplied=nil
    Events.run:trigger("newRunStarted", CurrentRun)
end

--- Bypass IsAlive check with this hook
function RunHooks.wrap.CheckRoomExitsReady(baseFun, ...)
    local aliveHero = CoopPlayers.GetAliveHeroes()[1]
    if aliveHero then
        local result = false
        HeroContext.RunWithHeroContext(aliveHero, function(...)
            result = baseFun(...)
        end, ...)

        return result
    else
        return baseFun(...)
    end
end

function RunHooks.wrap.EndEarlyAccessPresentation(baseFun)
    local mainHero = CoopPlayers.GetMainHero()
    mainHero.IsDead = false
    for playerId, hero in CoopPlayers.AdditionalHeroesIterator() do
        hero.IsDead = true
    end
    HeroContext.RunWithHeroContext(mainHero, baseFun)
end

local function sameSharedTerminal(r)
 if CurrentRun~=r.Run or CurrentRun.CurrentRoom~=r.Room or MapState~=r.Map or SessionMapState~=r.Session
  or CurrentHubRoom or Rescue.IsArenaOwned()then return false end
 for p=1,2 do if CoopPlayers.GetHero(p)~=r.Heroes[p]or r.Heroes[p].ObjectId~=r.Ids[p]then return false end end
 return(r.Main==r.Heroes[1]or r.Main==r.Heroes[2])and CoopPlayers.GetMainHero()==r.Main
end
function RunHooks.TryRescue(victim,args)
    if not Rescue.IsCampaign(CurrentRun)or CurrentRun.LocalDuoEnding or SessionMapState.HandlingDeath or CampaignEnd.IsEnding(CurrentRun)then return false end
    local partner
    for _,hero in CoopPlayers.PlayersIterator()do if hero~=victim then partner=hero end end
    local rescued,amount,duplicate=Rescue.Transfer(CurrentRun,victim,partner,args)
    if rescued then
        if duplicate then return true end
        SetTargetable({Id=victim.ObjectId})
        HeroContext.SetDefaultHero(CoopPlayers.GetMainHero())
        HeroContext.RunWithHeroContext(partner,UpdateHealthUI)
        UpdateHealthUI();SecondPlayerUi.UpdateHealthUI()
        RescueExpiry.Protect(_G,CoopPlayers,HeroContext,victim,Diagnostics.Write)
        Diagnostics.Snapshot('rescue','restored='..amount..' remaining='..Rescue.Remaining(CurrentRun))
        return true
    end
    return false
end
function RunHooks.wrap.CheckLastStand(base,victim,args)
    if CampaignEnd.IsEnding(CurrentRun)and victim and CoopPlayers.IsPlayerHero(victim)then return false end
    if Rescue.IsCampaign(CurrentRun)and victim and CoopPlayers.IsPlayerHero(victim)then
        -- Shared pool owns campaign fatalities BEFORE personal DD; never erase DD data.
        return HeroContext.RunWithHeroContextAwait(victim,RunHooks.TryRescue,victim,args)==true
    end
    return base(victim,args)
end
function RunHooks.wrap.Kill(base,victim,args)
    if victim and CoopPlayers.IsPlayerHero(victim)then
        local saved=HeroContext.RunWithHeroContextAwait(victim,RunHooks.TryRescue,victim,args)
        if saved then return end
    end
    return base(victim,args)
end
function RunHooks.wrap.KillHero(baseFun,...)
    if not Rescue.IsCampaign(CurrentRun)then return baseFun(...)end -- Solo/hub/private Arena keep original boundary.
    local run=CurrentRun
    local manualIntent=CampaignEnd.IsEnding(run) -- capture predicate against ORIGINAL run before cleanup can yield
    if RunHooks.TryRescue(run.Hero,select(2,...))then return end
    local r=sharedTerminalByRun[run]
    if r and(r.Busy or r.Dispatched)then return end
    if not r then
        if run.LocalDuoEnding or SessionMapState.HandlingDeath then return end
        local a,b=CoopPlayers.GetHero(1),CoopPlayers.GetHero(2)
        r={Run=run,Room=run.CurrentRoom,Map=MapState,Session=SessionMapState,
            Heroes={a,b},Ids={a.ObjectId,b.ObjectId},Main=CoopPlayers.GetMainHero(),Victim=run.Hero,ManualIntent=manualIntent}
        sharedTerminalByRun[run]=r
    end
    if not sameSharedTerminal(r)then return false,'Shared terminal scope changed'end
    if r.ManualIntent and not CampaignEnd.IsEnding(r.Run)then return false,'Original manual end intent changed'end
    -- Own terminal latch BEFORE cleanup can yield; concurrent fatal callbacks cannot dispatch twice.
    r.Busy=true;run.LocalDuoEnding=true;Rescue.UpdateHud()
    local ok,cleaned,why=pcall(drainBeforeTransition,'terminal KillHero')
    if not ok or not cleaned then
        r.Busy=false;r.Error=tostring(not ok and cleaned or why)
        return false,r.Error -- retain exact pending terminal for a legitimate later retry
    end
    if not sameSharedTerminal(r)then r.Busy=false;return false,'Shared terminal scope changed during cleanup'end
    if r.ManualIntent and not CampaignEnd.IsEnding(r.Run)then r.Busy=false;return false,'Original manual end intent changed during cleanup'end
    r.Dispatched=true;r.Busy=false -- No further cleanup/base replay after terminal commitment.
    local actualVictim=r.Victim;local owner=CoopPlayers.GetPlayerByHero(actualVictim)
    terminalVisualScope=nil
    if(owner==1 or owner==2)and CoopPlayers.GetHero(owner)==actualVictim then
        terminalVisualScope={Run=run,Room=r.Room,Map=r.Map,Session=r.Session,
            HeroRefs=r.Heroes,Ids=r.Ids,TerminalVictimOwner=owner,TerminalVictimRef=actualVictim}
    end
    for _,hero in CoopPlayers.PlayersIterator()do hero.IsDead=true;hero.Health=0 end
    -- Existing paired terminal dispatch: native death under main and ordinary postdeath reset.
    HeroEx.ShowHero(r.Main,actualVictim.ObjectId)
    RemoveOutline({Id=r.Main.ObjectId})
    HeroContext.RunWithHeroContext(r.Main,baseFun,...)
    CoopPlayers.OnAllPlayersDead()
end
-- Reuse real lifecycle events; no new polling loop or technical HUD labels.
function RunHooks.post.HideCombatUI()Rescue.UpdateHud()end
function RunHooks.post.ShowCombatUI()Rescue.UpdateHud()end
function RunHooks.post.OnScreenOpened()Rescue.UpdateHud()end
function RunHooks.post.OnScreenCloseFinished()Rescue.UpdateHud()end

function RunHooks.pre.LeaveRoom(currentRun, door)
    Events.run:trigger("roomPreLeave", currentRun, door)
end

function RunHooks.post.RestoreUnlockRoomExits()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
    -- DefaultHero becomes the survivor when J1 falls; it must not replace J1.
    if not CoopPlayers.GetMainHero() then
        CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
    end

    local spawnPoint = CurrentRun.CurrentRoom.HeroEndPoint or CoopPlayers.GetMainHero().ObjectId
    for playerId = 2, CoopPlayers.GetPlayersCount() do
        CoopPlayers.RestoreSavedHero(playerId)
        local hero = CoopPlayers.GetHero(playerId)
        if hero and not hero.IsDead then
            Teleport { Id = hero.ObjectId, DestinationId = spawnPoint }
        end
    end

    SecondPlayerUi.Refresh()
end

function RunHooks.wrap.EndEncounterEffects(baseFun, currentRun, currentRoom, currentEncounter)
    for _, hero in ipairs(CoopPlayers.GetAliveHeroes()) do
        HeroContext.RunWithHeroContextAwait(hero, baseFun, currentRun, currentRoom, currentEncounter)
        currentRoom.CodexUpdates = nil
        currentRoom.PendingCodexUpdate = nil
    end
end

function RunHooks.wrap.StartEncounterEffects(baseFun, run)
    for _, hero in ipairs(CoopPlayers.GetAliveHeroes()) do
        HeroContext.RunWithHeroContextAwait(hero, baseFun, run)
    end
end

function RunHooks.post.StartRoomPresentation(run, room)
    Events.run:trigger("roomPresentationFinished", run, room)
end

function RunHooks.pre.OnAllEnemiesDead()
    Events.run:trigger("allEnemiesDead")
end

function RunHooks.pre.StartRoom()
    Events.run:trigger("roomPreStart")
end

--- Fix players positions in the second stage
function RunHooks.post.ChronosPhaseTransition()
    for _, hero in pairs(CoopPlayers.GetAliveHeroes()) do
        Teleport({ Id = hero.ObjectId, DestinationId = 645921 })
    end
end

return RunHooks
