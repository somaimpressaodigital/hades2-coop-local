-- Lazy operational runtime assembly. Import does not open UI or register callbacks.
local Players=ModRequire 'CoopPlayers.lua'
local Context=ModRequire 'HeroContext.lua'
local NativeContext=ModRequire 'HeroContextNative.lua'
local Control=ModRequire 'CoopControl.lua'
local Gate=ModRequire 'LocalDuoRenderProbe.lua'
local Character=ModRequire 'LocalDuoCharacter.lua'
local Events=ModRequire 'Events.lua'
local Loot=ModRequire 'loot/LootIndividual.lua'
local M={}
local base='<WORKSPACE>/work/duo-runtime-6/'
local root='<WORKSPACE>/work/integration/duo-entry-pilot/'
function M.Ensure()
 if LocalDuoCoopModeActive~=true or Gate.IsTestProfile()~=true or Players.GetPlayersCount()~=2 then return nil end
 local run=CurrentRun;if not run or not run.CurrentRoom then return nil end
 if M.Run==run and M.Runtime then return M.Runtime end
 if LocalDuoRewardRouting and LocalDuoRewardRouting~=M.Runtime then return nil,'Another reward router is active'end
 if M.Runtime then
  for _,record in pairs(M.Runtime.Host.Records)do
   if record.Handle and record.Handle.Session.State~='closed'then return nil,'Previous session needs cleanup'end
   if record.EntryFault and not record.EmergencyDone then return nil,'Previous opening needs cleanup'end
  end
  if M.Runtime.Disable then M.Runtime:Disable() else M.Runtime.Enabled=false;M.Runtime.Bridge.Enabled=false end
 end
 local ok,runtime,report=pcall(function()
  local physical=LocalDuoPhysicalInput
  local modules=assert(loadfile(base..'LoadModules.lua','t',_G))()(base)
  local factory=assert(loadfile(base..'DuoRuntime6.lua','t',_G))()
  local keyboard
  if Control.Schemas.Current[1] and Control.Schemas.Current[1].Device=='Keyboard' then
   local reader=assert(loadfile('<WORKSPACE>/work/integration/keyboard-read-pilot/HadesKeyboardRead.lua','t',_G))()
   keyboard=reader.New{Game=_G,NativeContext=NativeContext,Context=Context,Players=Players,
    GetSchemas=function()return Control.Schemas.Current end,
    HasFocus=function()return physical.read(-1).Focused==true end}
  end
  local rootAlpha=assert(loadfile(base..'modules/RootAlphaPrototype.lua','t',_G))()
  local shop=assert(loadfile(base..'modules/OrdinaryShopPair.lua','t',_G))().New{Game=_G,Context=Context,Players=Players,Gate=Gate}
  return factory.Build{Diagnostics=ModRequire 'LocalDuoDiagnostics.lua',Shop=shop,RootAlpha=rootAlpha,Modules=modules,Game=_G,Context=Context,NativeContext=NativeContext,Players=Players,Control=Control,
   UIInputSnapshot=assert(loadfile('<WORKSPACE>/work/integration/UIInputSnapshotWriter.lua','t',_G))(),
   Gate=Gate,PhysicalInput=physical,Character=Character,Events=Events,LootIndividual=Loot,KeyboardRead=keyboard,
   -- OriginalActor is visual identity; only the explicit legacy weapon flag denotes H1 mechanics.
   IsOriginalSword=function(hero)return hero and (hero.LocalDuoOriginalSword==true or hero.LocalDuoUsesLegacySwordMechanics==true) end,
   Layout=assert(loadfile(root..'DuoVisualLayout.lua','t',_G))(),
   Templates=assert(loadfile(root..'NativeTextTemplates.lua','t',_G))(),
   Now=function()return physical.read(-1).Time end}
 end)
 if not ok or not runtime then M.Error=ok and report or runtime;return nil,M.Error end
 local subscribed,err=pcall(runtime.Subscribe,runtime)
 if not subscribed then runtime.Enabled=false;runtime.Bridge.Enabled=false;M.Error=err;return nil,err end
 M.Run=run;M.Runtime=runtime
 LocalDuoRewardRouting=runtime
 LocalDuoSingleVisibleBoonPickup=runtime.SingleVisible
 return runtime
end
return M
