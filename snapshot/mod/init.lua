--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

-- Load menu and add gamemode button
local logPath = GetScriptDir() .. "/LocalDuo.log"
local function LocalDuoLog(message)
    if io and io.open then
        local file = io.open(logPath, "a")
        if file then file:write(message .. "\n"); file:close() end
    end
end
LocalDuoLog("Scripts Coop iniciados")
ModRequire "mainmenu/CoopMenu.lua"

-- Coop is opt-in through the actual selector's confirmed Gamemode token.
-- No config AutoEnable may convert a stock/normal nil selection into Coop.
local _, disabled = GetTempRuntimeData("TN_Coop:disabled")
LocalDuoCoopModeActive = false

-- Get current gamemode
local _, data = GetTempRuntimeData("Gamemode")
if data ~= "Coop" or disabled == true then
    LocalDuoLog("Modo solo selecionado")
    return
end

LocalDuoCoopModeActive = true -- derived only from the explicit confirmed selector token

-- Disable the gamemode for the next run
SetTempRuntimeData("Gamemode", nil)

-- Load gamemode hooks

if not CoopHasPlayer(2) then
    CoopCreatePlayer()
end

local ok, failure = pcall(function() (ModRequire "GamemodeInit.lua").Start() end)
if not ok then
    LocalDuoLog("ERRO: " .. tostring(failure))
    error(failure)
end
LocalDuoLog("Coop habilitado; dois controles configurados")
local testFlag=io.open(GetScriptDir().."/LocalDuoTestMode.flag","r")
if testFlag then
    testFlag:close()
    ModRequire "logic/LocalDuoTestHarness.lua"
end
