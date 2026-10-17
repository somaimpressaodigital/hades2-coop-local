--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "HeroContext.lua"

---@class HeroContextWrapper
local HeroContextWrapper = {}

LocalDuoProjectileObserverGateway = LocalDuoProjectileObserverGateway or {
    Listeners = {creation={}, death={}}, Errors={}
}
do
    local gateway=LocalDuoProjectileObserverGateway
    gateway.Register=function(kind,callback)
        assert(type(callback)=='function' and gateway.Listeners[kind], 'Lua observer type required')
        table.insert(gateway.Listeners[kind],callback)
    end
    gateway.Dispatch=function(kind,args)
        for _,callback in ipairs(gateway.Listeners[kind])do
            local ok,problem=pcall(callback,args)
            if not ok then gateway.Errors[#gateway.Errors+1]=tostring(problem) end
        end
    end
end



function HeroContextWrapper.WrapTriggerHero(name, argField)
    local original = _G[name]
    _G[name] = function(args)
        local names, fun
        if type(args[1]) == "function" then
            fun = args[1]
        else
            names = args[1]
            fun = args[2]
        end

        if name == 'OnProjectileCreation' then
            local stock = fun
            fun = function(triggerArgs)
                local gateway = LocalDuoProjectileObserverGateway
                if gateway then gateway.Dispatch('creation', triggerArgs) end
                return stock(triggerArgs)
            end
        end

        local hook = function(triggerArgs)
            local hero = triggerArgs[argField]
            -- Missing charge owner bypasses GetWeaponData in vanilla. Resolve
            -- only an exact current actor/id, never the default hero or an NPC.
            local chargeEvent = argField == "OwnerTable" and
                (name == "OnWeaponCharging" or name == "OnWeaponChargeCanceled")
            if chargeEvent and hero == nil and LocalDuoCoopModeActive == true
                and CoopPlayers.GetPlayersCount() >= 2 then
                local id = triggerArgs.triggeredById
                local candidate = type(id) == "number" and id > 0 and CoopPlayers.GetHeroByUnit(id)
                if candidate and candidate.ObjectId == id and CoopPlayers.GetPlayerByHero(candidate) then
                    triggerArgs = ShallowCopyTable(triggerArgs)
                    triggerArgs.OwnerTable = candidate
                    hero = candidate
                end
            end
            if chargeEvent and type(LocalDuoChargeOwnerTrace) == "function" then
                local weapon = hero and hero.WeaponDataOverride and hero.WeaponDataOverride[triggerArgs.name]
                    or WeaponData and WeaponData[triggerArgs.name]
                pcall(LocalDuoChargeOwnerTrace, {
                    Event = {Kind=name,Weapon=triggerArgs.name},
                    Actor = {TriggeredId=triggerArgs.triggeredById,OwnerId=hero and hero.ObjectId,
                        CurrentPlayer=hero and CoopPlayers.GetPlayerByHero(hero)},
                    Camera = {Path=hero and "effective-owner" or "global-no-owner",
                        Charge=weapon and weapon.ChargeCameraMotion and weapon.ChargeCameraMotion.Fraction,
                        Cancel=weapon and weapon.ChargeCancelCameraMotion and weapon.ChargeCancelCameraMotion.Fraction},
                })
            end

            if CoopPlayers.IsPlayerHero(hero) then
                HeroContext.RunWithHeroContext(hero, fun, triggerArgs)
            else
                fun(triggerArgs)
            end
        end

        if names then
            original { names, hook }
        else
            original { hook }
        end
    end
end

return HeroContextWrapper
