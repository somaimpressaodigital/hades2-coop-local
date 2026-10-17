-- Local assembly loader. No engine callbacks or global installation.
return function(base)
 base=base or '<WORKSPACE>/work/duo-runtime-6/'
 local paths={
  FreeHammer='modules/FreeCommonHammer.lua',HostFactory='modules/DuoBoonGameHost.lua',Protection='modules/ScopedOperationalProtection.lua',
  CompatibleRows='modules/CompatibleRows.lua',SwordAdapter='modules/SwordBoonAdapter.lua',
  Entry='modules/DuoBoonEntry.lua',Model='modules/DuoBoonModel.lua',Adapter='modules/DuoBoonAdapter.lua',
  Apply='modules/DuoBoonApply.lua',Choices='modules/DuoBuildChoices.lua',Session='modules/DuoScreenSession.lua',
  View='modules/DuoBoonView.lua',Input='modules/DuoMenuInput.lua',
  CacheRuntime='DuoSimultaneousRuntime.lua',PickupBridge='modules/OperationalDuoPickupBridge.lua'}
 paths.PomOffer='modules/PreparePomOffer.lua'
 paths.CommonOffers='modules/CommonBoonOffers.lua'
 paths.ChaosOffer='modules/ChaosOffer.lua'
 local modules={};for key,path in pairs(paths)do modules[key]=assert(loadfile(base..path,'t',_G))()end
 return modules
end
