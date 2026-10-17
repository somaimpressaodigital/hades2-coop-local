--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class HookUtils
local HookUtils = {}
local function coopActive()
    if LocalDuoCoopModeActive~=true or type(CoopGetPlayersCount)~='function' then return false end
    local ok,count=pcall(CoopGetPlayersCount)
    return ok and type(count)=='number' and count>=2
end

---@param funcName string
---@param handler function
function HookUtils.onPostFunctionOnce(funcName, handler)
    local original = _G[funcName]

    if not original then
        return
    end

    _G[funcName] = function(...)
        if not coopActive() then return original(...) end
        _G[funcName] = original
        original(...)
        handler(...)
    end
end

---@param funcName string
---@param handler function
function HookUtils.onPreFunction(funcName, handler)
    local original = _G[funcName]

    if not original then
        return
    end

    _G[funcName] = function(...)
        if not coopActive() then return original(...) end
        handler(...)
        return original(...)
    end
end

---@param funcName string
---@param handler function
function HookUtils.onPostFunction(funcName, handler)
    local original = _G[funcName]

    if not original then
        return
    end

    _G[funcName] = function(...)
        if not coopActive() then return original(...) end
        local result = original(...)
        handler(...)
        return result
    end
end

---@param funcName string
---@param handler function
function HookUtils.onPreFunctionOnce(funcName, handler)
    local original = _G[funcName]

    if not original then
        return
    end

    _G[funcName] = function(...)
        if not coopActive() then return original(...) end
        _G[funcName] = original
        handler(...)
        original(...)
    end
end

---@param funcName string
---@param handler fun(basefun: function, ...): any
function HookUtils.wrap(funcName, handler)
    local original = _G[funcName]

    if not original then
        error("Cannot wrap function: " .. tostring(funcName))
    end

    _G[funcName] = function(...)
        if not coopActive() then return original(...) end
        return handler(original, ...)
    end
end

---@param funcName string
---@param handler fun(basefun: function, ...): any
function HookUtils.wrapOnce(funcName, handler)
    local original = _G[funcName]

    if not original then
        error("Cannot wrap function: " .. tostring(funcName))
    end

    _G[funcName] = function(...)
        if not coopActive() then return original(...) end
        local result = { handler(original, ...) }
        _G[funcName] = original
        return table.unpack(result)
    end
end

---@param funcName string
---@param handler fun(...): any
function HookUtils.replace(funcName, handler)
    local original=_G[funcName]
    _G[funcName]=function(...)
        if not coopActive() then if original then return original(...) end;return end
        return handler(...)
    end
end

return HookUtils

