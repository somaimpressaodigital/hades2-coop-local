--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type RunEx
local RunEx = ModRequire "RunEx.lua"
---@type Events
local Events = ModRequire "Events.lua"
local DuoConfig = (ModRequire "../config.lua").LocalDuo

---@class CoopCamera
local CoopCamera = {}

---@private
CoopCamera.isFocusEnabled = true

---@private
CoopCamera.IgnoreHeroes = {}

function CoopCamera.InitHooks()
    Events.engine:on("tick", CoopCamera.Update)
    CoopCamera.LockCameraOrig = LockCamera
    LockCamera = CoopCamera.LockCameraHook
end

---@param state boolean
function CoopCamera.ForceFocus(state)
    CoopCamera.FocusSignature=nil
    CoopCamera.isFocusEnabled = state
end

-- Pure current-player targets are explicit native return points, not NPC pans.
function CoopCamera.IsPlayerOnlyCameraTarget(args)
    local function owned(id)
        if type(id)~="number" or id<=0 then return false end
        local matches=0
        for _,hero in CoopPlayers.PlayersIterator()do
            if hero and hero.ObjectId==id then matches=matches+1 end
        end
        return matches==1
    end
    if type(args)~="table" then return false end
    if args.Id then return args.Ids==nil and owned(args.Id) end
    if type(args.Ids)~="table" then return false end
    local count=0
    for _,id in pairs(args.Ids)do if not owned(id)then return false end;count=count+1 end
    return count>0
end
function CoopCamera.LockCameraHook(args)
    if LocalDuoCoopModeActive==true and CoopPlayers.GetPlayersCount()>=2 then
        if CoopCamera.IsPlayerOnlyCameraTarget(args)then
            CoopCamera.ForceFocus(true)
            CoopCamera.Update()
        else
            CoopCamera.ForceFocus(false)
            return CoopCamera.LockCameraOrig(args)
        end
        return
    end
    local mainPlayerId  = CoopPlayers.GetMainHero().ObjectId
    if mainPlayerId and args.Id == mainPlayerId then
        CoopCamera.ForceFocus(true)
        CoopCamera.Update()
    else
        CoopCamera.ForceFocus(false)
        CoopCamera.LockCameraOrig(args)
    end
end


---@private
function CoopCamera.OnExitNPCPresentation()
    -- Fixes wrong camera focus after some  NPC dialoges.
    -- E.g. after feeding the dog in the styx temple hub
    CoopCamera.LockCameraHook({ Id = CoopPlayers.GetMainHero().ObjectId })
end

---@private
function CoopCamera.Update()
    if not CoopCamera.isFocusEnabled then
        return
    end

    local units = {}

    -- It's bad
    -- Players are dead in prerun room
    local wasRunFinished = RunEx.IsRunEnded()

    for _, hero in CoopPlayers.PlayersIterator() do
        if hero and (wasRunFinished or not hero.IsDead) and not CoopCamera.IgnoreHeroes[hero] then
            table.insert(units, hero.ObjectId)
        end
    end

    if #units == 0 then
        return
    end

    -- Preserve the previously working close-range follow behavior. Smooth
    -- only zoom, without adding/restarting an interpolation of the position.
    CoopCamera.LockCameraOrig { Ids = units, Duration = 0.0 }
    CoopCamera.UpdateDistanceZoom(units)
end

function CoopCamera.CalculateDistanceZoom(baseZoom, dx, dy, width, height)
    return math.max(DuoConfig.CameraMinimumZoom or 0.22,
        math.min(baseZoom, width * 0.72 / (math.abs(dx) + 600),
            height * 0.64 / (math.abs(dy) + 500)))
end

function CoopCamera.UpdateDistanceZoom(units)
    if not CoopCamera.isFocusEnabled or not CurrentRun or AreScreensActive() or PlayingTextLines
        or (SessionMapState and not IsEmpty(SessionMapState.LockCameraMotion or {})) then return end
    local room = RunEx.GetCurrentRoom()
    if not room then return end
    if CoopCamera.ZoomRoom ~= room then
        CoopCamera.ZoomRoom = room
        CoopCamera.BaseZoom = room.ZoomFraction or 1.0 -- Native DoCameraMotion's fallback, not Arcana GetZoomLevel.
        CoopCamera.InitializeRoomZoom=true
        CoopCamera.LastZoom = CoopCamera.BaseZoom
        CoopCamera.LastZoomTime = nil
        CoopCamera.ZoomCommandElapsed = 0
        CoopCamera.SentZoom = CoopCamera.LastZoom
    end
    local target = CoopCamera.BaseZoom
    -- Reduce each room's own coop zoom (.6 -> .5); Hub_Main uses native 1.23.
    -- An absolute .5 ceiling makes the hub excessively wide. Keep already-wide rooms.
    local maximumZoom = LocalDuoCoopModeActive==true and CoopPlayers.GetPlayersCount()>=2
        and (target>0.5 and target*(5/6) or target) or nil
    if #units >= 2 then
        local a = GetLocation({ Id = units[1] })
        local b = GetLocation({ Id = units[2] })
        if a and b and type(a.X)=="number" and type(a.Y)=="number"
            and type(b.X)=="number" and type(b.Y)=="number" then
            target = CoopCamera.CalculateDistanceZoom(target, a.X - b.X, a.Y - b.Y,
                ScreenWidth, ScreenHeight)
        end
    end
    -- Additional 17% smaller coop zoom, after native-room and distance fitting.
    if maximumZoom then target=math.min(target,maximumZoom)*0.83 end
    if CoopCamera.InitializeRoomZoom then
        CoopCamera.InitializeRoomZoom=nil
        CoopCamera.LastZoom=target;CoopCamera.SentZoom=target
        AdjustZoom({Fraction=target,Duration=0})
    end
    local now=_worldTimeUnmodified
    local dt=type(now)=="number" and CoopCamera.LastZoomTime and now-CoopCamera.LastZoomTime or 1/60
    CoopCamera.LastZoomTime=type(now)=="number" and now or nil
    dt=math.max(0,math.min(dt,0.1))
    CoopCamera.LastZoom=CoopCamera.SmoothZoom(CoopCamera.LastZoom,target,dt)
    -- The fraction itself is smoothed each frame. Do not stack a second native
    -- tween or emit it in visible 10 Hz steps while the close camera follows.
    -- GetZoomLevel is an Arcana layout getter, not native camera readback.
    -- Reassert the existing dynamic target only while shared view owns >=2 units.
    local ownsSharedZoom = #units >= 2 and CoopPlayers.GetPlayersCount() >= 2
    if ownsSharedZoom or math.abs(CoopCamera.LastZoom-CoopCamera.SentZoom)>=0.0001 then
        CoopCamera.SentZoom=CoopCamera.LastZoom
        AdjustZoom({Fraction=CoopCamera.SentZoom,Duration=0})
    end
end

function CoopCamera.SmoothZoom(current,target,dt)
    if math.abs(target-current)<0.003 then return current end
    dt=math.max(0,math.min(dt,0.1))
    local outward=target<current
    local tau=outward and 0.14 or 0.55
    local rate=outward and 0.60 or 0.18
    local step=(target-current)*(1-math.exp(-dt/tau))
    step=math.max(-rate*dt,math.min(rate*dt,step))
    return current+step
end

---@public
function CoopCamera.SetHeroIgnored(hero, state)
    if state then
        CoopCamera.IgnoreHeroes[hero] = state
    else
        CoopCamera.IgnoreHeroes[hero] = nil
    end
end

---@public
function CoopCamera.ResetIgnore()
    CoopCamera.IgnoreHeroes = {}
end

return CoopCamera
