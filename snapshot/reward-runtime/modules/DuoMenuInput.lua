-- Normalized Hades-only input. No OS polling, desktop injection or key logging.
local Input={};Input.__index=Input
local keys={'Up','Down','Left','Right','Confirm','Cancel','PageNext','PagePrevious','CategoryNext','DetailNext','DetailPrevious'}
local function blank(reason)
 local s={Connected=false,Focused=false,Reason=reason,Events={}}
 for _,key in ipairs(keys)do s[key]=false end;return s
end
local function neutral(state)for _,key in ipairs(keys)do if state[key]then return false end end;return true end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
function Input.New(deps)
 for _,name in ipairs({'schemas','gameHasFocus','gamepadDevices','gamepadRead'})do assert(type(deps[name])=='function','Missing callback: '..name)end
 local self=setmetatable({Deps=deps,Bindings={},Cache={},Epoch={0,0},Handles={}},Input)
 for p=1,2 do self.Handles[p]={Player=p,Owner=self}end
 return self
end
function Input:Begin(menuKey)
 self.MenuKey=menuKey;self.MouseState=nil;for p=1,2 do self:Rebind(p)end
end
function Input:Rebind(player)
 assert(player==1 or player==2,'Unknown player')
 self.Epoch[player]=self.Epoch[player]+1;self.Bindings[player]=nil;self.Cache[player]=blank('binding requires fresh release')
end
function Input:Devices()return {self.Handles[1],self.Handles[2]}end
function Input:ReadDevice(handle)
 assert(handle and handle.Owner==self and self.Handles[handle.Player]==handle,'Unknown device handle')
 return self:ReadPlayer(handle.Player)
end
function Input:ReadPlayer(player)
 assert(player==1 or player==2,'Unknown player')
 local state=copy(self.Cache[player]or blank('Poll required'))
 state.Events=copy(state.Events)
 if state.Pointer then state.Pointer=copy(state.Pointer)end
 return state
end
function Input:Sample(player,schema,devices,focused)
 if not schema then return blank('missing current schema')end
 if schema.Device=='Keyboard'then
  -- ControllerId 3/4/5/-1 may park the keyboard role; NEVER treat it as a pad.
  if not focused then return blank('Hades focus required for keyboard')end
  if type(self.Deps.keyboardRead)~='function'then return blank('real Hades keyboard snapshot API not provided')end
  return self.Deps.keyboardRead(player,{MenuKey=self.MenuKey,Focused=true,Device='Keyboard'})or blank('keyboard unavailable')
 elseif schema.Device=='Gamepad'then
  local found
  for _,device in ipairs(devices)do if device.Index==schema.ControllerId then found=device;break end end
  if not found or found.Instance==nil then return blank('configured pad not present in real device catalog')end
  local raw=self.Deps.gamepadRead(found.Index)or blank('pad unavailable')
  if raw.Instance~=found.Instance or raw.Index~=found.Index then return blank('pad changed during sample')end
  raw=copy(raw);raw.Focused=raw.Focused==true and focused
  return raw
 end
 return blank('unsupported schema device')
end
function Input:Normalize(player,schema,raw,now)
 local s=blank(raw.Reason);local focused=raw.Focused==true
 s.Connected=raw.Connected==true and raw.Instance~=nil;s.Focused=focused
 s.NativeInstance=raw.Instance;s.Device=schema and schema.Device;s.ControllerId=schema and schema.ControllerId
 local revision=self.Deps.schemaRevision and self.Deps.schemaRevision(player)or 0
 local identity=tostring(s.Device)..':'..tostring(s.ControllerId)..':'..tostring(revision)..':'..self.Epoch[player]
 local binding=self.Bindings[player]
 if not binding or binding.Identity~=identity or binding.NativeInstance~=raw.Instance then
  binding={Identity=identity,NativeInstance=raw.Instance,Previous={},Armed=false,
   InstanceToken={Device=s.Device,NativeInstance=raw.Instance,Binding=identity}}
  self.Bindings[player]=binding
 end
 s.Instance=binding.InstanceToken -- Stable opaque identity derived from REAL device.
 if not s.Connected or not focused then binding.Armed=false;binding.Previous={};return s end
 for _,key in ipairs(keys)do s[key]=raw[key]==true end
 s.CategoryNext=s.CategoryNext or raw.Character==true
 local threshold=self.Deps.axisThreshold or 18000
 if s.Device=='Gamepad'then
  s.Left=s.Left or(raw.X or 0)<-threshold;s.Right=s.Right or(raw.X or 0)>threshold
  s.Up=s.Up or(raw.Y or 0)<-threshold;s.Down=s.Down or(raw.Y or 0)>threshold
 end
 if s.Up and s.Down then s.Up=false;s.Down=false end
 if s.Left and s.Right then s.Left=false;s.Right=false end
 if not binding.Armed then
  if neutral(s)then binding.Armed=true end
  for _,key in ipairs(keys)do s[key]=false end;binding.Previous={};return s
 end
 for _,key in ipairs(keys)do s.Events[key]=s[key]and not binding.Previous[key]or false end
 local direction=s.Down and 'Down'or s.Up and 'Up'or s.Right and 'Right'or s.Left and 'Left'or nil
 if direction then
  if binding.Direction~=direction then binding.NextRepeat=now+(self.Deps.repeatDelay or 0.35)
  elseif now>=(binding.NextRepeat or now)then s.Events[direction]=true;binding.NextRepeat=now+(self.Deps.repeatInterval or 0.12)end
 end
 binding.Direction=direction;binding.Previous=copy(s)
 return s
end
local rawSignalKeys={'Up','Down','Left','Right','Confirm','Cancel','PageNext','PagePrevious'}
local function observeRaw(self,p,schema,raw,now)
 self.RawSignalCounts=self.RawSignalCounts or {};self.RawSignalPrevious=self.RawSignalPrevious or {}
 local counts=self.RawSignalCounts[p]or {};self.RawSignalCounts[p]=counts
 local previous=self.RawSignalPrevious[p]
 if raw.Connected~=true or raw.Focused~=true or raw.Instance==nil then self.RawSignalPrevious[p]=nil;return end
 if previous and(previous.Instance~=raw.Instance or previous.Device~=schema.Device or previous.ControllerId~=schema.ControllerId)then previous=nil end
 local nextSample={Instance=raw.Instance,Device=schema.Device,ControllerId=schema.ControllerId}
 for _,key in ipairs(rawSignalKeys)do
  local count=counts[key]or {PressedSamples=0,RisingEdges=0};counts[key]=count
  local down=raw[key]
  if type(down)=='boolean'then
   nextSample[key]=down;count.LastSampleAt=now
   if down then
    count.PressedSamples=count.PressedSamples+1;count.LastPressedAt=now
    if previous and previous[key]==false then count.RisingEdges=count.RisingEdges+1;count.LastRiseAt=now end
   end
  end
 end
 self.RawSignalPrevious[p]=nextSample
end
function Input:Poll(now)
 assert(type(now)=='number','Monotone timestamp required')
 self.PollCount=(self.PollCount or 0)+1;self.LastPollTime=now;self.LastRaw={}
 for p=1,2 do self.Cache[p]=blank('snapshot not completed')end
 local schemas=self.Deps.schemas();local focused=self.Deps.gameHasFocus()==true
 local invalid=not schemas or not schemas[1]or not schemas[2]
 if not invalid then
  invalid=schemas[2].Device=='Keyboard'
   or schemas[1].Device=='Gamepad'and schemas[2].Device=='Gamepad'and schemas[1].ControllerId==schemas[2].ControllerId
 end
 if invalid then
  self.RawSignalPrevious={} -- diagnostic continuity unknown, not an input/rearm reset
  for p=1,2 do self.Cache[p]=blank('duplicate or incomplete player schemas');self.Bindings[p]=nil end;return
 end
 local devices=self.Deps.gamepadDevices()or {}
 for p=1,2 do
  local ok,raw=pcall(self.Sample,self,p,schemas[p],devices,focused)
  if not ok then raw=blank('device snapshot failed')end
  self.LastRaw[p]=copy(raw) -- diagnostic bookkeeping only, no additional device read
  observeRaw(self,p,schemas[p],raw,now)
  self.Cache[p]=self:Normalize(p,schemas[p],raw,now)
 end
 -- One physical pointer is never broadcast to both panels.
 if not focused then self.MouseState=nil end
 if focused and self.Deps.mouseOwner and self.Deps.mouseRead and self.Deps.hitTest then
  local owner=self.Deps.mouseOwner()
  if(owner==1 or owner==2)and self.Cache[owner].Connected and self.Cache[owner].Focused then
   local pointer=self.Deps.mouseRead(owner,{MenuKey=self.MenuKey,Focused=true})
   if pointer and pointer.Owner==owner then
    local mouse=self.MouseState
    if not mouse or mouse.Owner~=owner or mouse.Instance~=self.Cache[owner].Instance then
     mouse={Owner=owner,Instance=self.Cache[owner].Instance,Armed=false,Previous=false};self.MouseState=mouse
    end
    local primary=pointer.Primary==true;local pressed=mouse.Armed and primary and not mouse.Previous
    if not primary then mouse.Armed=true end
    local hit=self.Deps.hitTest(pointer.X,pointer.Y)
    if hit and hit.Player==owner then self.Cache[owner].Pointer={Owner=owner,X=pointer.X,Y=pointer.Y,Primary=mouse.Armed and primary,PrimaryPressed=pressed,Target=hit.Target}end
    mouse.Previous=primary
   end
  end
 end
end
return Input
