-- One campaign revive shared by the pair. Native personal DD data is untouched.
local Players=ModRequire 'CoopPlayers.lua'
local SharedHud=ModRequire 'LocalDuoSharedReviveHud.lua'
local Rescue={Limit=1}
local lastSaved=setmetatable({},{__mode='k'})
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function Rescue.IsArenaOwned()
 local arena=LocalDuoArenaRuntime
 if arena==nil then return false end
 if type(arena)~='table'or type(arena.IsDuelSceneOwned)~='function'then return true end
 local ok,value=pcall(arena.IsDuelSceneOwned,arena)
 return not ok or value~=false -- unknown Arena lifetime is never campaign permission
end
function Rescue.IsCampaign(run)
 if LocalDuoCoopModeActive~=true or Players.GetPlayersCount()~=2 or type(run)~='table'or run~=CurrentRun
  or CurrentHubRoom or type(run.CurrentRoom)~='table'or type(MapState)~='table'or type(SessionMapState)~='table'
  or Rescue.IsArenaOwned()then return false end
 local a,b=Players.GetHero(1),Players.GetHero(2)
 return type(a)=='table'and type(b)=='table'and a~=b and finite(a.ObjectId)and finite(b.ObjectId)
  and a.ObjectId>0 and b.ObjectId>0 and a.ObjectId~=b.ObjectId and(run.Hero==a or run.Hero==b)
end
function Rescue.Remaining(run)
 if type(run)~='table'then return 0 end
 local used=run.LocalDuoRescuesUsed
 if used==nil then used=0 end
 if not finite(used)or used<0 or used%1~=0 then return 0 end
 return used==0 and 1 or 0
end
function Rescue.ReadState(run)
 local known=Rescue.IsCampaign(run)
 local used=type(run)=='table'and run.LocalDuoRescuesUsed or nil
 if used~=nil and(not finite(used)or used<0 or used%1~=0)then known=false end
 local ending=known and(run.LocalDuoEnding==true or SessionMapState.HandlingDeath==true)or false
 local remaining=known and Rescue.Remaining(run)or 0
 return {Run=run,Known=known,Remaining=remaining,Available=known and remaining==1 and not ending,
  Spent=known and remaining==0 or false,Ending=ending}
end
function Rescue.Transfer(run,victim,partner,args)
 if not Rescue.IsCampaign(run)or run.LocalDuoEnding or SessionMapState.HandlingDeath
  or not Players.IsPlayerHero(victim)or not finite(victim.Health)then return false end
 local saved=lastSaved[run]
 -- A repeated stage of the SAME successful event must not become a second death.
 -- A new actual fatal (HP<=0) is never ignored just because the engine reuses args.
 if args~=nil and saved and saved.Victim==victim and saved.Id==victim.ObjectId and saved.Args==args
  and saved.Room==run.CurrentRoom and saved.Map==MapState and saved.Session==SessionMapState
  and victim.Health>0 and victim.IsDead~=true then return true,0,true end
 if victim.Health>0 or Rescue.Remaining(run)==0 or not finite(victim.MaxHealth)or victim.MaxHealth<1 then return false end
 local amount=math.max(1,math.floor(victim.MaxHealth*0.5))
 -- Commit the shared pool and actual revive before any UI/presentation can yield.
 run.LocalDuoRescuesUsed=1
 victim.Health=math.min(victim.MaxHealth,amount);victim.IsDead=nil
 lastSaved[run]={Victim=victim,Id=victim.ObjectId,Args=args,Room=run.CurrentRoom,Map=MapState,Session=SessionMapState}
 Rescue.UpdateHud()
 return true,victim.Health,false -- partner HP is not a cost, including partner HP1/0
end
function Rescue.ClearTemporary(run,iterator,state,key)
    if not run then return end
    if run.InvulnerableFlags then run.InvulnerableFlags.LocalDuoRescue=nil end
    for _,hero in iterator,state,key do
        if hero.InvulnerableFlags then
            hero.InvulnerableFlags.LocalDuoRescue=nil
            if hero.ObjectId and not hero.IsDead and IsEmpty(hero.InvulnerableFlags) then
                SetVulnerable({Id=hero.ObjectId})
            end
        end
    end
end
function Rescue.UpdateHud()
 -- No text labels. UI errors cannot change the already committed death policy.
 local ok,why=pcall(SharedHud.Update,Rescue.ReadState(CurrentRun))
 Rescue.HudError=not ok and tostring(why)or nil
end
return Rescue
