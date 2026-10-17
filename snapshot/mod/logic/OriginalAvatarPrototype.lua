-- Phase-one adapter, enabled only by the caller on a disposable test profile.
-- Keeps the old actor for rollback. Binding remains pending until real input
-- reports the new actor; a successful native call is not proof of ownership.
local Avatar={}
function Avatar.Replace(adapter,player,hero,definition)
    assert(adapter.IsTestProfile(),'Disposable test profile required')
    assert(player==1 or player==2)
    assert(not hero.IsDead and hero.ObjectId,'Living actor required')
    if hero.LocalDuoOriginalActor==hero.ObjectId then return hero.ObjectId end
    local old=hero.ObjectId;local new;local committed=false
    adapter.Protect(hero)
    local ok,errorText=pcall(function()
        new=assert(adapter.CreateFor(player,definition,old),'No new actor')
        assert(new~=old,'Actor must be constructed independently')
        adapter.BindFor(player,new)
        hero.LocalDuoOriginalActor=new
        adapter.Initialize(player,new,hero)
        adapter.Commit(player,hero,old,new);committed=true
        adapter.Park(old)
    end)
    if not ok then
        local rollback=pcall(function()
            adapter.BindFor(player,old)
            -- Initialization can mutate hero.ObjectId and animation swaps even
            -- before Commit. Restore metadata in every failed replacement.
            adapter.Rollback(player,hero,old,new)
            hero.ObjectId=old;hero.LocalDuoOriginalActor=nil
            adapter.Show(old)
        end)
        if rollback then
            if new then pcall(adapter.Destroy,new)end
            adapter.Release(hero)
        else adapter.FailProtected(player,old,new,errorText)end
        return nil,errorText
    end
    hero.LocalDuoOriginalActor=new
    hero.LocalDuoOriginalPrevious=old
    hero.LocalDuoOriginalBinding='awaiting real input'
    adapter.Release(hero)
    return new
end
function Avatar.ObserveInput(hero,id)
    if hero and hero.LocalDuoOriginalActor==id and hero.ObjectId==id then
        hero.LocalDuoOriginalBinding='new actor received input'
        return true
    end
    return false
end
return Avatar
