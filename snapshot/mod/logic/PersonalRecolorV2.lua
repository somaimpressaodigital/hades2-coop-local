-- Independent personal cosmetic pilot. DEFAULT OFF. Stock mechanics and forms.
-- Resource callback loads/observes only. Actual J2 binding reinspects before application.
local M={}
local PACKAGE='LocalDuoPersonalCrimsonV2'
local TEXTURE='GR2/TheNormalnijMods_Coop_PersonalCrimsonV2_Color512'
local binding
local function trace(event,detail)
    -- Existing project logger; no tick/poll, loader call or native query here.
    pcall(function()
        local diagnostics=ModRequire "LocalDuoDiagnostics.lua"
        diagnostics.Write("recolorV2:"..event,detail)
    end)
end
local function observation(stage,ok,value)
    if type(value)~='table'then trace(stage,"returned="..tostring(ok).." type="..type(value));return end
    trace(stage,"returned="..tostring(ok).." context="..tostring(value.ContextValid)
        .." valid="..tostring(value.HandleValid).." fallback="..tostring(value.Fallback)
        .." resource="..tostring(value.ResourcePresent).." size="..tostring(value.Width).."x"..tostring(value.Height))
end
function M.New(game,players,inspect,config)
    local enabled=false
    local attempted,armed,actorAttempt,applied
    local lastLoadReturned
    local status='disabled'
    local function world(room)
        local run,map,session=game.CurrentRun,game.MapState,game.SessionMapState
        if type(run)~='table'or type(room)~='table'or type(map)~='table'or type(session)~='table'then return end
        -- Caller supplies the actual room. Never prefer a possibly stale global hub.
        if room~=run.CurrentRoom then
            if room~=game.CurrentHubRoom or(room.Name~='Hub_Main'and room.Name~='Hub_PreRun')
                or type(game.HubRoomData)~='table'or not game.HubRoomData[room.Name]then return end
        end
        return {Run=run,Room=room,Map=map,Session=session,RoomName=room.Name}
    end
    local function same(a,b)
        return a and b and a.Run==b.Run and a.Room==b.Room and a.Map==b.Map
            and a.Session==b.Session and a.RoomName==b.RoomName
    end
    local function owner(hero)
        if game.LocalDuoCoopModeActive~=true or players.GetPlayersCount()~=2 then return false end
        local first=players.GetHero(1)
        return hero and hero==players.GetHero(2)and players.GetPlayerByHero(hero)==2
            and first and first~=hero and type(hero.ObjectId)=='number'and hero.ObjectId>0
            and first.ObjectId~=hero.ObjectId and not hero.IsDead
            and type(game.IsAlive)=='function'and game.IsAlive({Id=hero.ObjectId})==true
    end
    local function temporary(hero)
        local dark=game.SessionMapState and game.SessionMapState.DarkSide
        local map=game.MapState
        return hero.PolymorphType~=nil or hero.PolymorphModelOverride~=nil
            or(map and(map.HostilePolymorph or map.BabyPolymorph))
            or(type(dark)=='table'and next(dark)~=nil)
    end
    local function safe(scope,hero,actor)
        return same(scope,world(scope.Room))and owner(hero)and hero.ObjectId==actor and not temporary(hero)
    end
    local function outline(hero)
        game.AddOutline({Id=hero.ObjectId,R=180,G=70,B=240,Opacity=.6,Thickness=2,Threshold=.6})
    end
    local function fallback(hero)
        if not owner(hero)or temporary(hero)then return end
        outline(hero)
        local tint=config and config.LocalDuo and config.LocalDuo.Player2Tint
        if type(tint)~='table'then return end
        local color={}
        for i=1,4 do
            local v=tint[i]
            if type(v)~='number'or v~=v or v<0 or v>255 then return end
            color[i]=v
        end
        game.SetColor({Id=hero.ObjectId,Color=color})
    end
    local self={}
    function self:Apply(hero)
        -- Visibility/form callers cannot load, inspect or set a personal texture.
        if not owner(hero)then return false end
        if temporary(hero)then applied=nil;status='native-form-retained';return false end
        if applied and safe(applied.World,hero,applied.Actor)and applied.Hero==hero then
            outline(hero)
            game.SetColor({Id=hero.ObjectId,Color={255,255,255,255}})
        else fallback(hero)end
        return false
    end
    local function acceptable(ok,observed)
        return ok and type(observed)=='table'and observed.ContextValid==true
            and observed.HandleValid==true and observed.Fallback==false
            and observed.ResourcePresent==true and observed.Width==512 and observed.Height==512
            and observed.TextureName==TEXTURE
    end
    local function resourceScope(scope)
        return same(scope,world(scope.Room))and game.LocalDuoCoopModeActive==true and players.GetPlayersCount()==2
    end
    function self:RoomResourcesLoaded(room)
        local scope=world(room)
        if not enabled then status='disabled';return false end
        if not scope or scope.Room~=room or not resourceScope(scope)then
            status='wrong-resource-room';return false
        end
        if same(attempted,scope)then status='resource-already-attempted';return false end
        attempted=scope;armed=nil;actorAttempt=nil
        -- J2 may not exist yet. This entry never reads, tints or sets an actor.
        if type(inspect)~='function'or type(game.LoadPackages)~='function'then
            status='inspector-unavailable';return false
        end
        local returned=pcall(game.LoadPackages,{Name=PACKAGE})
        lastLoadReturned=returned
        if not resourceScope(scope)then status='scope-changed-after-load';return false end
        if not returned then status='native-load-error';return false end
        local ok,observed=pcall(inspect)
        observation("load-inspect",ok,observed)
        if not resourceScope(scope)then status='scope-changed-after-load-inspect';return false end
        if not acceptable(ok,observed)then status='native-load-observation-refused';return false end
        -- Record ONLY the real loader's scoped return, not a handle or Ready cache.
        -- The initial inspection table is discarded; the bind must reinspect.
        armed=scope;status='resource-observed-awaiting-actual-bind'
        return true
    end
    function self:CurrentActorBound(run,room)
        local scope=world(room)
        if not enabled then status='disabled';return false end
        if not scope or scope.Run~=run or scope.Room~=room or not same(armed,scope)
            or lastLoadReturned~=true then status='bind-without-current-resource-load';return false end
        local hero=players.GetHero(2)
        local actor=hero and hero.ObjectId
        if not safe(scope,hero,actor)then status='bind-owner-or-form-refused';return false end
        if actorAttempt and same(actorAttempt.World,scope)and actorAttempt.Hero==hero
            and actorAttempt.Actor==actor then status='actor-already-attempted';return false end
        actorAttempt={World=scope,Hero=hero,Actor=actor}
        -- The EXISTING post-InitCoopUnit binding path is the only authored caller.
        -- Never reload here; validate the actual current handle/resource afresh.
        local ok,observed=pcall(inspect)
        observation("bind-inspect",ok,observed)
        if not safe(scope,hero,actor)then status='scope-changed-after-bind-inspect';return false end
        if not acceptable(ok,observed)then fallback(hero);status='native-bind-observation-refused';return false end
        game.SetThingProperty({DestinationId=actor,Property='GrannyTexture',Value=TEXTURE})
        game.SetColor({Id=actor,Color={255,255,255,255}});outline(hero)
        applied={World=scope,Hero=hero,Actor=actor};status='personal-texture-requested'
        return true
    end
    function self:BeforeMapLoad()
        local record=applied
        applied=nil;attempted=nil;armed=nil;actorAttempt=nil;lastLoadReturned=nil
        if not record then return true end
        if not safe(record.World,record.Hero,record.Actor)then
            status='stale-or-native-form-not-restored';return false
        end
        game.SetThingProperty({DestinationId=record.Actor,Property='GrannyTexture',Value='null'})
        fallback(record.Hero);status='native-default-restored';return true
    end
    function self:SetEnabled(value)
        if value~=true then self:BeforeMapLoad()end
        enabled=value==true
    end
    function self:ReadStatus()
        return {Enabled=enabled,Status=status,Texture=TEXTURE,Package=PACKAGE,
            AppliedActor=applied and applied.Actor,NativeLoadReturned=lastLoadReturned,NativeVisualValidated=false}
    end
    return self
end
function M.Bind(game,players,config)
    if binding then return false end
    local inspector=rawget(game,'LocalDuoPersonalRecolorInspectV2')
    -- Capture one engine-created closure privately. No generic query global after binding.
    if type(inspector)=='function'then rawset(game,'LocalDuoPersonalRecolorInspectV2',nil)end
    binding=M.New(game,players,inspector,config)
    trace("bind","inspectorType="..type(inspector).." coop="..tostring(game.LocalDuoCoopModeActive))
    return true
end
function M.ApplyPersonal(hero)return binding and binding:Apply(hero)or false end
function M.AfterRoomResourcesLoaded(room)
    local ok,result=pcall(function()return binding and binding:RoomResourcesLoaded(room)or false end)
    local read=binding and binding:ReadStatus()or{}
    trace("resource","room="..tostring(type(room)=='table'and room.Name).." returned="..tostring(ok)
        .." result="..tostring(result).." enabled="..tostring(read.Enabled).." status="..tostring(read.Status)
        .." loadReturned="..tostring(read.NativeLoadReturned))
    return ok and result or false
end
function M.AfterCurrentActorBound(run,room)
    local ok,result=pcall(function()return binding and binding:CurrentActorBound(run,room)or false end)
    local read=binding and binding:ReadStatus()or{}
    trace("actor-bind","room="..tostring(type(room)=='table'and room.Name).." returned="..tostring(ok)
        .." result="..tostring(result).." status="..tostring(read.Status).." actor="..tostring(read.AppliedActor))
    return ok and result or false
end
function M.BeforeNativeMapLoad()return not binding or binding:BeforeMapLoad()end
function M.SetPersonalEnabled(value)
    if not binding then return false end
    binding:SetEnabled(value);trace("enabled",tostring(value==true));return true
end
function M.ReadStatus()return binding and binding:ReadStatus()or{Enabled=false,Status='not-bound',NativeVisualValidated=false}end
return M
