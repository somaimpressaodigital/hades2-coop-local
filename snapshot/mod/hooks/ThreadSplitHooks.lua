--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"

---@class ThreadSplitHooks : SimpleHook
local ThreadSplitHooks = SimpleHook.New()

-- Read-only installation records. No extra dispatch wrapper or change to tag policy.
local baseApplyHooks = SimpleHook.ApplyHooks
local expectedHandlers, installedDispatchers = {}, {}
local timeoutRecord, timeoutMetatable, timeoutIndex, timeoutNewIndex
local originalPlayerGetter = CoopPlayers.GetCurrentPlayerId

function ThreadSplitHooks:ApplyHooks()
    assert(self == ThreadSplitHooks, "ThreadSplitHooks actual instance required")
    local pending = {}
    for name, handler in pairs(expectedHandlers) do
        if self.wrap[name] == handler and type(_G[name]) == "function" then
            pending[name] = { Base = _G[name], Handler = handler }
        end
    end
    baseApplyHooks(self) -- SAME existing SimpleHook install pass, once.
    for name, record in pairs(pending) do
        if self.wrap[name] == nil and type(_G[name]) == "function" and _G[name] ~= record.Base then
            record.Installed = _G[name]
            installedDispatchers[name] = record
        else
            installedDispatchers[name] = nil
        end
    end
end

function ThreadSplitHooks.ReadInstalledDispatchers()
    local rows, all = {}, true
    for name, handler in pairs(expectedHandlers) do
        local record = installedDispatchers[name]
        local current = record ~= nil and record.Handler == handler and _G[name] == record.Installed
        rows[name] = { Base = record and record.Base, Handler = handler,
            Installed = record and record.Installed, Current = current }
        if not current then all = false end
    end
    local mt = timeoutRecord and getmetatable(timeoutRecord)
    local timeoutCurrent = timeoutRecord ~= nil and _eventTimeoutRecord == timeoutRecord
        and mt == timeoutMetatable and mt.__index == timeoutIndex and mt.__newindex == timeoutNewIndex
    local playerCurrent = CoopPlayers.GetCurrentPlayerId == originalPlayerGetter
    return { Dispatchers = rows, TimeoutRecord = timeoutRecord, TimeoutMetatable = timeoutMetatable,
        TimeoutIndex = timeoutIndex, TimeoutNewIndex = timeoutNewIndex,
        TimeoutCurrent = timeoutCurrent, PlayerGetter = originalPlayerGetter,
        PlayerGetterCurrent = playerCurrent, AllCurrent = all and timeoutCurrent and playerCurrent,
        CoverageType = "LuaThreadTagDispatchersOnly", NativeOwnershipVerified = false }
end

function ThreadSplitHooks.VerifyArenaOwnership()
    local observed = ThreadSplitHooks.ReadInstalledDispatchers()
    if not observed.AllCurrent then return false, "Actual thread-tag dispatcher/metatable identity changed", observed.CoverageType end
    if LocalDuoCoopModeActive ~= true or type(CoopGetPlayersCount) ~= "function" then
        return false, "Existing coop dispatch guard is inactive", observed.CoverageType
    end
    local ok, count = pcall(CoopGetPlayersCount)
    if not ok or type(count) ~= "number" or count < 2 then
        return false, "Existing coop native player-count guard refused", observed.CoverageType
    end
    return true, nil, observed.CoverageType -- wrapper/tag closure only; caller must verify explicit hero context.
end

local THREAD_TO_SPLIT = {
    -- Mana regen
    ManaRegenStartup = true;
    ManaRegenInterval = true;
    IdleManaRegen = true;
    -- TODO check
    WeaponCastArmIndicatorFire = true;

    WeaponStaffSwing5IndicatorFire = true,
    WeaponStaffBallIndicatorFire = true,

    WeaponDagger5IndicatorFire = true,
    WeaponDaggerThrowIndicatorFire = true,

    WeaponTorchIndicatorFire = true;
    WeaponTorchSpecialIndicatorFire = true;

    WeaponAxeSpinIndicatorFire = true,
    WeaponAxeSpecialSwingIndicatorFire = true,

    WeaponLobIndicatorFire = true;
    WeaponLobSpecialIndicatorFire = true;

    WeaponSuitChargedIndicatorFire = true,
    WeaponSuitRangedIndicatorFire = true,

    -- weapon charge
    ChargeManaWeaponStart = true;
    ManaChargeComplete = true;
}

---@param name string
local function GetThreadRename(name)
    if name and THREAD_TO_SPLIT[name] then
        name = name .. "CoopPlayers" .. (CoopPlayers.GetCurrentPlayerId() or 1)
    end

    return name
end

function ThreadSplitHooks:InitGameHooks()
    local mt = {
        __index = function(self, key)
            return rawget(self, GetThreadRename(key))
        end;
        __newindex = function(self, key, value)
            rawset(self, GetThreadRename(key), value)
        end;
    }
    setmetatable(_eventTimeoutRecord, mt)
    timeoutRecord, timeoutMetatable = _eventTimeoutRecord, mt
    timeoutIndex, timeoutNewIndex = mt.__index, mt.__newindex
end

function ThreadSplitHooks.wrap.HasThread(HasThread, name)
    return HasThread(GetThreadRename(name))
end

function ThreadSplitHooks.wrap.waitUnmodified(waitUnmodified, duration, tag, persist)
    return waitUnmodified(duration, GetThreadRename(tag), persist)
end

function ThreadSplitHooks.wrap.SetThreadWait(SetThreadWait, tag, duration)
    return SetThreadWait(GetThreadRename(tag), duration)
end

function ThreadSplitHooks.wrap.killTaggedThreads(killTaggedThreads, tag)
    return killTaggedThreads(GetThreadRename(tag))
end

function ThreadSplitHooks.wrap.wait(wait, duration, tag, persist)
    return wait(duration, GetThreadRename(tag), persist)
end

function ThreadSplitHooks.wrap.HasWaitUntil(HasWaitUntil, tag)
    return HasWaitUntil(GetThreadRename(tag))
end

function ThreadSplitHooks.wrap.waitUntil(waitUntil, event, tag, persist)
    return waitUntil(GetThreadRename(event), tag, persist)
end

function ThreadSplitHooks.wrap.notifyExistingWaiters(notifyExistingWaiters, event, wasTimeout)
    return notifyExistingWaiters(GetThreadRename(event), wasTimeout)
end

function ThreadSplitHooks.wrap.NotifyOnWeaponCharge(NotifyOnWeaponCharge, args)
    args.Notify = GetThreadRename(args.Notify)
    NotifyOnWeaponCharge(args)
end

-- Pin only this module's original handlers before callers can apply or mutate hook tables.
for name, handler in pairs(ThreadSplitHooks.wrap) do expectedHandlers[name] = handler end

return ThreadSplitHooks
