-- Persistent H2 selection projection using the existing splitter/store/save lifecycle.
local Store=ModRequire 'HeroContextProxySpliterStore.lua'
local Players=ModRequire 'CoopPlayers.lua'
local Gate=ModRequire 'LocalDuoRenderProbe.lua'
local M={};local owned
local key='LocalDuoPersonalWeaponSelections'
local fields={'LastWeaponUpgradeName','PrimaryWeaponName'}
local function enabled()
 return LocalDuoCoopModeActive==true and Gate.IsTestProfile()==true and Players.GetPlayersCount()==2
end
local function copy(t)return DeepCopyTable(t)end
local function validSelection(s)
 return type(s)=='table' and type(s.LastWeaponUpgradeName)=='table'
  and (s.PrimaryWeaponName==nil or type(s.PrimaryWeaponName)=='string')
end
local function snapshot(handler)
 local a,b=handler:GetPlayerData(1),handler:GetPlayerData(2)
 assert(validSelection(a)and validSelection(b)and a~=b and a.LastWeaponUpgradeName~=b.LastWeaponUpgradeName,
  'Personal aspect selections are missing or aliased')
 return {[1]=copy(a),[2]=copy(b)}
end
-- Private lifetime record; its token identifies Lua ownership, never native admission.
local arena;local resumeTarget
local function rememberTables(value,pins)
 if type(value)~='table'or pins[value]then return end
 local entries={};pins[value]=entries
 for k,v in next,value do entries[k]=v;rememberTables(k,pins);rememberTables(v,pins)end
end
local function originalIntact(a)
 if getmetatable(a.Original)~=a.Metatable then return false,'Original selection metatable changed'end
 for _,name in ipairs({'LastWeaponUpgradeName','PrimaryWeaponName','LocalDuoWeaponSelections'})do
  if rawget(a.Original,name)~=a.Raw[name]then return false,'Original selection field changed: '..name end
 end
 for target,entries in next,a.Pins do
  for k,v in next,entries do if rawget(target,k)~=v then return false,'Original selection data changed'end end
  for k,v in next,target do if entries[k]~=v then return false,'Original selection data changed'end end
 end
 if a.Owned and(a.Owned.Target~=a.Original or a.Owned.Handler.target~=a.Original or a.Owned.Handler.data~=a.HandlerData
  or not a.Metatable or a.Metatable.handler~=a.Owned.Handler)then return false,'Original selection owner changed'end
 return true
end
local function privateCurrent(a)
 local ok,state=pcall(a.ReadOwnedState)
 if not ok or type(state)~='table'or state==a.Original then return nil,'Actual Arena state reader unavailable'end
 if GameState~=state then return nil,'Current GameState is not the actual owned Arena state'end
 local valid,why=originalIntact(a);if not valid then return nil,why end
 a.Targets[state]=true
 return state
end
function M.CanBeginArenaScope(originalState)
 if arena then return false,'Personal selection Arena lifetime already active'end
 if originalState~=GameState or type(originalState)~='table'or not enabled()then return false,'Actual original coop GameState required'end
 local handler=Store.Get(key);local mt=getmetatable(originalState)
 if owned then
  if owned.Target~=originalState or handler~=owned.Handler or type(mt)~='table'
   or mt.handler~=handler or handler.target~=originalState then return false,'Foreign original selection projection'end
 elseif handler~=nil or mt~=nil then return false,'Foreign original selection registry/metatable'end
 return true
end
function M.BeginArenaScope(originalState,readOwnedState)
 local ready,why=M.CanBeginArenaScope(originalState);if not ready then return nil,why end
 if type(readOwnedState)~='function'then return nil,'Actual Arena state reader required'end
 local ok,state=pcall(readOwnedState)
 if not ok or type(state)~='table'or state==originalState then return nil,'Actual private Arena GameState required'end
 -- Reader may yield: recheck the untouched original immediately before suspension.
 ready,why=M.CanBeginArenaScope(originalState);if not ready then return nil,why end
 local a={Token={},Original=originalState,Owned=owned,Handler=Store.Get(key),Metatable=getmetatable(originalState),
  HandlerData=owned and owned.Handler.data,ReadOwnedState=readOwnedState,Raw={},Pins={},Targets={[state]=true}}
 for _,name in ipairs({'LastWeaponUpgradeName','PrimaryWeaponName','LocalDuoWeaponSelections'})do
  a.Raw[name]=rawget(originalState,name);rememberTables(a.Raw[name],a.Pins)
 end
 if owned then rememberTables(owned.Handler.data,a.Pins)end
 arena=a;owned=nil;resumeTarget=nil
 -- Suspend only the registry slot. Never detach, serialize or rewrite the original target.
 Store.Delete(key)
 return a.Token
end
function M.VerifyArenaScope(token,ownedState)
 local a=arena;if not a or token~=a.Token then return false,'Unknown personal selection Arena lifetime'end
 local current,why=privateCurrent(a);if not current then return false,why end
 if ownedState~=current then return false,'Foreign Arena selection state'end
 if owned then
  local mt=getmetatable(owned.Target)
  if owned.Target~=current or not a.Targets[owned.Target]or owned.Target==a.Original or Store.Get(key)~=owned.Handler
   or owned.Handler.target~=owned.Target or type(mt)~='table'or mt.handler~=owned.Handler then
   return false,'Foreign private selection projection'
  end
 elseif Store.Get(key)~=nil then return false,'Foreign private selection registry'end
 return true
end
function M.EndArenaScope(token)
 local a=arena;if not a or token~=a.Token then return false,'Unknown personal selection Arena lifetime'end
 local valid,why=originalIntact(a);if not valid then return false,why end
 if GameState==a.Original then
  if owned or Store.Get(key)~=nil then return false,'Private selection bank must retire before root restoration'end
 else
  valid,why=M.VerifyArenaScope(token,GameState);if not valid then return false,why end
 end
 if owned then M.Detach()end -- Only a recorded private Arena target may be detached.
 if Store.Get(key)~=nil then return false,'Private selection registry still occupied'end
 if a.Handler then Store.Set(key,a.Handler)end
 owned=a.Owned;arena=nil;resumeTarget=a.Original
 return true
end

function M.IsActive()
 if resumeTarget and GameState~=resumeTarget then return false end
 if arena and not privateCurrent(arena)then return false end
 if not owned or not enabled()or owned.Target~=GameState or Store.Get(key)~=owned.Handler then return false end
 local mt=getmetatable(GameState)
 return type(mt)=='table'and mt.handler==owned.Handler and owned.Handler.target==GameState
end
function M.Detach()
 if not owned then return true end
 assert(not resumeTarget or GameState==resumeTarget,'Original selection root restoration pending')
 if arena then
  local current,why=privateCurrent(arena);assert(current,why)
  assert(owned~=arena.Owned and owned.Target~=arena.Original and arena.Targets[owned.Target],'Cannot detach original or foreign Arena selection bank')
 end
 local target,handler=owned.Target,owned.Handler
 local mt=getmetatable(target)
 assert(type(mt)=='table'and mt.handler==handler and Store.Get(key)==handler,
  'Cannot detach a foreign GameState projection')
 rawset(target,'LocalDuoWeaponSelections',snapshot(handler))
 handler:MovePlayerDataToTarget(1) -- ordinary stock fields, owner 1 authoritative in Solo
 setmetatable(target,nil)
 Store.Delete(key);owned=nil
 return true
end
function M.Ensure()
 if resumeTarget then
  if GameState~=resumeTarget then return nil,'Original selection root restoration pending'end
  resumeTarget=nil
 end
 if arena then local current,why=privateCurrent(arena);if not current then return nil,why end end
 if not enabled()then M.Detach();return nil,'Profile3 explicit coop with two players required' end
 if M.IsActive()then return owned.Handler end
 if owned then M.Detach()end -- retire only the exact prior owned target on a GameState replacement
 assert(type(GameState)=='table'and getmetatable(GameState)==nil,'Foreign GameState metatable is not supported')
 assert(Store.Get(key)==nil,'Foreign personal selection registry entry')
 assert(type(rawget(GameState,'LastWeaponUpgradeName'))=='table','Stock aspect map unavailable')
 local base={LastWeaponUpgradeName=copy(rawget(GameState,'LastWeaponUpgradeName')),
  PrimaryWeaponName=rawget(GameState,'PrimaryWeaponName')}
 local saved=rawget(GameState,'LocalDuoWeaponSelections')
 local second
 if type(saved)=='table'then second=saved[2]end
 assert(second==nil or validSelection(second),'Saved owner2 selection schema is invalid')
 second=copy(second or base) -- initialize old saves from stock without changing unlocks/ranks
 local handler=Store.GetOrCreate(key,GameState,fields)
 -- Owner 1 always comes from native raw fields, including any newer Solo selection.
 handler.data[1]=base;handler.data[2]=second
 owned={Target=GameState,Handler=handler}
 return handler
end
function M.Get(player)
 assert(player==1 or player==2,'Selection owner must be 1 or 2')
 local handler,reason=M.Ensure();if not handler then return nil,reason end
 return handler:GetPlayerData(player)
end
function M.PreSave()
 local handler=M.Ensure();if not handler then return end -- other profiles retain stock saving
 -- Plain copied tables under GameState are serialized by the existing stock saveTable route.
 rawset(GameState,'LocalDuoWeaponSelections',snapshot(handler))
end
function M.PostSave()
 assert(not resumeTarget or GameState==resumeTarget,'Original selection root restoration pending')
 if arena then local current,why=privateCurrent(arena);assert(current,why)end
 if owned and owned.Target==GameState then
  assert(Store.Get(key)==owned.Handler,'Personal selection registry changed during save')
  owned.Handler:RemoveKeysFromTarget()
 end
end
function M.Load()return M.Ensure()end
return M
