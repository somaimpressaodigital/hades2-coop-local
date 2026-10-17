-- Integration candidate ONLY. No globals, engine calls, hooks, or implicit installation.
-- Call with resolved/preprocessed PERSONAL trait data. Lua 5.2.
local M = {}
local attack = {'LocalDuoH1_SwordWeapon','LocalDuoH1_SwordWeapon2',
    'LocalDuoH1_SwordWeapon3','LocalDuoH1_SwordWeaponDash'}
local special = {'LocalDuoH1_SwordParry'}
local function copy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}; if seen[v] then return seen[v] end
    local out = {}; seen[v] = out
    for k,x in pairs(v) do out[copy(k,seen)] = copy(x,seen) end
    -- Deliberately no metatables/global context proxies on a personal snapshot.
    return out
end
local function equal(a,b,seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    seen=seen or {}; if seen[a] == b then return true end; seen[a]=b
    for k,v in pairs(a) do if not equal(v,b[k],seen) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function ownerOK(owner) assert(owner==1 or owner==2,'Explicit owner 1 or 2 required') end
local function actorOK(actor) assert(type(actor)=='number' and actor>0 and actor%1==0,'Valid actor ID required') end
local function array(t)
    assert(type(t)=='table','Expected selector array')
    local count=0
    for k,v in pairs(t) do
        assert(type(k)=='number' and k>=1 and k%1==0 and type(v)=='string','Not a weapon selector array')
        count=count+1
    end
    assert(count==#t,'Sparse selector array')
end
local function lookup(t) local out={} for _,v in ipairs(t) do out[v]=true end return out end
local allSword=lookup(attack); allSword[special[1]]=true
local function expand(t, family, includeFamily)
    array(t); local out,seen={},{}
    local allowed=lookup(family)
    for _,name in ipairs(t) do
        assert(not allSword[name] or allowed[name],'Attack and special families must remain separate')
        if not seen[name] then out[#out+1]=name;seen[name]=true end
    end
    if includeFamily then for _,name in ipairs(family) do
        if not seen[name] then out[#out+1]=name;seen[name]=true end
    end end
    return out
end
-- This allowlist permits adaptation of copies, NOT a claim of engine validation.
local policy={
    AphroditeWeaponBoon={bindings={{path={'AddOutgoingDamageModifiers','ValidWeapons'},family='attack'}}},
    AphroditeSpecialBoon={bindings={{path={'AddOutgoingDamageModifiers','ValidWeapons'},family='special'}}},
    HighHealthCritBoon={bindings={}},
    CritBonusBoon={bindings={}},
}
function M.Policy() return copy(policy) end
function M.Families() return {attack=copy(attack),special=copy(special)} end

-- Low-level helper for reviewed test/integration data. Does not authorize a boon.
-- Only named selector paths are changed. No scalar WeaponName/ProjectileName remap.
function M.ExpandCopy(source, owner, bindings)
    ownerOK(owner);assert(type(source)=='table','Trait copy required')
    local out=copy(source)
    for _,binding in ipairs(bindings or {}) do
        assert(binding.family=='attack' or binding.family=='special','Unknown family')
        assert(type(binding.path)=='table' and #binding.path>=2,'Explicit selector path required')
        local node=out
        for i=1,#binding.path-1 do
            node=node[binding.path[i]];assert(type(node)=='table','Unresolved trait or missing binding path')
        end
        local field=binding.path[#binding.path]
        assert(field=='ValidWeapons' or field=='WeaponNames','Only weapon selector lists may be expanded')
        assert(not out.ExcludeLinked and not node.ExcludeLinked,'Explicit ExcludeLinked needs separate review')
        local family=binding.family=='attack' and attack or special
        node[field]=expand(node[field],family,true)
        -- Rebuild processed caches from the updated LIST, never union a stale lookup.
        node[field..'Lookup']=lookup(node[field])
    end
    return out
end
function M.Prepare(source, owner)
    assert(type(source)=='table' and type(source.Name)=='string','Resolved trait Name required')
    local rule=policy[source.Name]
    assert(rule,'Deferred or unknown boon: '..source.Name)
    -- Fail closed if another mod/version adds active gameplay callbacks to an
    -- allowed name. This is a guard, not a complete semantic dependency audit.
    for key,value in pairs(source) do
        if type(key)=='string' and value~=nil then
            assert(not key:match('^On') and key~='SetupFunction' and key~='SetupFunctions',
                'Allowed definition changed; callback requires new review: '..key)
        end
    end
    return M.ExpandCopy(source,owner,rule.bindings)
end

-- A store holds only adapter snapshots, never hero/global tables. The backend must
-- implement an ATOMIC, synchronous owner-only reconciliation (or reject it).
-- No native backend is shipped: resolving engine rollback/contexts is integration work.
function M.NewStore(backend)
    assert(type(backend)=='table' and type(backend.commit)=='function','Transactional backend required')
    local states,busy={},false
    local store={}
    local function reconcile(owner,desired,reason)
        ownerOK(owner);assert(not busy,'Reentrant/overlapping reconciliation forbidden')
        local partner=states[owner==1 and 2 or 1]
        assert(not desired or not partner or desired.actorId~=partner.actorId,'Actor already belongs to partner in ledger')
        local previous=states[owner]
        if equal(previous,desired) then return false end
        if previous and desired then
            assert(desired.actorId==previous.actorId or reason=='rebind','Use Rebind for actor change')
        end
        local transaction={owner=owner,reason=reason,before=copy(previous),after=copy(desired),remove={},apply={}}
        local changedActor=previous and desired and previous.actorId~=desired.actorId
        for key,trait in pairs(previous and previous.entries or {}) do
            if changedActor or not desired or not equal(trait,desired.entries[key]) then
                transaction.remove[#transaction.remove+1]={key=key,actorId=previous.actorId,trait=copy(trait)}
            end
        end
        for key,trait in pairs(desired and desired.entries or {}) do
            if changedActor or not previous or not equal(trait,previous.entries[key]) then
                transaction.apply[#transaction.apply+1]={key=key,actorId=desired.actorId,trait=copy(trait)}
            end
        end
        table.sort(transaction.remove,function(a,b)return a.key<b.key end)
        table.sort(transaction.apply,function(a,b)return a.key<b.key end)
        busy=true
        local ok,result=pcall(backend.commit,transaction)
        busy=false
        if not ok then error(result,0) end
        assert(result==true,'Backend did not confirm atomic commit; ledger retained')
        states[owner]=copy(desired)
        return true
    end
    function store:Set(owner,actor,key,source)
        ownerOK(owner);actorOK(actor);assert(type(key)=='string' and key~='','Stable slot/trait key required')
        local adapted=M.Prepare(source,owner)
        local previous=states[owner]
        assert(not previous or previous.actorId==actor,'Actor changed: Rebind first')
        local nextState=copy(previous) or {actorId=actor,entries={}}
        nextState.entries[key]=adapted
        return reconcile(owner,nextState,'set')
    end
    -- Level/pom/rarity updates pass the fully recalculated source into Set.
    -- Never multiply an already-applied native property again.
    function store:Remove(owner,key)
        ownerOK(owner);assert(type(key)=='string','Stable key required')
        if not states[owner] or not states[owner].entries[key] then return false end
        local nextState=copy(states[owner]);nextState.entries[key]=nil
        return reconcile(owner,nextState,'remove')
    end
    function store:Rebind(owner,newActor)
        ownerOK(owner);actorOK(newActor)
        assert(states[owner],'No registered build to rebind')
        local nextState=copy(states[owner]);nextState.actorId=newActor
        return reconcile(owner,nextState,'rebind')
    end
    function store:Snapshot(owner) ownerOK(owner);return copy(states[owner]) end
    return store
end
return M
