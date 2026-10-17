--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type Events
local Events = ModRequire "Events.lua"
---@type TableUtils
local TableUtils = ModRequire "../utils/TableUtils.lua"

---@class HeroContext
local HeroContext = {}

local CorontinueToHero = setmetatable({}, { __mode ="k" })
local WorldThreads = setmetatable({}, { __mode = "k" })
local worldHeroProvider
local serviceDispatcher
local ArenaLeaseContext -- nil preserves the campaign dispatcher path
local ArenaLeaseInitialized = false

function HeroContext.SetArenaLeaseContext(instance)
    assert(not ArenaLeaseInitialized, "Lease seam must be configured before InitHooks")
    assert(instance == nil or (instance.Enabled == true
        and type(instance.WrapThread) == "function"
        and type(instance.WrapResume) == "function"
        and type(instance.AfterYield) == "function"
        and type(instance.RecordInstalledDispatchers) == "function"), "Actual lease context required")
    ArenaLeaseContext = instance
end

local defaultHero

local RunMT = {
    __index = function(self, key)
        if key == "Hero" then
            return HeroContext.GetCurrentHeroContext()
        end

        return rawget(self, key)
    end;
}

function HeroContext.InitHooks()
    local _thread = thread
    ArenaLeaseInitialized = true
    if ArenaLeaseContext then
        _thread = ArenaLeaseContext.WrapThread(_thread)
        resume = ArenaLeaseContext.WrapResume(resume)
    end
    serviceDispatcher = _thread
    thread = function(fun, ...)
        local heroContext = CorontinueToHero[coroutine.running()]
        local worldContext = WorldThreads[coroutine.running()]
        if heroContext or worldContext then
            _thread(function(...)
                local thread = coroutine.running()
                CorontinueToHero[thread] = heroContext
                WorldThreads[thread] = worldContext
                fun(...)
                CorontinueToHero[thread] = nil
                WorldThreads[thread] = nil
            end, ...)
        else
            _thread(fun, ...)
        end
    end

    local coroutine_yield = coroutine.yield
    ---@diagnostic disable-next-line: duplicate-set-field
    coroutine.yield = function(params)
        if params == "task done" then
            CorontinueToHero[coroutine.running()] = nil
            WorldThreads[coroutine.running()] = nil
        end
        if not ArenaLeaseContext then return coroutine_yield(params) end
        local out = table.pack(coroutine_yield(params))
        ArenaLeaseContext.AfterYield(coroutine.running())
        return table.unpack(out, 1, out.n)
    end

    if ArenaLeaseContext then
        ArenaLeaseContext.RecordInstalledDispatchers(thread, resume, coroutine.yield, serviceDispatcher)
    end
    Events.run:on("newRunStarted", HeroContext.InitRunHook)
    if CurrentRun then
        HeroContext.InitRunHook()
    end
end

-- Session verifies private world roots before calling this rebind. Existing
-- coroutine identities remain available for observed native cancellation.
function HeroContext.BindOwnedRunPreservingCoroutines(run, hero)
    assert(type(run) == "table" and type(hero) == "table"
        and CurrentRun == run and rawget(run, "Hero") == hero, "Actual new run/hero required")
    defaultHero = hero
    rawset(run, "Hero", nil)
    setmetatable(run, RunMT)
    return true
end

function HeroContext.InitRunHook()
    TableUtils.clean(CorontinueToHero)
    TableUtils.clean(WorldThreads)
    local hero = rawget(CurrentRun, "Hero")
    if not hero then
        error("Current run has no hero")
    end

    defaultHero = hero
    CurrentRun.Hero = nil
    setmetatable(CurrentRun, RunMT)
end

function HeroContext.GetCurrentHeroContext()
    local thread, isMain = coroutine.running()
    if not isMain then
        local hero = CorontinueToHero[thread] or defaultHero
        local world = WorldThreads[thread]
        if type(world)=="table" and world.Enemy and worldHeroProvider then
            return worldHeroProvider(world.Enemy.ObjectId) or hero
        end
        if WorldThreads[thread] and hero and hero.IsDead and worldHeroProvider then
            return worldHeroProvider() or hero
        end
        return hero
    end

    return defaultHero
end

-- Exact coroutine context access for observed native scheduler cancellation.
-- No coroutine is resumed or killed, and active/foreign scheduler entries refuse cleanup.
function HeroContext.ReadCoroutineContext(co)
    assert(type(co)=="thread", "Actual coroutine required")
    return {Hero=CorontinueToHero[co],World=WorldThreads[co]}
end
function HeroContext.ReleaseCancelledCoroutine(co, expectedHero, expectedWorld)
    if type(co)~="thread" or co==coroutine.running() then return false end
    if type(_threads)~="table" or type(_workingThreads)~="table" or type(_eventListeners)~="table" then return false end
    for _, list in ipairs({_threads,_workingThreads}) do
        for _, info in pairs(list) do if info.thread==co then return false end end
    end
    for _, list in pairs(_eventListeners) do
        for _, info in pairs(list) do if info.Thread==co then return false end end
    end
    if CorontinueToHero[co]~=expectedHero or WorldThreads[co]~=expectedWorld then return false end
    CorontinueToHero[co]=nil;WorldThreads[co]=nil
    return true
end

-- Engine services are independent of the initiating actor/narrative coroutine.
-- Preserve actual native dispatcher returns; explicit hero operations stay contextual.
function HeroContext.ScheduleServiceThread(fun, ...)
    assert(serviceDispatcher and type(fun)=="function", "Native service dispatcher unavailable")
    return serviceDispatcher(fun, ...)
end

function HeroContext.SetWorldHeroProvider(provider)
    worldHeroProvider = provider
end

-- Enemy and encounter coroutines must follow a surviving hero dynamically.
-- Explicit actor callbacks (damage, rewards, menus) keep their own identity.
function HeroContext.RunWithWorldContext(fun, ...)
    local co, isMain = coroutine.running()
    if isMain then return fun(...) end
    local previous = WorldThreads[co]
    local first,second = ...
    local enemy=type(first)=="table" and first or (type(second)=="table" and second)
    if enemy and enemy.ObjectId and enemy.RequiredKill and (enemy.AIOptions or enemy.AIBehavior or enemy.AIStages or enemy.AIThreadName) then
        WorldThreads[co] = {Enemy=enemy}
    else WorldThreads[co] = previous or true end
    local result = table.pack(pcall(fun, ...))
    WorldThreads[co] = previous
    if not result[1] then error(result[2]) end
    return table.unpack(result, 2, result.n)
end

function HeroContext.IsHeroContextExplicit()
    local thread, isMain = coroutine.running()
    if not isMain then
        return CorontinueToHero[thread] and true
    end
    return false
end

function HeroContext.SetDefaultHero(hero)
    defaultHero = hero
end

function HeroContext.GetDefaultHero()
    return defaultHero
end

---@param hero table Hero info
---@param fun function
---@param ... unknown params
function HeroContext.RunWithHeroContext(hero, fun, ...)
    thread(function(...)
        local thread = coroutine.running()
        CorontinueToHero[thread] = hero
        WorldThreads[thread] = nil
        fun(...)
        CorontinueToHero[thread] = nil
        WorldThreads[thread] = nil
    end, ...)
end

---@param hero table Hero info
---@param fun function
---@param ... unknown params
---@return ...
function HeroContext.RunWithHeroContextReturn(hero, fun, ...)
    local out = {}
    HeroContext.RunWithHeroContext(hero, function(...)
        out = { fun(...) }
    end, ...)

    return table.unpack(out)
end

local awaitableThreadId = 0

---@param hero table Hero info
---@param fun function
---@param ... unknown params
function HeroContext.RunWithHeroContextAwait(hero, fun, ...)
    awaitableThreadId = awaitableThreadId + 1
    local notifyName = "RunWithHeroContextAwait" .. awaitableThreadId
    local done = false

    local out = {}
    thread(function(...)
        local thread = coroutine.running()
        CorontinueToHero[thread] = hero
        WorldThreads[thread] = nil
        out = table.pack(pcall(fun, ...))
        CorontinueToHero[thread] = nil
        WorldThreads[thread] = nil
        notifyExistingWaiters(notifyName)
        done = true
    end, ...)

    if not done then
        waitUntil(notifyName)
    end

    if not out[1] then error(out[2]) end
    return table.unpack(out, 2, out.n)
end

return HeroContext
