local Players = ModRequire "CoopPlayers.lua"
local Context = ModRequire "HeroContext.lua"
local Safety = { Frozen = {} }
local flag = "LocalDuoMenuProtection"

function Safety.ValidUnit(id)
    if not id then return false end
    local pos = GetLocation({Id=id})
    return pos and type(pos.X)=="number" and type(pos.Y)=="number"
end

function Safety.Update()
    if not CurrentRun or not CurrentRun.Hero then return end
    local active = LocalDuoPreparationPending or AreScreensActive()
    if active then
        for id, enemy in pairs(ActiveEnemies or {}) do
            if enemy.RequiredKill and not enemy.Charmed and not Safety.Frozen[id] and not enemy.IsDead then
                Safety.Frozen[id] = { Enemy=enemy, Thread=enemy.AIThreadName }
                Stop({Id=id})
                SetThingProperty({DestinationId=id,Property="ElapsedTimeMultiplier",Value=0,
                    ValueChangeType="Absolute",DataValue=false})
            end
        end
    else
        for id, entry in pairs(Safety.Frozen) do
            if ActiveEnemies and ActiveEnemies[id]==entry.Enemy and not entry.Enemy.IsDead then
                SetThingProperty({DestinationId=id,Property="ElapsedTimeMultiplier",
                    Value=(entry.Enemy.SpeedMultiplier or 1)*GetGameplayElapsedTimeMultiplier(id),
                    ValueChangeType="Absolute",DataValue=false})
                if entry.Thread then SetThreadWait(entry.Thread,0.05) end
            end
            Safety.Frozen[id]=nil
        end
    end
    for player=1,2 do
        local hero=Players.GetHero(player)
        if hero then
            hero.InvulnerableFlags=hero.InvulnerableFlags or {}
            if active and not hero.InvulnerableFlags[flag] and Safety.ValidUnit(hero.ObjectId) then
                Context.RunWithHeroContextAwait(hero,SetPlayerInvulnerable,flag)
            elseif not active and hero.InvulnerableFlags[flag] then
                if Safety.ValidUnit(hero.ObjectId) then Context.RunWithHeroContextAwait(hero,SetPlayerVulnerable,flag)
                else hero.InvulnerableFlags[flag]=nil end
            end
        end
    end
end
return Safety
