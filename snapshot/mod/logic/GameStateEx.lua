--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class GameStateEx
local GameStateEx = {}
GameStateEx.ArcanaScopes={}

local function snapshot()
    local state={Equipped={},Layouts=GameState.SavedMetaUpgradeLayouts,Layout=GameState.CurrentMetaUpgradeLayout}
    for name,data in pairs(GameState.MetaUpgradeState or {}) do state.Equipped[name]=data.Equipped==true end
    return state
end
local function restore(state)
    for name,data in pairs(GameState.MetaUpgradeState or {}) do data.Equipped=state.Equipped[name] or nil end
    GameState.SavedMetaUpgradeLayouts=state.Layouts
    GameState.CurrentMetaUpgradeLayout=state.Layout
    -- Adjacency depends on the equipped owner; never reuse the partner cache.
    if GameState.MetaUpgradeState and GameState.MetaUpgradeCardLayout then
        UpdateMetaUpgradeCardAdjacencyBonuses()
    end
end
function GameStateEx.BeginArcanaScope(player)
    local scope={Player=player,Before=snapshot()}
    table.insert(GameStateEx.ArcanaScopes,scope)
    GameState.LocalDuoArcanaLayouts=GameState.LocalDuoArcanaLayouts or {}
    if player>1 then
        local personal=GameState.LocalDuoArcanaLayouts[player]
        GameState.SavedMetaUpgradeLayouts=DeepCopyTable(personal and personal.Layouts or GameState.SavedMetaUpgradeLayouts or {})
        GameState.CurrentMetaUpgradeLayout=personal and personal.Layout or GameState.CurrentMetaUpgradeLayout
    end
    return scope
end
function GameStateEx.EndArcanaScope(scope)
    GameState.LocalDuoArcanaLayouts[scope.Player]=snapshot()
    if scope.Player>1 then restore(scope.Before) end
    for i=#GameStateEx.ArcanaScopes,1,-1 do
        if GameStateEx.ArcanaScopes[i]==scope then table.remove(GameStateEx.ArcanaScopes,i);break end
    end
end
function GameStateEx.SuspendArcanaForSave()
    local scope=GameStateEx.ArcanaScopes[1]
    if not scope or scope.Player==1 then return end
    local personal=snapshot()
    GameState.LocalDuoArcanaLayouts[scope.Player]=personal
    restore(scope.Before)
    return personal
end
function GameStateEx.ResumeArcanaAfterSave(personal)
    if personal then restore(personal) end
end
function GameStateEx.WithPersonalArcana(player,fun,...)
    local personal=GameState.LocalDuoArcanaLayouts and GameState.LocalDuoArcanaLayouts[player]
    if not personal or player==1 then return fun(...) end
    local before=snapshot()
    restore(personal)
    local result=table.pack(pcall(fun,...))
    restore(before)
    if not result[1] then error(result[2]) end
    return table.unpack(result,2,result.n)
end
function GameStateEx.MoveMelinoeArcana(fromPlayer,toPlayer,hero)
    GameState.LocalDuoArcanaLayouts=GameState.LocalDuoArcanaLayouts or {}
    local personal=DeepCopyTable(GameState.LocalDuoArcanaLayouts[fromPlayer] or snapshot())
    personal.Equipped={}
    local traits={}
    for _,trait in ipairs(hero.Traits or {})do traits[trait.Name]=true end
    for name,data in pairs(MetaUpgradeCardData or {})do
        personal.Equipped[name]=data.TraitName and traits[data.TraitName] or false
    end
    GameState.LocalDuoArcanaLayouts[toPlayer]=personal
    if toPlayer==1 then restore(personal) end
end

function GameStateEx.CopyTraitsToMetaUpgrades(hero)
    local metaUpgrades = GameState.MetaUpgradeState

    local traitToMeta = {}

    for name, data in pairs(MetaUpgradeCardData) do
        local upgarde = metaUpgrades[name]
        if upgarde then
            upgarde.Equipped = false
        end
        if data.TraitName then
            traitToMeta[data.TraitName] = upgarde
        end
    end

    for k, trait in ipairs(hero.Traits) do
        local upgrade = traitToMeta[trait.Name]
        if upgrade then
            upgrade.Equipped = true
        end
    end
end

return GameStateEx
