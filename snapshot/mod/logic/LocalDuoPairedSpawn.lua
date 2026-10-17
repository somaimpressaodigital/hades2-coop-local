-- One entry alignment after presentation/move/binding, never a combat-follow teleporter.
local M={}
function M.Start(d)
 local g,p,c,e=d.Game,d.Players,d.Context,d.Events;local pending;local movementScopes={};local introPresentation;local deathPresentation
 local function room()return d.RunEx.GetCurrentRoom()end
 local function queue(r,reason)
  if LocalDuoCoopModeActive~=true or not r then return end
  if pending and pending.Run==g.CurrentRun and pending.Room==r and pending.Map==g.MapState then return end
  pending={Run=g.CurrentRun,Room=r,Map=g.MapState,Reason=reason}
 end
 local function current(r)
  return LocalDuoCoopModeActive==true and g.CurrentRun==r.Run and room()==r.Room and g.MapState==r.Map
 end
 local function ready(r)
  if not current(r) or g.PlayingTextLines
   or (introPresentation and current(introPresentation))
   or (deathPresentation and current(deathPresentation))then return false end
  for scope in pairs(movementScopes)do
   if not current(scope)then movementScopes[scope]=nil
   elseif scope.ActorId==(p.GetHero(1) or {}).ObjectId then return false end
  end
  if g.AreScreensActive() then
   for name in pairs(g.ActiveScreens or {})do if name~='LocalDuoPreparation'then return false end end
  end
  local a,b=p.GetHero(1),p.GetHero(2)
  if not a or not b or a.IsDead or b.IsDead or not a.ObjectId or not b.ObjectId or a.ObjectId==b.ObjectId then return false end
  if type(a.Health)~='number' or not(a.Health>0 and a.Health<math.huge)
   or type(b.Health)~='number' or not(b.Health>0 and b.Health<math.huge)then return false end
  if a.InvulnerableFlags and a.InvulnerableFlags.MoveHeroToRoomPosition then return false end
  if g.SessionMapState and g.SessionMapState.OriginalBindingAttempted then
   for player,hero in ipairs({a,b})do
    if d.Character.Name(player)=='Zagreus' and hero.LocalDuoOriginalActor~=hero.ObjectId then return false end
   end
  end
  if type(g.LocalDuoNativeBindingProbe)~='function'then return false end
  local probe=g.LocalDuoNativeBindingProbe(a.ObjectId,b.ObjectId)
  return probe and probe.Validated==true and probe.Player1NativeId==a.ObjectId and probe.Player2NativeId==b.ObjectId,a,b
 end
 local function place(r,a,b,ids)
  local ok,x,y=ready(r);if not ok or x~=a or y~=b or a.ObjectId~=ids[1] or b.ObjectId~=ids[2]then return end
  local location=g.GetLocation({Id=ids[1]})
  local now=g._worldTimeUnmodified
  if not location or type(location.X)~='number' or type(location.Y)~='number'
   or not(location.X>-math.huge and location.X<math.huge and location.Y>-math.huge and location.Y<math.huge)
   or type(now)~='number' or not(now>-math.huge and now<math.huge)
   or not r.Stable or r.Stable.Actor1~=ids[1] or r.Stable.Actor2~=ids[2]
   or now<r.Stable.Since or now-r.Stable.Since<0.5 then r.Stable=nil;return end
  if g.IsLocationBlocked({Id=ids[1],CheckUnits=false})~=false then r.Stable=nil;return end
  local selected={0,0} -- share the validated final anchor; peer occupancy is intentional
  ok,x,y=ready(r);if not ok or x~=a or y~=b or a.ObjectId~=ids[1]or b.ObjectId~=ids[2]then return end
  r.Attempted=true -- before native position change; no automatic retry after partial setter failure
  g.Teleport({Id=ids[2],DestinationId=ids[1],OffsetX=selected[1],OffsetY=selected[2]})
  local after=g.GetLocation({Id=ids[2]})
  if not current(r) or a.ObjectId~=ids[1] or b.ObjectId~=ids[2] or not after
   or type(after.X)~='number' or type(after.Y)~='number'
   or not((after.X-location.X)^2+(after.Y-location.Y)^2<=1^2)
   or g.IsLocationBlocked({Id=ids[2],CheckUnits=false})~=false then r.Error='Entry placement readback blocked/unknown';return end
  r.Done=true;r.ActorIds=ids;r.Anchor=location;r.Offset=selected
  -- A completed entry may precede this map's one visual actor swap.
  for player,hero in ipairs({a,b})do
   if d.Character.Name(player)=='Zagreus' and hero.LocalDuoOriginalActor~=ids[player] then
    r.ExpectedActorRebind={Player=player,PreviousId=ids[player]}
   end
  end
 end
 local service={NativeProof=false}
 function service.Request(r,reason)queue(r,reason)end
 function service.Poll()
  local r=pending;if not r or r.Error or r.Attempted or r.Scheduled then return end
  if not current(r)then pending=nil;return end
  local checked,ok,a,b=pcall(ready,r);if not checked then r.Error=ok;return end
  if not ok then r.Stable=nil;return end
  local now=g._worldTimeUnmodified
  if type(now)~='number' or not(now>-math.huge and now<math.huge)then r.Stable=nil;return end
  if not r.FirstReadyAt then r.FirstReadyAt=now end
  if now<r.FirstReadyAt or now-r.FirstReadyAt>30 then r.Error='Entry stability window expired';return end
  local location=g.GetLocation({Id=a.ObjectId})
  if not location or type(location.X)~='number' or type(location.Y)~='number'
   or not(location.X>-math.huge and location.X<math.huge and location.Y>-math.huge and location.Y<math.huge)
   or g.IsLocationBlocked({Id=a.ObjectId,CheckUnits=false})~=false then r.Stable=nil;return end
  local stable=r.Stable
  if not stable or stable.Actor1~=a.ObjectId or stable.Actor2~=b.ObjectId
   or now<stable.Since then
   r.Stable={Actor1=a.ObjectId,Actor2=b.ObjectId,Since=now};return
  end
  if now-stable.Since<0.5 then return end
  r.Scheduled=true;local ids={a.ObjectId,b.ObjectId}
  local scheduled,scheduleError=pcall(c.ScheduleServiceThread,function()
   local good,err=pcall(place,r,a,b,ids);r.Scheduled=false;if not good then r.Error=err end
  end)
  if not scheduled then r.Scheduled=false;r.Error=scheduleError end
 end
 function service.Read()return pending end
 e.run:on('roomPresentationFinished',function(run,r)if run==g.CurrentRun then queue(r,'room presentation finished')end end)
 -- Renew only a completed entry that actually placed the pre-swap actor, or the existing hub receipt.
 e.run:on('playerActorRebound',function(player,oldId,newId,scope)
  local r=pending
  if not r or not r.Done or r.Error or not current(r) then return end
  local expected=r.ExpectedActorRebind
  local entry=r.Reason=='room presentation finished' or r.Reason=='saved cleared-room restore finished'
  if not d.RunEx.IsHubRoom(r.Room.Name) and not (entry and expected and expected.Player==player and expected.PreviousId==oldId) then return end
  if not scope or scope.Run~=r.Run or scope.Room~=r.Room or scope.Map~=r.Map
   or (player~=1 and player~=2) or not r.ActorIds or r.ActorIds[player]~=oldId or newId==oldId then return end
  local hero,peer=p.GetHero(player),p.GetHero(3-player)
  if not hero or hero.ObjectId~=newId or not peer or peer.ObjectId~=r.ActorIds[3-player] then return end
  pending=nil;queue(r.Room,r.Reason)
  pending.ActorRebound={Player=player,PreviousId=oldId,CurrentId=newId}
 end)
 e.engine:on('tick',service.Poll)
 d.HookUtils.wrap('MoveHeroToRoomPosition',function(base,args)
  local owner=args.MoverId or (g.CurrentRun.Hero and g.CurrentRun.Hero.ObjectId)
  local main=p.GetHero(1);local tracks=main and owner==main.ObjectId
  local scope
  if tracks then scope={Run=g.CurrentRun,Room=room(),Map=g.MapState,ActorId=owner};movementScopes[scope]=true end
  local out=table.pack(pcall(base,args));if scope then
   movementScopes[scope]=nil
   if pending and current(scope) and current(pending)then pending.Stable=nil end
  end
  if not out[1]then error(out[2],0)end
  return table.unpack(out,2,out.n)
 end)
 -- Cover the entire intro, including entrance functions that launch an asynchronous move.
 d.HookUtils.wrap('StartRoomPresentation',function(base,run,r,...)
  local previous=introPresentation;local scope
  if LocalDuoCoopModeActive==true and run==g.CurrentRun and room()==r then
   scope={Run=run,Room=r,Map=g.MapState};introPresentation=scope
  end
  local out=table.pack(pcall(base,run,r,...))
  if scope and introPresentation==scope then introPresentation=previous end
  if scope and pending and current(scope) and current(pending)then pending.Stable=nil end
  if not out[1]then error(out[2],0)end
  return table.unpack(out,2,out.n)
 end)
 -- Stock OnAnyLoad cleared-room resume calls RestoreUnlockRoomExits instead of
 -- StartRoomPresentation unless StartRoomPresentationOnReload is set.
 d.HookUtils.wrap('RestoreUnlockRoomExits',function(base,run,r)
  local out=table.pack(pcall(base,run,r));if not out[1]then error(out[2],0)end
  if run==g.CurrentRun and room()==r and r.RestoreUnlockRoomExits==true then queue(r,'saved cleared-room restore finished')end
  return table.unpack(out,2,out.n)
 end)
 -- DeathAreaRoomTransition returns BEFORE the stock respawn presentation.
 -- Bind the barrier to real world refs so a killed old-map coroutine cannot block a new map.
 d.HookUtils.wrap('StartDeathLoopPresentation',function(base,run,...)
  local r=room();local map=g.MapState
  local tracks=LocalDuoCoopModeActive==true and run==g.CurrentRun and r and d.RunEx.IsHubRoom(r.Name)
  local previous=deathPresentation;local scope
  if tracks then scope={Run=run,Room=r,Map=map};deathPresentation=scope end
  local out=table.pack(pcall(base,run,...))
  if scope and deathPresentation==scope then deathPresentation=previous end
  if not out[1]then error(out[2],0)end
  if scope and current(scope)then
   -- Renew only a completed early placement. Never retry a failed/partial setter.
   if pending and pending.Run==run and pending.Room==r and pending.Map==map
    and pending.Done and not pending.Error then pending=nil end
   queue(r,'death return presentation finished')
  end
  return table.unpack(out,2,out.n)
 end)
 d.HookUtils.wrap('DeathAreaRoomTransition',function(base,source,args)
  local out=table.pack(pcall(base,source,args));if not out[1]then error(out[2],0)end
  if room()==source then queue(source,'hub transition finished')end
  return table.unpack(out,2,out.n)
 end)
 return service
end
return M
