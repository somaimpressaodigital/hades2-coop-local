--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type HeroContext
local HeroContext = ModRequire "../logic/HeroContext.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"
---@type HeroContextProxyStore
local HeroContextProxyStore = ModRequire "../logic/HeroContextProxyStore.lua"

---@class ResourceLoadingHooks : SimpleHook
local ResourceLoadingHooks = SimpleHook.New()
local PersonalRecolorV2=ModRequire "../logic/PersonalRecolorV2.lua"

function ResourceLoadingHooks.wrap.LoadSpawnPackages(baseFun, encounter)
    for playerId, hero in CoopPlayers.PlayersIterator() do
        HeroContext.RunWithHeroContext(hero, baseFun, encounter)
    end
end

function ResourceLoadingHooks.post.DoPatches()
    local lootHistory = HeroContextProxyStore.Get("LootTypeHistory")

    if not lootHistory then
        return
    end

    for playerId = 1, CoopPlayers.GetPlayersCount() do
        for lootName, i in pairs(lootHistory:GetPlayerData(playerId)) do
            if not GameData.MissingPackages[lootName] then
                LoadPackages { Name = lootName }
            end
        end
    end
end

-- The stock OnAnyLoad resource callback is the ONLY recolor load/inspect/apply seam.
function ResourceLoadingHooks.post.LoadCurrentRoomResources(currentRoom)
    -- Optional cosmetic failure must not block room setup or progression.
    pcall(PersonalRecolorV2.AfterRoomResourcesLoaded,currentRoom)
end

-- Only a real stock hub transition may authorize a nil Names collection.
-- This marker owns no native handle or readiness; it expires when stock returns.
local hubTransition
function ResourceLoadingHooks.pre.DeathAreaRoomTransition(source)
    hubTransition=nil
    if LocalDuoCoopModeActive~=true or type(source)~="table"
        or(source.Name~="Hub_Main"and source.Name~="Hub_PreRun")
        or type(HubRoomData)~="table"or not HubRoomData[source.Name]
        or type(CurrentRun)~="table"or type(MapState)~="table"or type(SessionMapState)~="table"then return end
    hubTransition={Source=source,Run=CurrentRun,Map=MapState,Session=SessionMapState,Owner=coroutine.running()}
end
function ResourceLoadingHooks.post.DeathAreaRoomTransition(source)
    local scope=hubTransition
    if scope and scope.Source==source and scope.Owner==coroutine.running()then hubTransition=nil end
end
function ResourceLoadingHooks.post.LoadPackages(args)
    local scope=hubTransition
    if not scope or scope.Owner~=coroutine.running()or LocalDuoCoopModeActive~=true
        or CurrentRun~=scope.Run or MapState~=scope.Map or SessionMapState~=scope.Session
        or CurrentHubRoom~=scope.Source or type(args)~="table"or args.Name~=nil
        or args.Names~=scope.Source.LoadPackages then return end
    -- Hub_PreRun has nil LoadPackages. Nil is accepted ONLY in this exact owned
    -- transition. Private package requests have singular Name and cannot recurse.
    pcall(PersonalRecolorV2.AfterRoomResourcesLoaded,scope.Source)
end

return ResourceLoadingHooks
