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
---@type PlayerVisibilityHelper
local PlayerVisibilityHelper = ModRequire "../logic/PlayerVisibilityHelper.lua"
local personalRecolor = ModRequire "../logic/PersonalRecolorV2.lua"

---@class PlayerVisibilityHooks : SimpleHook
local PlayerVisibilityHooks = SimpleHook.New()
local function restorePersonalTexture()
    local hero=HeroContext.GetCurrentHeroContext()
    if hero then personalRecolor.ApplyPersonal(hero) end
end
-- Native gameplay flags and temporary forms stay stock. Presentation only
-- reapplies to the registered current J2, never J1 by default.
PlayerVisibilityHooks.post.SetPlayerDarkside=restorePersonalTexture
PlayerVisibilityHooks.post.SetupCostume=restorePersonalTexture
-- Vanilla clears PolymorphType AFTER SetupCostume; restore only after that cleanup.
PlayerVisibilityHooks.post.HecatePolymorphClear=restorePersonalTexture
PlayerVisibilityHooks.post.ChronosPolymorphClear=restorePersonalTexture

---@private
function PlayerVisibilityHooks.post.SetPlayerUnDarkside()
    local hero=HeroContext.GetCurrentHeroContext()
    if hero and IsEmpty(SessionMapState.DarkSide) then
        local player=CoopPlayers.GetPlayerByHero(hero)
        if player==2 then personalRecolor.ApplyPersonal(hero)
        else PlayerVisibilityHelper.TriggerOutline(player,hero.ObjectId) end
    end
end
function PlayerVisibilityHooks.pre.LoadMap()
    -- Native Main.lua LoadMap does not call LoadMapInternal until after its first yield.
    -- Cosmetic cleanup cannot block a real map transition if the optional provider fails.
    pcall(personalRecolor.BeforeNativeMapLoad)
end

return PlayerVisibilityHooks
