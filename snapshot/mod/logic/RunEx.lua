--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class RunEx
local RunEx = {}

---@return boolean
function RunEx.IsRunEnded()
    -- The game sets RunResult when the run ends
    -- So we can use this value to check if the run was finished
    return CurrentRun.RunResult and true
end

---@return boolean
function RunEx.WasTheFirstRunStarted()
    return not GameState or (not CurrentRun and IsEmpty(GameState.RunHistory))
end

---@return boolean
function RunEx.IsFirstRun(run)
    return not GameState or IsEmpty(GameState.RunHistory)
end

---@return boolean
function RunEx.IsShopRoomName(name)
    error("Not implementated")
    return false
end

---@return boolean
function RunEx.IsStoryRoomName(name)
    error("Not implementated")
    return false
end

function RunEx.IsDoorSpecial(door)
    error("Not implementated")
    return false
end

---@return boolean
function RunEx.IsFinalBossDoor(door)
    error("Not implementated")
    return door.ForceRoomName == "D_Boss01"
end

---@return boolean
function RunEx.IsDefaultDoorsLeadToRunProgress()
    error("Not implementated")
    return false
end

function RunEx.RemoveDoorReward(door)
    error("Not implementated")
    return false
end

function RunEx.IsHubRoom(name)
    return name == "Hub_Main" or name == "Hub_PreRun"
end

local META_STORY_ROOMS = {
    I_PostBoss01 = true,
    I_DeathAreaRestored = true,
    I_ChronosFlashback01 = true,
    EndCredits01 = true,
    Q_PostBoss01 = true
}

---@return boolean
function RunEx.IsMetaStoryRoom(name)
    return META_STORY_ROOMS[name] or false
end

function RunEx.GetCurrentRoom()
    return CurrentHubRoom or CurrentRun.CurrentRoom
end

function RunEx.RemoveRewardFromAllDefaultDoors()
    for _, door in pairs(MapState.OfferedExitDoors) do
        if door.IsDefaultDoor then
            RunEx.RemoveDoorReward(door)
        end
    end
end

function RunEx.RefreshEnemyAI()
    for _, enemy in pairs(ActiveEnemies) do
        if enemy.RequiredKill and not enemy.IsDead then
            enemy.TargetId = nil
            if enemy.AIStages then
                -- World contexts already follow the survivor. Wake the boss
                -- without resetting its phase or killing its staged coroutine.
                if enemy.AINotifyName then notifyExistingWaiters(enemy.AINotifyName) end
                if enemy.AIThreadName then SetThreadWait(enemy.AIThreadName,0.01) end
            else
                if enemy.AIThreadName then killTaggedThreads(enemy.AIThreadName) end
                if enemy.AINotifyName then killWaitUntilThreads(enemy.AINotifyName) end
                Stop({Id=enemy.ObjectId});StopAnimation({DestinationId=enemy.ObjectId})
                local behavior=enemy.AIBehavior
                enemy.AINotifyName=nil
                thread(function()
                    -- Cancellation is queued until the end of this frame.
                    -- Starting with the same tag immediately kills the new AI.
                    waitUnmodified(0.05,"LocalDuoAIRestart")
                    if ActiveEnemies[enemy.ObjectId]~=enemy or enemy.IsDead then return end
                    if behavior then SetAI(behavior,enemy,CurrentRun)
                    else enemy.AIBehavior=nil;SetupAI(enemy,{}) end
                end)
            end
        end
    end
end

return RunEx
