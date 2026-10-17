--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type CoopCamera
local CoopCamera = ModRequire "../logic/CoopCamera.lua"

local CameraHooks = SimpleHook.New()

local function coopActive()
    return LocalDuoCoopModeActive==true and CoopPlayers.GetPlayersCount()>=2
end

function CameraHooks.wrap.CreateRoom(baseFunc, ...)
    local room = baseFunc(...)
    if not coopActive() then return room end
    if not room.ZoomFraction then
        room.ZoomFraction = 0.6
    elseif room.ZoomFraction > 0.5 then
        room.ZoomFraction = room.ZoomFraction * 0.6
    end
    return room
end

function CameraHooks.post.PanCamera(args)
    if not coopActive() then return end
    if args.Id or type(args.Ids)=="table" then
        CoopCamera.ForceFocus(CoopCamera.IsPlayerOnlyCameraTarget(args))
    end
end

-- Gate only charge/cancel presentation fields BEFORE CombatLogic queues zoom.
-- All gameplay fields and nested data retain their original references.
function CameraHooks.wrap.GetWeaponData(base,unit,weaponName,...)
    local data=base(unit,weaponName,...)
    if data and (data.ChargeCameraMotion or data.ChargeCancelCameraMotion)
        and coopActive() and CoopPlayers.IsPlayerHero(unit)
        and CoopCamera.isFocusEnabled==true and not PlayingTextLines
        and not AreScreensActive() and SessionMapState
        and IsEmpty(SessionMapState.LockCameraMotion or {}) then
        local view=ShallowCopyTable(data)
        view.ChargeCameraMotion=nil
        view.ChargeCancelCameraMotion=nil
        -- The same charged weapon can schedule a release zoom through a
        -- separate FireCameraMotion producer (e.g. WeaponSuitCharged).
        view.FireCameraMotion=nil
        return view
    end
    return data
end

-- Stock charging can queue the raw weapon table when OwnerTable is absent,
-- bypassing GetWeaponData above. Guard only the exact current Suit motion refs.
function CameraHooks.wrap.DoCameraMotion(base,cameraData)
    if type(cameraData)=='table'and coopActive()and CoopCamera.isFocusEnabled==true
        and not PlayingTextLines and not AreScreensActive()and SessionMapState
        and IsEmpty(SessionMapState.LockCameraMotion or {})then
        local suit=WeaponData and WeaponData.WeaponSuitCharged
        local known=suit and(cameraData==suit.ChargeCameraMotion
            or cameraData==suit.ChargeCancelCameraMotion or cameraData==suit.FireCameraMotion)
        if known then
            local actualSuit=false
            for _,hero in CoopPlayers.PlayersIterator()do
                if hero and not hero.IsDead and type(hero.ObjectId)=='number'and hero.ObjectId>0
                    and hero.Weapons and hero.Weapons.WeaponSuit then actualSuit=true;break end
            end
            local playerSource=not(cameraData.Id or cameraData.Ids)
                or CoopCamera.IsPlayerOnlyCameraTarget(cameraData)
            if actualSuit and playerSource then return end -- Visual motion only; no charge/gameplay mutation.
        end
    end
    return base(cameraData)
end

return CameraHooks
