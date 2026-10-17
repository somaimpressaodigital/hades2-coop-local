-- Personal accounting for actual H2 reroll budgets, acquisitions and spending.
-- No Run metatable/projection and no default-player inference.
local R={}
local Players,Context
local creating=setmetatable({},{__mode="k"})
local nativeMain=setmetatable({},{__mode="k"})
local function number(value)
    assert(type(value)=="number"and value==value and value~=math.huge and value~=-math.huge,"Invalid native reroll amount")
    return value
end
local function active(run)
    return LocalDuoCoopModeActive==true and Players~=nil and run==CurrentRun
end
local function owner(run,hero)
    assert(run==CurrentRun and type(hero)=="table","Reroll actor/run unavailable")
    local p=Players.GetPlayerByHero(hero)
    if p==1 or p==2 then
        assert(Players.GetHero(p)==hero,"Reroll actor binding changed")
        assert(not creating[hero]or creating[hero].Player==p,"Native creation owner conflicts with binding")
        return p
    end
    local pending=creating[hero]
    if pending and pending.Run==run and CurrentRun.Hero==hero then return pending.Player end
    if nativeMain[run]==hero and CurrentRun.Hero==hero then return 1 end
    error("Reroll owner is unknown; no default-player fallback",0)
end
local function validate(record)
    number(record.Budget);number(record.Acquired);number(record.Spent)
    assert(record.Budget>=0 and record.Spent>=0,"Invalid persisted reroll record")
    return record
end
local function amount(record)
    return math.max(0,record.Budget+record.Acquired-record.Spent)
end
local function bank(run)
    local data=rawget(run,"LocalDuoPersonalRerolls")
    if data then assert(data.Version==1 and type(data.Owners)=="table","Unsupported persisted reroll data");return data end
    -- Legacy migration preserves the EXACT existing shared balance for P1.
    -- There is no evidence of P2 spending/grants in an old save: do not mint it.
    local previous=rawget(run,"NumRerolls")
    assert(previous~=nil,"Native reroll initialization has not occurred")
    previous=number(previous);assert(previous>=0,"Invalid legacy reroll balance")
    data={Version=1,Owners={[1]={Budget=0,Acquired=previous,Spent=0,Legacy=true}}}
    rawset(run,"LocalDuoPersonalRerolls",data)
    return data
end
local function mirror(run,p,record)
    if p==1 then rawset(run,"NumRerolls",amount(record))end
end
function R.Configure(players,context)
    assert(Players==nil or Players==players,"Reroll players provider changed")
    Players=assert(players);Context=assert(context)
    LocalDuoPersonalRerolls=R -- published only during explicit coop initialization
end
function R.Read(run,hero)
    if not active(run)then return run.NumRerolls end
    local p=owner(run,hero)
    local record=bank(run).Owners[p]
    if not record then return 0 end -- legacy P2 is unavailable until a real reset/init
    validate(record);mirror(run,p,record)
    return amount(record)
end
function R.CanAct(run,hero)
    if not active(run)then return true end
    -- ControlHooks has an unknown-trigger fallback invoking the callback without
    -- actor context. Never treat that default hero as the payer/recipient.
    if not Context.IsHeroContextExplicit()or CurrentRun.Hero~=hero or creating[hero]then return false end
    local ok,p=pcall(owner,run,hero)
    return ok and Players.GetHero(p)==hero
end
function R.Spend(run,hero,cost)
    number(cost)
    if not active(run)then
        if cost<0 or(run.NumRerolls or 0)<cost then return false end
        run.NumRerolls=run.NumRerolls-cost;return true
    end
    if not R.CanAct(run,hero)then return false end
    local p=owner(run,hero)
    local record=bank(run).Owners[p]
    if not record or cost<0 then return false end
    validate(record)
    if amount(record)<cost then return false end
    record.Spent=record.Spent+cost
    mirror(run,p,record)
    return true
end
function R.Grant(run,hero,value)
    number(value)
    if not active(run)then run.NumRerolls=run.NumRerolls+value;return true end
    local pending=creating[hero]
    if not pending and not R.CanAct(run,hero)then return false,"Explicit reroll recipient is unavailable"end
    local p=owner(run,hero)
    if pending and not pending.Committing then pending.Grant=(pending.Grant or 0)+value;return true end
    local record=bank(run).Owners[p]
    -- Actual H2 AddRerolls is itself evidence of this owner's acquisition.
    if not record then record={Budget=0,Acquired=0,Spent=0,Legacy=true};bank(run).Owners[p]=record end
    validate(record);record.Acquired=record.Acquired+value;mirror(run,p,record)
    return true
end
function R.SetNativeBudget(run,hero,value)
    value=number(value);assert(value>=0,"Negative native reroll budget")
    if not active(run)then run.NumRerolls=value;return end
    local p=owner(run,hero);local data=bank(run);local record=data.Owners[p]
    local pending=creating[hero]
    if pending and not pending.Committing then pending.Budget=value;return true end
    if not record then
        if data.NativeBoundary~=true then return false,"Legacy P2 requires a fresh native run/hub reset"end
        record={Budget=value,Acquired=0,Spent=0};data.Owners[p]=record
    elseif not record.Legacy then
        -- Keep expenditure debt: unequip/re-equip and level changes cannot refill.
        validate(record);record.Budget=value
    end
    mirror(run,p,record)
    return true
end
function R.BeginNativeRun(run,hero,value)
    value=number(value);assert(value>=0 and run==CurrentRun and hero==CurrentRun.Hero,"Native run initialization mismatch")
    if not active(run)then run.NumRerolls=value;return end
    -- Called only at the ORIGINAL StartNewRun initialization statement.
    nativeMain[run]=hero
    rawset(run,"LocalDuoPersonalRerolls",{Version=1,NativeBoundary=true,
        Owners={[1]={Budget=value,Acquired=0,Spent=0}}})
    rawset(run,"NumRerolls",value)
end
function R.BeginNativeHub(run,hero,value)
    value=number(value);assert(value>=0,"Negative native hub budget")
    if not active(run)then run.NumRerolls=value;return end
    assert(run==CurrentRun and hero==CurrentRun.Hero and Players.GetHero(1)==hero,"Native death/hub reset requires the actual main hero")
    -- ORIGINAL KillHero reset boundary, before native transition to the hub.
    -- Gather actual second-hero stock trait total BEFORE committing either reset.
    local second=Players.GetHero(2)
    local secondValue
    if second then Context.RunWithHeroContextAwait(second,function()
        assert(Players.GetHero(2)==second and run==CurrentRun,"Hub reset actor/run changed")
        secondValue=number(GetTotalHeroTraitValue("RerollCount"))
    end)end
    assert(run==CurrentRun and Players.GetHero(1)==hero and Players.GetHero(2)==second,"Hub reset bindings changed")
    local owners={[1]={Budget=value,Acquired=0,Spent=0}}
    if secondValue then assert(secondValue>=0);owners[2]={Budget=secondValue,Acquired=0,Spent=0}end
    rawset(run,"LocalDuoPersonalRerolls",{Version=1,NativeBoundary=true,Owners=owners})
    rawset(run,"NumRerolls",value)
end
function R.WithCreating(player,hero,fn,...)
    assert(player==1 or player==2,"Missing explicit creation player")
    assert(CurrentRun.Hero==hero and not creating[hero],"Native creation actor/context mismatch")
    assert(Context.IsHeroContextExplicit(),"Native creation requires the real actor context")
    local run=CurrentRun
    local pending={Player=player,Run=run}
    creating[hero]=pending
    local result=table.pack(pcall(fn,...))
    if not result[1]then creating[hero]=nil;error(result[2],0)end
    if CurrentRun~=run or CurrentRun.Hero~=hero then creating[hero]=nil;error("Native creation context changed",0)end
    pending.Committing=true
    local committed,failure=pcall(function()
        if pending.Budget~=nil then R.SetNativeBudget(run,hero,pending.Budget)end
        if pending.Grant~=nil then R.Grant(run,hero,pending.Grant)end
    end)
    creating[hero]=nil
    if not committed then error(failure,0)end
    return table.unpack(result,2,result.n)
end
function R.ReadMainHUD(run)
    if not active(run)then return run.NumRerolls end
    local hero=Players.GetHero(1)
    -- Only the actual StartNewRun statement can publish this pre-binding actor.
    -- CurrentRun.Hero alone is not evidence that an unknown actor belongs to J1.
    if not hero then
        local initialized=nativeMain[run]
        if initialized and CurrentRun.Hero==initialized then hero=initialized end
    end
    assert(hero,"Main HUD owner is unavailable")
    return R.Read(run,hero)
end
function R.ReuseCounts(run,hero)
    if not active(run)then return run.CurrentRoom.SpentRerolls end
    local p=owner(run,hero)
    local room=assert(run.CurrentRoom,"Reroll room is unavailable")
    room.LocalDuoRerollReuse=room.LocalDuoRerollReuse or {[1]=room.SpentRerolls or {},[2]={}}
    local values=assert(room.LocalDuoRerollReuse[p],"Reroll reuse owner is unavailable")
    -- Preserve the existing raw field as P1's real native cost history.
    if p==1 then room.SpentRerolls=values end
    return values
end
return R
