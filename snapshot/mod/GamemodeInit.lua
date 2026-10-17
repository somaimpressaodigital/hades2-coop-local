--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type HeroEx
local HeroEx = ModRequire "logic/HeroEx.lua"
---@type CoopGame
local CoopGame = ModRequire "logic/CoopGame.lua"
---@type HookStorage
local HookStorage = ModRequire "utils/HookStorage.lua"
---@type Events
local Events = ModRequire "logic/Events.lua"
---@type ILootDelivery
local LootInterface = ModRequire "logic/loot/LootInterface.lua"
---@type HeroContext
local HeroContext = ModRequire "logic/HeroContext.lua"
---@type CoopCamera
local CoopCamera = ModRequire "logic/CoopCamera.lua"
local CoopControl=ModRequire "logic/CoopControl.lua"

local PersonalWeapons=ModRequire "logic/LocalDuoPersonalWeaponSelections.lua"
local PersonalRerolls=ModRequire "logic/LocalDuoPersonalRerolls.lua"
local RerollPlayers=ModRequire "logic/CoopPlayers.lua"
local PersonalRecolorV2=ModRequire "logic/PersonalRecolorV2.lua"
local Gamemode = {}

function Gamemode.Start()
    PersonalRerolls.Configure(RerollPlayers,HeroContext)
    -- OFF by default; binding performs no asset load or texture application.
    PersonalRecolorV2.Bind(_G,RerollPlayers,ModRequire "config.lua")
    -- Explicit human request: enable the new personal J2 recolor.
    PersonalRecolorV2.SetPersonalEnabled(true)
    Gamemode.RegisterHooks()
    HookStorage.EngineInit()
    Gamemode.RegisterEngineHandlers()
end

---@private
function Gamemode.RegisterHooks()
    HookStorage.Add "hooks/EngineHooks.lua"
    HookStorage.Add "hooks/ThreadSplitHooks.lua"
    HookStorage.Add "hooks/FreezeHooks.lua"
    HookStorage.Add "hooks/RunHooks.lua"
    HookStorage.Add "hooks/MenuHooks.lua"
    HookStorage.Add "hooks/SaveHooks.lua"
    HookStorage.Add "hooks/EnemyAiHooks.lua"
    HookStorage.Add "hooks/LootHooks.lua"
    HookStorage.Add "hooks/UIHooks.lua"
    HookStorage.Add "hooks/VulnerabilityHooks.lua"
    HookStorage.Add "hooks/ResourceLoadingHooks.lua"
    HookStorage.Add "hooks/MapStateHooks.lua"
    HookStorage.Add "hooks/PlayerVisibilityHooks.lua"
    HookStorage.Add "hooks/CameraHooks.lua"

    HookStorage.Add "hooks/DamageHooks.lua"
    HookStorage.Add "hooks/InteractLogicHooks.lua"
    HookStorage.Add "hooks/ControlHooks.lua"
    HookStorage.Add "hooks/WeaponHooks.lua"
    HookStorage.Add "hooks/WeaponLogicHooksLob.lua"
    HookStorage.Add "hooks/EffectHooks.lua"
    HookStorage.Add "hooks/FamilliarHooks.lua"

    HookStorage.Add "hooks/AnaimationSwapHook.lua"
    HookStorage.Add "hooks/LocalDuoHooks.lua"
end

---@private
function Gamemode.RegisterEngineHandlers()
    local hooksInited = false
    local function TryInstalBasicHooks()
        if LocalDuoCoopModeActive~=true then return end
        if hooksInited then
            return
        end

        hooksInited = true
        Events.engine:trigger("hooksPreInicialized")

        HeroContext.InitHooks()
        HeroEx.SaveUnhookedFunctions()

        HookStorage.GameInit()

        CoopCamera.InitHooks()
        LootInterface.InitHooks()

        CoopGame.Init()

        Events.engine:trigger("hooksInicialized")
    end

    OnPreThingCreation
    {
        TryInstalBasicHooks
    }

    OnAnyLoad {
        function(triggerArgs)
            if LocalDuoCoopModeActive==true then Events.run:trigger("mapLoaded", triggerArgs.name) end
        end
    }

    OnMenuOpened {
        "MainMenuScreen",
        function(triggerArgs)
            PersonalWeapons.Detach() -- restore exact owned J1 stock fields before Solo dispatch
            -- Retire the owned HUD before Solo makes draw/tick hooks dormant.
            local hud=LocalDuoHudRuntime
            if type(hud)=='table'and type(hud.Stop)=='function'then
                local ok,why=pcall(hud.Stop,hud)
                if not ok then LocalDuoSoloHudCleanupError=tostring(why)end
            end
            LocalDuoCoopModeActive=false -- back at native menu; wait for explicit next Coop selection
            CoopControl.MenuOwners = {}
            CoopSetPlayerGamepad(1, 0)
            if CoopHasPlayer(2) then CoopSetPlayerGamepad(2, 5) end
            SetConfigOption { Name = "AllowControlHotSwap", Value = true }
        end
    }
end

return Gamemode
