--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type Events
local Events = ModRequire "../logic/Events.lua"
local GameStateEx=ModRequire "../logic/GameStateEx.lua"

---@class SaveHooks : SimpleHook
local SaveHooks = SimpleHook.New()

function SaveHooks.wrap.Save(baseFun)
    local personal=GameStateEx.SuspendArcanaForSave()
    Events.engine:trigger("presave")
    local result=table.pack(pcall(baseFun))
    Events.engine:trigger("postsave")
    GameStateEx.ResumeArcanaAfterSave(personal)
    if not result[1] then error(result[2]) end
    return table.unpack(result,2,result.n)
end

return SaveHooks
