-- Profile3 operational guard for legacy Host. No force getter/setter/epoch certificate.
local M={}
function M.Wrap(service,d)
 local api,ctx=assert(d.Game),assert(d.Context);local host=assert(service.Host)
 local native=assert(d.NativeContext,'Existing native context required for joint freeze experiment')
 assert(type(native.RunWithNativeHeroContext)=='function')
 for _,name in ipairs({'FreezePlayerUnit','UnfreezePlayerUnit','ToggleControl'})do assert(type(api[name])=='function','Missing stock API: '..name)end
 local probe=assert(api.LocalDuoNativeBindingProbe,'Existing native binding probe required')
 local scopes={};local canOpen=service.CanOpen;local acquire,release=host.acquire,host.release
 local function capture(args)
  local s=d.state()
  return {Run=s.Run,Room=args.room,Map=s.MapState,Session=s.SessionMapState,Screens=s.ActiveScreens,Order=s.ActiveScreenOrder,
   Heroes={args.heroes[1],args.heroes[2]},Ids={args.heroes[1].ObjectId,args.heroes[2].ObjectId}}
 end
 local function valid(s)
  assert(d.isTestProfile()==true and not api.CurrentHubRoom,'Operational pilot requires Profile3 test room')
  assert(type(api.RequiredKillEnemies)=='table' and not next(api.RequiredKillEnemies),'Room no longer cleared')
  local now=d.state()
  assert(now.Run==s.Run and now.Run.CurrentRoom==s.Room and now.MapState==s.Map and now.SessionMapState==s.Session
   and now.ActiveScreens==s.Screens and now.ActiveScreenOrder==s.Order,'Run/room/registry changed')
  for p=1,2 do assert(d.getHero(p)==s.Heroes[p] and s.Heroes[p].ObjectId==s.Ids[p] and not s.Heroes[p].IsDead,'Hero/actor changed')end
  assert(api.LocalDuoNativeBindingProbe==probe,'Binding reader changed')
  local r=probe(s.Ids[1],s.Ids[2])
  assert(r and r.Validated==true and r.Player1NativeId==s.Ids[1] and r.Player2NativeId==s.Ids[2],'Current native binding not validated')
 end
 -- Stock FreezePlayerUnit list with DisableCodex/DisableInventory, no DisableTray.
 local freezeNames={'Use','Move','Rush','Shout','Assist','Attack1','Attack2','Attack3','AutoLock','Gift','Emote','Reload','Codex','Inventory'}
 local function reconcile(s,journal)
  for p=1,2 do
   valid(s)
   local blocks=assert(s.Session.PlayerControlBlocks,'Current stock block table required')
   local enabled,disabled={},{}
   for _,name in ipairs(freezeNames)do
    local flags=blocks[name];assert(flags==nil or type(flags)=='table','Invalid stock control flags')
    local list=flags and next(flags)and disabled or enabled;list[#list+1]=name
   end
   local call={Player=p,Enabled=enabled,Disabled=disabled,Attempted=true};journal[#journal+1]=call
   -- Validation before/after, not inside the temporarily swapped native root.
   native.RunWithNativeHeroContext(p,function()
    if #disabled>0 then call.DisableAttempted=true;api.ToggleControl({Names=disabled,Enabled=false});call.DisableReturned=true end
    if #enabled>0 then call.EnableAttempted=true;api.ToggleControl({Names=enabled,Enabled=true});call.EnableReturned=true end
   end)
   call.Returned=true;valid(s);call.BindingValidated=true
  end
 end
 function service:CanOpen(args)
  local ok,s=pcall(capture,args);if not ok then return false,'Invalid operational scope'end
  local checked,why=pcall(valid,s);if not checked then return false,tostring(why)end
  local allowed,reason=canOpen(self,args);if not allowed then return allowed,reason end
  checked,why=pcall(valid,s);if not checked then return false,tostring(why)end
  scopes[args.key]=s;return true
 end
 local function record(scope)
  local r=assert(service.Records[scope.Key]);local s=assert(scopes[scope.Key],'No operational preflight')
  valid(s);for p=1,2 do assert(scope.Heroes[p]==s.Heroes[p],'Scope hero alias changed')end
  return r,s
 end
 host.acquire=function(scope,owner,resource)
  local r,s=record(scope);local p=tonumber(resource:match('^combat:J([12])$'))
  if not p then
   if resource=='exits'then assert(not r.State.ActiveScreens[r.Flag] and not r.State.MapState.BlockTimerFlags[r.Flag] and not r.State.Run.BlockTimerFlags[r.Flag],'Foreign exit/timer key occupied')end
   if resource=='rewards'then for _,source in ipairs(scope.Sources)do assert(not(source.InteractBlocks and source.InteractBlocks[r.Flag]),'Foreign reward key occupied')end end
   local out=acquire(scope,owner,resource);valid(s);return out
  end
  r.OperationalLeases=r.OperationalLeases or {};assert(not r.OperationalLeases[p],'Do not retry an operational acquire')
  local hero,flag=s.Heroes[p],r.Flag..':J'..p
  hero.InvulnerableFlags=hero.InvulnerableFlags or {};assert(hero.InvulnerableFlags[flag]==nil,'Foreign invulnerability key occupied')
  local controlBlocks,moveBlocks=s.Session.PlayerControlBlocks,s.Session.PlayerMoveBlocks
  assert(type(controlBlocks)=='table'and type(moveBlocks)=='table','Stock freeze flag storage required')
  for _,name in ipairs(freezeNames)do
   local flags=controlBlocks[name];assert(flags==nil or type(flags)=='table','Invalid stock control flags')
   assert(not flags or flags[flag]==nil,'Foreign stock control flag occupied')
  end
  assert(moveBlocks[flag]==nil,'Foreign stock move flag occupied')
  local lease={Owner=owner,Flags=hero.InvulnerableFlags,Flag=flag,ControlBlocks=controlBlocks,MoveBlocks=moveBlocks};r.OperationalLeases[p]=lease
  r.Owner=owner;r.Acquired=r.Acquired or {};r.Acquired[resource]=true
  ctx.RunWithHeroContextAwait(hero,function()
   valid(s);assert(ctx.GetCurrentHeroContext()==hero,'Wrong protection context')
   local baseline=api.IsInvulnerable({Id=s.Ids[p]});assert(type(baseline)=='boolean','Invulnerability baseline unknown')
   valid(s);lease.Opaque=baseline and not next(lease.Flags)
   lease.InputStarted=true;lease.FreezeCall={Attempted=true}
   api.FreezePlayerUnit(flag,{DisableCodex=true,DisableInventory=true});lease.FreezeCall.Returned=true;valid(s)
   lease.AcquireReconcile={};reconcile(s,lease.AcquireReconcile)
   api.Stop({Id=s.Ids[p]});valid(s)
   lease.Flags[flag]=true;lease.FlagsOwned=true;lease.InvulnerableStarted=true;api.SetInvulnerable({Id=s.Ids[p]});valid(s)
  end)
  valid(s);lease.Acquired=true;return true
 end
 host.release=function(scope,owner,resource)
  local r,s=record(scope);assert(r.Owner==owner,'Wrong operational owner')
  local p=tonumber(resource:match('^combat:J([12])$'))
  if not p then
   if resource=='exits'then assert(r.State.ActiveScreens[r.Flag]==r.Screen,'Foreign screen replaced own exit lease')end
   local out=release(scope,owner,resource);valid(s);return out
  end
  local lease=assert(r.OperationalLeases and r.OperationalLeases[p],'Missing own protection lease')
  local hero=s.Heroes[p];assert(lease.Owner==owner and hero.InvulnerableFlags==lease.Flags,'Foreign flag storage replaced')
  assert(s.Session.PlayerControlBlocks==lease.ControlBlocks and s.Session.PlayerMoveBlocks==lease.MoveBlocks,'Foreign stock freeze storage replaced')
  assert(not lease.ReleaseUncertain,'Partial release requires review, no automatic native retry')
  ctx.RunWithHeroContextAwait(hero,function()
   valid(s);assert(ctx.GetCurrentHeroContext()==hero,'Wrong cleanup context')
   assert(s.Session.PlayerControlBlocks==lease.ControlBlocks and s.Session.PlayerMoveBlocks==lease.MoveBlocks,'Foreign stock freeze storage replaced')
   if lease.InputStarted and not lease.InputReleased then
    lease.ReleaseUncertain=true;lease.UnfreezeCall={Attempted=true}
    api.UnfreezePlayerUnit(lease.Flag);lease.UnfreezeCall.Returned=true;valid(s)
    lease.ReleaseReconcile={};reconcile(s,lease.ReleaseReconcile)
    lease.InputReleased=true;lease.ReleaseUncertain=false;valid(s)
   end
   if lease.FlagsOwned then
    assert(lease.Flags[lease.Flag]==true,'Own invulnerability flag changed')
    lease.Flags[lease.Flag]=nil;lease.FlagsOwned=false
   end
   if lease.InvulnerableStarted and lease.Opaque==false and not next(lease.Flags) and not lease.VulnerableRestored then
    lease.ReleaseUncertain=true;api.SetVulnerable({Id=s.Ids[p]});lease.VulnerableRestored=true;lease.ReleaseUncertain=false;valid(s)
   end
  end)
  valid(s);lease.Released=true;return true
 end
 service.OperationalProtection={Profile3Only=true,NativeMemoryEpochUnknown=true,ForceProtectionUsed=false,ProductionAuthority=false}
 return service
end
return M
