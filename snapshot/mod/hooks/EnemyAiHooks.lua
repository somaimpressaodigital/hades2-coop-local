--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type HeroContext
local HeroContext = ModRequire "../logic/HeroContext.lua"

---@class EnemyAiHooks : SimpleHook
local EnemyAiHooks = SimpleHook.New()

function EnemyAiHooks:InitGameHooks()
    HeroContext.SetWorldHeroProvider(function(enemyId)
        if enemyId then return EnemyAiHooks.getNearestHero(enemyId) end
        return CoopPlayers.GetFirstAliveHero()
    end)
    local HookUtils = ModRequire "../utils/HookUtils.lua"
    for _, name in ipairs({"StartEncounter", "SetupAI", "StagedAI", "SetAI",
        "CheckCancelSpawns", "GetRemainingSpawns", "CheckForEncounterEnemiesDead"}) do
        if _G[name] then
            HookUtils.wrap(name, function(base, ...)
                return HeroContext.RunWithWorldContext(base, ...)
            end)
        end
    end
end

---@private
---@param unitId integer
function EnemyAiHooks.getNearestHero(unitId)
    local nearest
    local distance = 99999

    for playerId = 1, CoopPlayers.GetPlayersCount() do
        local hero = CoopPlayers.GetHero(playerId)
        if not hero or hero.IsDead or (hero.Health and hero.Health<=0) or not hero.ObjectId then
            goto continue
        end
        local thisDistance = GetDistance { Id = hero.ObjectId, DestinationId = unitId }
        if thisDistance <= distance then
            nearest = hero
            distance = thisDistance
        end
        ::continue::
    end

    return nearest or HeroContext.GetDefaultHero()
end

---@private
---@param baseFun function
---@param enemy table
---@param weaponAiData table?
---@return integer
function EnemyAiHooks.wrap.GetTargetId(baseFun, enemy, weaponAiData)
    local hero = EnemyAiHooks.getNearestHero(enemy.ObjectId)
    -- Combat player-target branch must not lock onto an untargetable nearer partner.
    -- Stock GetTargetId(TargetPlayer=true) overrides its initial UntargetableFlags check.
    if LocalDuoCoopModeActive==true and not CurrentHubRoom and enemy.RequiredKill==true
        and CurrentRun and CurrentRun.CurrentRoom and not CurrentRun.CurrentRoom.InStageTransition
        and not CurrentRun.CurrentRoom.BlockAggro and not CurrentRun.CurrentRoom.BossKillPresentation
        and ActiveEnemies and ActiveEnemies[enemy.ObjectId]==enemy and not enemy.IsDead and not enemy.Charmed
        and weaponAiData and weaponAiData.TargetPlayer==true then
        local eligible,distance=nil,math.huge
        for p=1,CoopPlayers.GetPlayersCount() do
            local candidate=CoopPlayers.GetHero(p)
            if candidate and not candidate.IsDead and candidate.ObjectId and (not candidate.Health or candidate.Health>0)
                and not next(candidate.UntargetableFlags or {}) then
                local allowed=true
                if weaponAiData.IgnoreInvulnerable then allowed=IsInvulnerable({Id=candidate.ObjectId})==false end
                if allowed then
                    local value=GetDistance({Id=candidate.ObjectId,DestinationId=enemy.ObjectId})
                    if type(value)=='number' and value>=0 and value<math.huge and value<=distance then eligible=candidate;distance=value end
                end
            end
        end
        if eligible then hero=eligible end -- preserve stock behavior if no candidate is eligible
    end
    local target=HeroContext.RunWithHeroContextReturn(hero, baseFun, enemy, weaponAiData)
    enemy.LocalDuoTargetId=target
    return target
end

---@private
---@param baseFun function
---@param params table
function EnemyAiHooks.wrap.NotifyWithinDistance(baseFun, params)
    if params.Notify == "ContractOpen" then
        -- Skip pact door
        baseFun(params)
        return
    end

    if CoopPlayers.IsPlayerUnit(params.DestinationId) then
        params.DestinationId = nil
        params.DestinationIds = {}
        for _,hero in ipairs(CoopPlayers.GetAliveHeroes()) do
            if hero.ObjectId then table.insert(params.DestinationIds,hero.ObjectId) end
        end
        params.Ids = params.Ids or { params.Id }
        params.Id = nil
        NotifyWithinDistanceAny(params)
    else
        baseFun(params)
    end
end

function EnemyAiHooks.wrap.NotifyOutsideDistance(baseFun, params)
    if CoopPlayers.IsPlayerUnit(params.DestinationId) then
        local origin=params.Id or (params.Ids and params.Ids[1])
        local hero=origin and EnemyAiHooks.getNearestHero(origin) or CoopPlayers.GetFirstAliveHero()
        if hero then params.DestinationId=hero.ObjectId end
    end
    return baseFun(params)
end

function EnemyAiHooks.wrap.IsAIActive(baseFun, ...)
    -- Suspend this enemy's coroutine while UI is open instead of changing
    -- thread time multipliers or ending the AI loop.
    local _, isMain = coroutine.running()
    local enemy=...
    while enemy and enemy.RequiredKill and not isMain and (LocalDuoPreparationPending or AreScreensActive())
        and CoopPlayers.HasAlivePlayers() do
        waitUnmodified(0.05)
    end
    local alivePlayer = CoopPlayers.GetAliveHeroes()[1]
    if alivePlayer then
        return HeroContext.RunWithHeroContextReturn(alivePlayer, baseFun, ...)
    else
        return baseFun(...)
    end
end

return EnemyAiHooks
