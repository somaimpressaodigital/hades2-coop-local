local Players=ModRequire "CoopPlayers.lua"
local Context=ModRequire "HeroContext.lua"
local Control=ModRequire "CoopControl.lua"
local Monitor=ModRequire "CoopInvariantMonitor.lua"
local Diagnostics={LastState=nil}
local monitorState=Monitor.New()
local path=GetScriptDir().."/../LocalDuoDiagnostics.log"

function Diagnostics.Write(event,message)
    local file=io and io.open and io.open(path,"a")
    if not file then return end
    local stamp=os and os.date and os.date("%Y-%m-%d %H:%M:%S") or tostring(_worldTimeUnmodified)
    file:write(stamp.." ["..event.."] "..tostring(message).."\n");file:close()
end
local function keys(t)
    local list={}
    for k in pairs(t or {}) do list[#list+1]=tostring(k) end
    table.sort(list);return table.concat(list,",")
end
function Diagnostics.Snapshot(event,extra)
    if not CurrentRun then return end
    local room=CurrentHubRoom or CurrentRun.CurrentRoom or {}
    local details={"room="..tostring(room.Name),"default="..tostring(Players.GetPlayerByHero(Context.GetDefaultHero())),
        "context="..tostring(Players.GetCurrentPlayerId()),"pending="..tostring(LocalDuoPreparationPending),
        "screens="..keys(ActiveScreens),"extra="..tostring(extra)}
    for p=1,2 do
        local hero=Players.GetHero(p)
        if hero then
            details[#details+1]=string.format("J%d{id=%s,hp=%s/%s,dead=%s,untargetable=%s,invulnerable=%s}",
                p,tostring(hero.ObjectId),tostring(hero.Health),tostring(hero.MaxHealth),tostring(hero.IsDead),
                keys(hero.UntargetableFlags),keys(hero.InvulnerableFlags))
            details[#details+1]="J"..p.." character="..tostring(hero.LocalDuoCharacter)
                .." weapons="..keys(hero.Weapons).." traits="..keys(hero.TraitDictionary)
        end
    end
    local required={}
    for id,obj in pairs(MapState and MapState.RoomRequiredObjects or {}) do
        required[#required+1]=tostring(id)..":"..tostring(obj.Name)..":owner="..tostring(obj.LocalDuoOwner)
    end
    table.sort(required);details[#details+1]="required="..table.concat(required,",")
    local encounters={}
    for _,enc in ipairs(room.ActiveEncounters or {}) do
        encounters[#encounters+1]=tostring(enc.Name)..":completed="..tostring(enc.Completed)
            ..":main="..tostring(enc==room.Encounter)..":identity="..tostring(enc)
    end
    details[#details+1]="encounters="..table.concat(encounters,",")
    local enemies={}
    for id,enemy in pairs(ActiveEnemies or {}) do
        if not enemy.IsDead then
            enemies[#enemies+1]=tostring(id)..":"..tostring(enemy.Name)..":hp="..tostring(enemy.Health)
                ..":target="..tostring(enemy.LocalDuoTargetId or enemy.TargetId)
                ..":AI="..tostring(enemy.AIBehavior)..":disabled="..tostring(enemy.AIDisabled)
        end
    end
    table.sort(enemies);details[#details+1]="enemies="..table.concat(enemies,",")
    Diagnostics.Write(event,table.concat(details," | "))
end
function Diagnostics.Update()
    if not CurrentRun then return end
    local a,b=Players.GetHero(1),Players.GetHero(2)
    if not a or not b then return end
    if Diagnostics.BindingProbeRun~=CurrentRun then
        Diagnostics.BindingProbeRun=CurrentRun
        Diagnostics.BindingProbeAttempts=0
        Diagnostics.BindingProbeNext=0
        Diagnostics.BindingProbeComplete=false
    end
    local probeTime=_worldTimeUnmodified or _worldTime or 0
    if type(LocalDuoNativeBindingProbe)=="function" and not Diagnostics.BindingProbeComplete
        and Diagnostics.BindingProbeAttempts<6 and probeTime>=Diagnostics.BindingProbeNext then
        Diagnostics.BindingProbeAttempts=Diagnostics.BindingProbeAttempts+1
        Diagnostics.BindingProbeNext=probeTime+2
        local ok,result=pcall(LocalDuoNativeBindingProbe,a.ObjectId,b.ObjectId)
        Diagnostics.BindingProbeComplete=ok and type(result)=="table" and result.Validated==true
        Diagnostics.Write("nativeBindingProbe",ok and ("validated="..tostring(result.Validated)
            .." J1="..tostring(result.Player1Matches).." J2="..tostring(result.Player2Matches)
            .." J1index="..tostring(result.Player1IndexMatches).." J2index="..tostring(result.Player2IndexMatches)
            .." J1active="..tostring(result.Player1ActiveMatches).." J2active="..tostring(result.Player2ActiveMatches)
            .." J1found="..tostring(result.Player1Found).." J2found="..tostring(result.Player2Found)
            .." J1nativeId="..tostring(result.Player1NativeId).." J2nativeId="..tostring(result.Player2NativeId)
            .." J1type="..tostring(result.Player1NativeType).." J2type="..tostring(result.Player2NativeType)
            .." J1owner="..tostring(result.Player1OwnerMatches).." J2owner="..tostring(result.Player2OwnerMatches)
            .." status="..tostring(result.Status))or tostring(result))
    end
    if Diagnostics.MonitoredRun~=CurrentRun then
        Diagnostics.MonitoredRun=CurrentRun;monitorState=Monitor.New()
    end
    local previousCount=#monitorState.Findings
    local room=CurrentHubRoom or CurrentRun.CurrentRoom or {}
    -- Restrict HP checks to preparation; ordinary damage is expected in combat.
    local sample={Room=room,Protected=LocalDuoPreparationPending==true,
        Menu=next(ActiveScreens or {})~=nil,RescuesUsed=CurrentRun.LocalDuoRescuesUsed,Players={}}
    for p,hero in ipairs({a,b})do
        local schema=Control.Schemas.Current[p] or {}
        sample.Players[p]={Id=hero.ObjectId,Health=hero.Health,Character=hero.LocalDuoCharacter,
            Controller=schema.Device=="Gamepad" and schema.ControllerId or nil}
    end
    Monitor.Observe(monitorState,sample)
    for i=previousCount+1,#monitorState.Findings do
        local finding=monitorState.Findings[i]
        Diagnostics.Snapshot("invariantFailure",finding.Code..": "..finding.Message)
    end
    local state=tostring(a.IsDead)..":"..tostring(b.IsDead)..":"..keys(ActiveScreens)
        ..":"..tostring(LocalDuoPreparationPending)
    if state~=Diagnostics.LastState then
        Diagnostics.LastState=state;Diagnostics.Snapshot("state")
    end
end
return Diagnostics
