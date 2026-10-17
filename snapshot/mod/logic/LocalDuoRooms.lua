local Players = ModRequire "CoopPlayers.lua"
local Rooms = {}

function Rooms.GetChooser()
    local claim=CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.LocalDuoExitClaim
    return claim and claim.Player
end

function Rooms.CanChoose(player)
    local hero=Players.GetHero(player)
    return hero and not hero.IsDead and (hero.Health==nil or hero.Health>0)
        and not (CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.LocalDuoExitClaim)
end

function Rooms.TryClaim(player,doorId)
    if not Rooms.CanChoose(player) then return false end
    CurrentRun.CurrentRoom.LocalDuoExitClaim={Player=player,DoorId=doorId}
    return true
end

function Rooms.ResetRuntime(room)
    -- ActiveEncounters contains coroutine registrations from this Lua session.
    -- Serialized copies cannot be active after loading/restarting a map.
    room.ActiveEncounters={}
    room.LocalDuoExitClaim=nil;room.LocalDuoChoiceCommitted=nil
end

function Rooms.CommitChoice(run)
    local room = run.CurrentRoom
    if CurrentHubRoom or not room or room.LocalDuoChoiceCommitted then return end
    room.LocalDuoChoiceCommitted = true
    run.LocalDuoNextChooser = nil
end

function Rooms.ShowTurn()
    -- Retained callback: technical campaign labels are disabled in every mode.
end

return Rooms
