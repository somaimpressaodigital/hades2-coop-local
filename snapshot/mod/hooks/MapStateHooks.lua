--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type HeroContextProxySpliterStore
local HeroContextProxySpliterStore = ModRequire "../logic/HeroContextProxySpliterStore.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"

---@class MapStateHooks  : SimpleHook
local MapStateHooks = SimpleHook.New()
local arenaSession,readOwnedWorld,installedInitializers
local proxyPins={}
local function recordProxy(name,target,handler)
    local mt=getmetatable(target);local keys={}
    for i,key in ipairs(handler.keys)do keys[i]=key end
    proxyPins[name]={Target=target,Handler=handler,Metatable=mt,Index=mt and mt.__index,NewIndex=mt and mt.__newindex,
        Data=handler.data,First=handler.data[1],Second=handler.data[2],Keys=keys}
end
local arenaSessionFields={
    -- Base cast/charge/sprint STATE only. Projectile/obstacle registries whose
    -- keys identify world objects (OriginMarkers, ExProjectileIds etc) stay world.
    'ChargeStageManaSpend','PendingStageManaRefund','MaxChargeStageReached',
    'ReadiedMassiveAttacks','CastAttachedProjectiles','CastDefense','CastLock',
    'ArmCast','SuperchargeCast','LastCastProjectileId','LastCastProjectileVolley',
    'CastAttachTriggered','AttachedCastObstacleId','QueuedClearCast','InsideCastSpeedPropertyChanges',
    'SprintActive','SprintStartTime','SprintStartEventsFired','SprintSoundId','SprintWeaponSoundId',
    'EndAutoSprintThread','WaitUntilAutoSprintInput','LockSprintActive','BlockStagedCharge',
    'NextPerfectChargeTimeStart','NextPerfectChargeTimeEnd','LastExMove',
    'ManaIndicatorCustomColor','ManaIndicatorCustomHSV','FreshInputOOMStateEnabled',
    'TrackManaRegen','CumulativeManaRegen',
}
local function arena()
    return arenaSession and arenaSession.HasOwnedWorld==readOwnedWorld
        and readOwnedWorld()==true and CurrentHubRoom==nil
end
function MapStateHooks.ConfigureArenaSession(session)
    assert(type(session)=='table'and type(session.HasOwnedWorld)=='function','Actual Arena session required')
    assert(arenaSession==nil or arenaSession==session,'Arena session provider changed')
    arenaSession=session;readOwnedWorld=session.HasOwnedWorld
end
function MapStateHooks:InitGameHooks()
    installedInitializers={Map=MapStateInit,Session=SessionMapStateInit}
end

---@public
function MapStateHooks:InitEngineHooks()
    if MapState then
        MapStateHooks.ApplyMapStateProxy()
    end
    if SessionMapState then
        MapStateHooks.ApplySessionMapStateProxy()
    end
end

---@private
function MapStateHooks.ApplyMapStateProxy()
    local hadnler = HeroContextProxySpliterStore.GetOrCreate("MapState", MapState, {
        "LastBlinkTimeUnmodified",
        "PlayerAlphaFlags",
        "HeroNotStopsProjectile",
        "EquippedWeapons",
        "WeaponCharge",
        "ManaChargeIndicatorIds",
        "CastArmDisable",
        "ChargedManaWeapons",
        "ShowManaChargeIndicator",
        "ManaChargeIndicatorCost",
        "ManaChargeIndicatorData",
        "ManaChargeIndicatorIds",
        "FamiliarUnit",
    })

    for playerId = 1, CoopPlayers.GetPlayersCount() do
        local playerData = hadnler:GetPlayerData(playerId)
        playerData.EquippedWeapons = playerData.EquippedWeapons or {}
        playerData.HeroNotStopsProjectile = playerData.HeroNotStopsProjectile or {}
        playerData.ChargedManaWeapons = playerData.ChargedManaWeapons or {}
        playerData.ManaChargeIndicatorIds = playerData.ManaChargeIndicatorIds or {}
    end
    recordProxy('MapState',MapState,hadnler)
end

---@private
function MapStateHooks.ApplySessionMapStateProxy()
    local keys={
        "MagnetismMultiplier",
        "OlympianBoonCountBoost",
        "OlympianBoonCountBoostPropertyChanges",
    }
    if arena()then for _,key in ipairs(arenaSessionFields)do keys[#keys+1]=key end end
    local handler=HeroContextProxySpliterStore.GetOrCreate("SessionMapState", SessionMapState, keys)
    recordProxy('SessionMapState',SessionMapState,handler)
end

function MapStateHooks.post.MapStateInit()
    HeroContextProxySpliterStore.Delete("MapState")
    MapStateHooks.ApplyMapStateProxy()
end

function MapStateHooks.post.SessionMapStateInit()
    HeroContextProxySpliterStore.Delete("SessionMapState")
    MapStateHooks.ApplySessionMapStateProxy()
end

-- Read existing REAL splitter instances; not a native weapon-kit certificate.
function MapStateHooks.ReadArenaResourceState(scope)
    if not arena()or not installedInitializers or MapStateInit~=installedInitializers.Map
        or SessionMapStateInit~=installedInitializers.Session then return nil,'Actual Arena map initializer wrappers changed or missing'end
    if not scope or MapState~=scope.Map or SessionMapState~=scope.Session or CoopPlayers.GetPlayersCount()~=2 then return nil,'Actual current two-player map required'end
    local map=HeroContextProxySpliterStore.Get('MapState')
    local session=HeroContextProxySpliterStore.Get('SessionMapState')
    for _,row in ipairs({{map,MapState},{session,SessionMapState}})do
        local handler,target=row[1],row[2];local mt=getmetatable(target)
        local pin=proxyPins[target==MapState and'MapState'or'SessionMapState']
        if not handler or handler.target~=target or not mt or mt.handler~=handler
            or type(handler.data)~='table'or type(handler.data[1])~='table'or type(handler.data[2])~='table'
            or handler.data[1]==handler.data[2]or not pin or pin.Target~=target or pin.Handler~=handler
            or pin.Metatable~=mt or pin.Index~=mt.__index or pin.NewIndex~=mt.__newindex or pin.Data~=handler.data
            or pin.First~=handler.data[1]or pin.Second~=handler.data[2]or #pin.Keys~=#handler.keys then return nil,'Actual private map splitter not current'end
        for i,key in ipairs(pin.Keys)do if handler.keys[i]~=key then return nil,'Personal splitter key policy changed'end end
    end
    for i=1,2 do if CoopPlayers.GetHero(i)~=scope.Actors[i]or scope.ActorIds[i]~=scope.Actors[i].ObjectId then return nil,'Current actor binding changed'end end
    local requiredMap={'EquippedWeapons','WeaponCharge','ChargedManaWeapons','ManaChargeIndicatorIds','CastArmDisable',
        'ShowManaChargeIndicator','ManaChargeIndicatorCost','ManaChargeIndicatorData'}
    for _,row in ipairs({{map,requiredMap},{session,arenaSessionFields}})do
        local handler,fields=row[1],row[2];local known={}
        for _,key in ipairs(handler.keys)do known[key]=true end
        for _,key in ipairs(fields)do
            if not known[key]or rawget(handler.target,key)~=nil then return nil,'Personal field is not actually projected: '..key end
            local a,b=handler.data[1][key],handler.data[2][key]
            if type(a)=='table'and a==b then return nil,'Aliased personal table: '..key end
        end
    end
    local sessionFields={};for i,key in ipairs(arenaSessionFields)do sessionFields[i]=key end
    return {Map=map,Session=session,MapFields=requiredMap,SessionFields=sessionFields,
        LuaPersonalFieldsOnly=true,NativeWeaponKitCoverage=false,NativeGameplayValidated=false}
end

return MapStateHooks
