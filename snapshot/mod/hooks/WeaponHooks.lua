--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type HeroContextNative
local HeroContextNative = ModRequire "../logic/HeroContextNative.lua"

local hook = SimpleHook.New()

-- Fixes crashes when the game unload weapons that is currently equipped by another player
function hook.wrap.UnequipWeapon(baseFunc, args)
    if args.UnloadPackages == false then
        return baseFunc(args)
    end

    local toRemove = args.Names or { args.Name }

    local unit = args.DestinationId
    local hasAnotherPlayerThisWeapon = false

    for playerId, hero in CoopPlayers.PlayersIterator() do
        if hero.ObjectId == unit then
            goto continue
        end

        for _, name in ipairs(toRemove) do
            if hero.Weapons[name] then
                hasAnotherPlayerThisWeapon = true
                break
            end
        end

        ::continue::
    end

    args.UnloadPackages = not hasAnotherPlayerThisWeapon
    args.UnloadPackages = false

    return baseFunc(args)
end

function hook.wrap.GetWeaponChargeFraction(baseFun, args)
    return HeroContextNative.RunWithNativeHeroContextFromHero(baseFun, args)
end

function hook.wrap.GetAutoLockId(base,args)
    local arena=LocalDuoArenaRuntime
    if arena and type(arena.IsDuelSceneOwned)=='function'and arena:IsDuelSceneOwned() then
        if type(arena.GetPartnerAutoLock)=='function'then return arena:GetPartnerAutoLock(args)end
        return 0
    end
    local id=base(args)
    -- The actual actors can already be rebound before their registry metadata.
    local first,second=CoopPlayers.GetHero(1),CoopPlayers.GetHero(2)
    local function currentPlayerId(value)
        return value~=nil and ((first and first.ObjectId==value)or(second and second.ObjectId==value))
    end
    local function playerId(value)return currentPlayerId(value)or CoopPlayers.IsPlayerUnit(value)end
    if not playerId(id) then return id end
    local source=args.Id or CurrentRun.Hero.ObjectId
    -- Filtering the Lua return alone leaves the engine's cached partner focus intact.
    -- Clear ONLY an observed current partner target from a current player source.
    if id~=source and currentPlayerId(source)and currentPlayerId(id)then
        ClearAutoLock({Id=source}) -- Same explicit source-ID API used by stock EnemyAILogic.
    end
    local enemies=GetClosestIds({Id=source,DestinationName='EnemyTeam',Distance=args.Range or 1200,
        IgnoreSelf=true,IgnoreInvulnerable=true,IgnoreHomingIneligible=true})or{}
    for _,enemyId in ipairs(enemies)do
        local enemy=ActiveEnemies and ActiveEnemies[enemyId]
        if not playerId(enemyId) and enemy and not enemy.IsDead and not enemy.Charmed then
            local inArc=true
            if args.Arc then
                local bearing=GetAngleBetween({Id=source,DestinationId=enemyId})
                local facing=GetAngle({Id=source})
                local delta=math.abs((bearing-facing+180)%360-180)
                inArc=delta<=math.deg(args.Arc)
            end
            if inArc then return enemyId end
        end
    end
    return 0
end

function hook.wrap.PreLoadBinks(baseFun, args)
    if args.Cache == "WeaponCache" then
        return baseFun {
            Names = args.Names
            -- Do not reset
        }
    else
        return baseFun(args)
    end
end

return hook
