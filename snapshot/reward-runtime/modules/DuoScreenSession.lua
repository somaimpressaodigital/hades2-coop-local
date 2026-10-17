-- Modal lifecycle only. All engine operations are explicit injected callbacks.
local Manager={};Manager.__index=Manager
local Session={};Session.__index=Session
local required={'acquire','release','openUI','closeUI','stopChoices','isApplying',
 'secureRewards','roomValid','connected','alive','choiceStatus'}
function Manager.New(host)
 for _,name in ipairs(required)do assert(type(host[name])=='function','Missing callback: '..name)end
 return setmetatable({Host=host,Sessions={},Serial=0},Manager)
end
local function call(self,name,...)
 local ok,result=pcall(self.Host[name],self.Scope,self.Owner,...)
 if not ok then self.Errors[#self.Errors+1]=name..': '..tostring(result)end
 return ok,result
end
function Manager:Open(args)
 assert(type(args.key)=='string' and args.key~='' and args.room,'Stable reward key and room identity required')
 local old=self.Sessions[args.key]
 if old then return old,false end
 if self.Active and self.Active.State~='closed'then return nil,false,'Another modal session is active or awaiting cleanup' end
 assert(args.heroes[1] and args.heroes[2] and args.heroes[1]~=args.heroes[2],'Distinct heroes required')
 assert(args.sources[1].LocalDuoOwner==1 and args.sources[2].LocalDuoOwner==2,'Wrong personal reward owners')
 assert(args.sources[1].LocalDuoBundle~=nil and args.sources[1].LocalDuoBundle==args.sources[2].LocalDuoBundle,'Wrong reward pair')
 self.Serial=self.Serial+1
 local s=setmetatable({Host=self.Host,Manager=self,Owner={},State='opening',Errors={},Leases={},
  OpeningBusy=true,Scope={Key=args.key,Room=args.room,Heroes={args.heroes[1],args.heroes[2]},
   Sources={args.sources[1],args.sources[2]}},AttemptedUI=false,Stopped=false,UIClosed=false},Session)
 -- Register BEFORE any callback that may yield or partially fail.
 self.Sessions[args.key]=s;self.Active=s
 local ok,result=pcall(function()
  assert(self.Host.roomValid(s.Scope,s.Owner),'Room changed before opening')
  for p=1,2 do assert(self.Host.connected(s.Scope,s.Owner,p) and self.Host.alive(s.Scope,s.Owner,p),'Player unavailable')end
  for _,resource in ipairs({'combat:J1','combat:J2','rewards','exits'})do
   s.Leases[#s.Leases+1]={Resource=resource}
   assert(self.Host.acquire(s.Scope,s.Owner,resource)==true,'Lock acquisition not acknowledged: '..resource)
   assert(s.State=='opening','Opening cancelled')
  end
  s.AttemptedUI=true
  assert(self.Host.openUI(s.Scope,s.Owner)==true,'UI opening not acknowledged')
  assert(s.State=='opening','Opening cancelled')
 end)
 s.OpeningBusy=false
 if ok then s.State='active' else s.Errors[#s.Errors+1]=tostring(result);s:Finish('open-error')end
 return s,true
end
function Session:Report()
 return {Key=self.Scope.Key,Reason=self.Reason,State=self.State,Errors=self.Errors,
  J1=self.LastStatus and self.LastStatus[1],J2=self.LastStatus and self.LastStatus[2]}
end
function Session:Finish(reason)
 if self.State=='closed'then return end
 self.Reason=self.Reason or reason or 'cancelled';self.State='stopping'
 self:RetryCleanup()
end
function Session:RetryCleanup()
 if self.State=='closed' or self.Cleaning or self.OpeningBusy or (self.State~='stopping' and self.State~='cleanup')then return end
 self.Cleaning=true
 local ok,errorText=pcall(function()
  if not self.Stopped then
   local success,result=call(self,'stopChoices',self.Reason)
   if success and result==true then self.Stopped=true else return end
  end
  -- Abort cannot undo an application already running in an engine coroutine.
  local checked,busy=call(self,'isApplying')
  if not checked or busy~=false then return end
  if not self.UIClosed then
   local success,result=true,true
   if self.AttemptedUI then success,result=call(self,'closeUI',self.Reason)end
   if success and result==true then self.UIClosed=true else return end
  end
  self.State='cleanup'
  -- Keep boundary locks until independent reward/door invariants are secured.
  -- Completion does not imply native loot consumption finished successfully.
  if not self.RewardsSecured then
   local success,result=call(self,'secureRewards',self:Report())
   if success and result==true then self.RewardsSecured=true end
  end
  for _,lease in ipairs(self.Leases)do
   local boundary=lease.Resource=='rewards' or lease.Resource=='exits'
   if not lease.Released and (not boundary or self.RewardsSecured)then
    -- Release exits last, only after the reward modal lease is removed.
    local othersReleased=true
    if lease.Resource=='exits'then
     for _,l in ipairs(self.Leases)do if l~=lease and not l.Released then othersReleased=false end end
    end
    if othersReleased then
     local success,result=call(self,'release',lease.Resource)
     if success and result==true then lease.Released=true end
    end
   end
  end
  for _,lease in ipairs(self.Leases)do if not lease.Released then return end end
  if not self.RewardsSecured then return end
  self.State='closed'
  if self.Manager.Active==self then self.Manager.Active=nil end
 end)
 if not ok then self.Errors[#self.Errors+1]=tostring(errorText)end
 self.Cleaning=false
end
function Session:Update()
 if self.State=='stopping' or self.State=='cleanup'then self:RetryCleanup();return end
 if self.State~='active'then return end
 local ok,errorText=pcall(function()
  if not self.Host.roomValid(self.Scope,self.Owner)then self:Finish('room-changed');return end
  for p=1,2 do
   if not self.Host.connected(self.Scope,self.Owner,p)then self:Finish('disconnected:J'..p);return end
   if not self.Host.alive(self.Scope,self.Owner,p)then self:Finish('dead:J'..p);return end
  end
  self.LastStatus={self.Host.choiceStatus(self.Scope,self.Owner,1),self.Host.choiceStatus(self.Scope,self.Owner,2)}
  for p=1,2 do
   local status=self.LastStatus[p]
   if status=='uncertain' or status=='rejected'then self:Finish('apply-error');return end
   if status=='cancelled' or status=='dead'then self:Finish(status);return end
   assert(status=='choosing' or status=='queued' or status=='applying' or status=='committed','Unknown choice state')
  end
  if self.LastStatus[1]=='committed' and self.LastStatus[2]=='committed'then self:Finish('complete')end
 end)
 if not ok then self.Errors[#self.Errors+1]=tostring(errorText);self:Finish('callback-error')end
end
function Session:PanelClosed(player)
 assert(player==1 or player==2,'Unknown panel')
 if self.State~='active'then return end
 local ok,status=call(self,'choiceStatus',player)
 if not ok or status~='committed'then self:Finish('partial-close:J'..player)end
 -- A committed player's panel may hide; it does not release any modal locks.
end
return Manager
