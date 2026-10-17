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
---@type CoopControl
local CoopControl = ModRequire "../logic/CoopControl.lua"
---@type GameStateEx
local GameStateEx = ModRequire "../logic/GameStateEx.lua"
-- All dependencies load at main initialization, before any menu/actor coroutine.
local ArcanaCoop = ModRequire "../logic/LocalDuoArcanaCoop.lua"
local ArcanaLobby = ModRequire "../logic/LocalDuoLobby.lua"
local PauseEnd = ModRequire "../logic/LocalDuoPauseEnd.lua"

---@class MenuHooks : SimpleHook
local MenuHooks = SimpleHook.New()

-- Native PauseScreen is not a Lua Open* coroutine: retain its opener until actual close.
local nativePause
local pauseCallbacksRegistered=false
local function pauseOwner(args)
    -- Native event opener packet is unobserved: do not infer ownership from args fields.
    local pad=LocalDuoPhysicalInput
    local schemas=CoopControl.Schemas.Current
    if pad and type(pad.read)=='function' and type(pad.devices)=='function' then
        local ok,catalog=pcall(pad.devices)
        if not ok or type(catalog)~='table' then return nil end
        local pressed,pressedIndex;local indices={}
        for owner=1,CoopPlayers.GetPlayersCount() do
            local schema=schemas[owner]
            if schema and schema.Device=='Gamepad' then
                if indices[schema.ControllerId] then return nil end
                indices[schema.ControllerId]=true
                local device
                for _,item in ipairs(catalog) do if item.Index==schema.ControllerId then device=item;break end end
                if device and device.Instance~=nil then
                    local read,raw=pcall(pad.read,schema.ControllerId)
                    if read and raw and raw.Connected==true and raw.Focused==true
                        and raw.Index==device.Index and raw.Instance==device.Instance and raw.Start==true then
                        if pressed then return nil end
                        pressed=owner;pressedIndex=schema.ControllerId
                    end
                end
            end
        end
        if LocalDuoPhysicalInput~=pad or CoopControl.Schemas.Current~=schemas then return nil end
        if pressed then
            local current=schemas[pressed]
            if current and current.Device=='Gamepad' and current.ControllerId==pressedIndex then return pressed end
            return nil
        end
    end
    -- Keyboard opening follows native J1; never guess J2 from default hero context.
    local owner=CoopPlayers.GetCurrentPlayerId()
    if owner==1 and schemas[1] and schemas[1].Device=='Keyboard' then return 1 end
    return nil
end
function MenuHooks.NativePauseOpened(args)
    PauseEnd.Opened()
    if LocalDuoCoopModeActive~=true then return end
    if nativePause or CoopPlayers.GetPlayersCount()<2 then return end
    local owner=pauseOwner(args);if not owner then return end
    nativePause={Owner=owner,Stack=CoopControl.MenuOwners}
    nativePause.Frame=CoopControl.PushMenuOwner(owner)
end
local function releasePauseOwner()
    local owned=nativePause;nativePause=nil
    if not owned or not owned.Frame or CoopControl.MenuOwners~=owned.Stack then return end
    for _,frame in ipairs(owned.Stack) do
        if frame==owned.Frame then CoopControl.PopMenuOwner(owned.Frame);return end
    end
    -- Main menu reset/foreign removal owns routing now: do not reset someone else's stack.
end

function MenuHooks.NativePauseClosed()
    releasePauseOwner()
    PauseEnd.Closed()
end

-- EngineInit runs from Gamemode.Start on the main Lua load, before the
-- transient OnPreThingCreation callback installs the gameplay hooks. Native
-- menu scripts retain their registering lua_State; do not register them there.
function MenuHooks:InitEngineHooks()
    if not pauseCallbacksRegistered then
        pauseCallbacksRegistered=true
        OnMenuOpened {"PauseScreen", function(args)MenuHooks.NativePauseOpened(args)end}
        OnMenuCloseFinished {"PauseScreen", function(args)MenuHooks.NativePauseClosed(args)end}
    end
end

function MenuHooks.InitGameHooks()
    MenuHooks.HookUiControl("OpenKeepsakeRackScreen")
    MenuHooks.HookUiControl("OpenWeaponShopScreen")
    MenuHooks.HookUiControl("OpenCosmeticsShopScreen")
    MenuHooks.HookUiControl("ShowBoonInfoScreen")
    MenuHooks.HookUiControl("OpenBountyBoardScreen")
    MenuHooks.HookUiControl("OpenCodexScreen")
    MenuHooks.HookUiControl("OpenElementalPromptScreen")
    MenuHooks.HookUiControl("OpenFamiliarCostumeScreen")
    MenuHooks.HookUiControl("OpenFamiliarShopScreen")
    MenuHooks.HookUiControl("OpenGameStatsScreen")
    MenuHooks.HookUiControl("OpenGhostAdminScreen")
    MenuHooks.HookUiControl("OpenMailboxScreen")
    MenuHooks.HookUiControl("OpenMarketScreen")
    MenuHooks.HookUiControl("OpenMusicPlayerScreen")
    MenuHooks.HookUiControl("OpenQuestLogScreen")
    MenuHooks.HookUiControl("OpenInventoryScreen")
    MenuHooks.HookUiControl("OpenRunHistoryScreen")
    MenuHooks.HookUiControl("OpenSellTraitMenu")
    MenuHooks.HookUiControl("OpenShrineScreen")
    MenuHooks.HookUiControl("OpenSpellScreen")
    MenuHooks.HookUiControl("ShowStoreScreen")
    MenuHooks.HookUiControl("ShowSurfaceShopScreen")
    MenuHooks.HookUiControl("OpenTalentScreen")
    MenuHooks.HookUiControl("OpenMetaUpgradeCardScreen")
    MenuHooks.HookUiControl("OpenTradeScreen")
    MenuHooks.HookUiControl("OpenTraitTrayScreen")
    MenuHooks.HookUiControl("OpenRunClearScreen")
    MenuHooks.HookUiControl("OpenUpgradeChoiceMenu")
    MenuHooks.HookUiControl("PlayTextLines")
    MenuHooks.HookUiControl("OpenWeaponUpgradeScreen")
end

---@private
---@param funName string
function MenuHooks.HookUiControl(funName)
    HookUtils.wrap(funName, function(originalFun, ...)
        -- Duo Arcana owns TWO independent readers, never the stock single-owner remap.
        if funName=="OpenMetaUpgradeCardScreen" and ArcanaCoop.IsAvailable()then
            return originalFun(...)
        end
        local frame = CoopControl.PushMenuOwner(CoopPlayers.GetCurrentPlayerId())
        local result = table.pack(pcall(originalFun, ...))
        CoopControl.PopMenuOwner(frame)
        if not result[1] then error(result[2]) end
        return table.unpack(result, 2, result.n)
    end)
end

function MenuHooks.wrap.OpenMetaUpgradeCardScreen(base,...)
    if ArcanaCoop.IsAvailable() then
        return ArcanaCoop.Open(ArcanaLobby,{})
    end
    local player=CoopPlayers.GetCurrentPlayerId() or 1
    local scope=GameStateEx.BeginArcanaScope(player)
    local params=table.pack(...)
    local result=table.pack(pcall(function()
        -- Capture J1 before reflecting J2's traits into the shared base menu.
        GameStateEx.CopyTraitsToMetaUpgrades(CurrentRun.Hero)
        return base(table.unpack(params,1,params.n))
    end))
    GameStateEx.EndArcanaScope(scope)
    if not result[1] then error(result[2]) end
    return table.unpack(result,2,result.n)
end

function MenuHooks.wrap.OpenKeepsakeRackScreen(baseFun, ...)
    local playerId = CoopPlayers.GetCurrentPlayerId()

    if playerId == 1 then
        baseFun(...)
        return
    end

    local key = "LastAwardTraitCoopPlayer" .. playerId
    local prevGift = GameState.LastAwardTrait
    local currentGift = GameState[key]

    GameState.LastAwardTrait = currentGift

    local result = table.pack(pcall(baseFun, ...))

    GameState[key] = GameState.LastAwardTrait
    GameState.LastAwardTrait = prevGift
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

function MenuHooks.wrap.OpenSellTraitMenu(base, ...)
    local playerId = CoopPlayers.GetPlayerByHero(HeroContext.GetCurrentHeroContext()) or 1
    if playerId <= 1 then return base(...) end

    local run = CurrentRun
    local currentRoom = run.CurrentRoom
    local key = "SellOptions" .. playerId
    local backup = currentRoom.SellOptions
    currentRoom.SellOptions = currentRoom[key]

    local result = table.pack(pcall(base, ...))
    -- Only persist the personal result while this is still the captured menu room.
    -- Never take options from or write through a replacement CurrentRun/room.
    if CurrentRun == run and run.CurrentRoom == currentRoom then
        currentRoom[key] = currentRoom.SellOptions
    end
    -- Always release the borrowed shared slot, including on error/scene change.
    currentRoom.SellOptions = backup
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end

function MenuHooks.wrap.DisplayTextLine(baseFun, screen, source, line, parentLine)
    if line.Choices then
        -- Only this solution works
        SetConfigOption { Name = "AllowControlHotSwap", Value = false }

        HookUtils.onPreFunctionOnce("UnfreezePlayerUnit", function(name)
            if name == "PlayTextLines" then
                SetConfigOption { Name = "AllowControlHotSwap", Value = false }
            end
        end)
    end
    baseFun(screen, source, line, parentLine)
end

function MenuHooks.pre.OnScreenOpened(screen)
    DebugPrint { Text = "OnScreenOpened:  " .. tostring(screen.Name) }
end

return MenuHooks
