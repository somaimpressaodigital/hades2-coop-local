-- Cosmetic background only. Never changes the current hero/native death context.
local Players=ModRequire 'CoopPlayers.lua'
local Character=ModRequire 'LocalDuoCharacter.lua'
local Gate=ModRequire 'LocalDuoRenderProbe.lua'
local M={};local usedRun
function M.Present(base,scopeSource,...)
 if usedRun~=CurrentRun then usedRun=nil end
 if LocalDuoZagreusDeathBackgroundPreview~=true or type(scopeSource)~='table'
  or type(scopeSource.GetTerminalVisualScope)~='function' then return base(...)end
 local token=scopeSource.GetTerminalVisualScope()
 local descriptor=LocalDuoZagreusDeathBackgroundCandidate
 local function valid()
  return token and LocalDuoZagreusDeathBackgroundPreview==true and Gate.IsTestProfile()==true
   and LocalDuoCoopModeActive==true and not CurrentHubRoom and CurrentRun==token.Run
   and CurrentRun.CurrentRoom==token.Room and MapState==token.Map and SessionMapState==token.Session and CurrentRun.LocalDuoEnding==true
   and not CurrentRun.Cleared and not CurrentRun.BountyCleared
   and Players.GetPlayersCount()==2 and (token.TerminalVictimOwner==1 or token.TerminalVictimOwner==2)
   and Players.GetHero(token.TerminalVictimOwner)==token.TerminalVictimRef
   and token.HeroRefs and token.Ids and Players.GetHero(1)==token.HeroRefs[1]and Players.GetHero(2)==token.HeroRefs[2]
   and token.HeroRefs[1].ObjectId==token.Ids[1]and token.HeroRefs[2].ObjectId==token.Ids[2]
   and token.TerminalVictimRef.LocalDuoOriginalActor==token.TerminalVictimRef.ObjectId
   and not token.TerminalVictimRef.LocalDuoUsesLegacySwordMechanics and not token.TerminalVictimRef.LocalDuoOriginalSword
   and Character.Name(token.TerminalVictimOwner)=='Zagreus'
   and descriptor and descriptor.Registered==true
 end
 if not valid()or usedRun==CurrentRun then return base(...)end
 local prior=SetAnimation;local replaced=false
 local function scoped(args,...)
  local fresh=scopeSource.GetTerminalVisualScope()
  if not replaced and fresh and fresh.Run==token.Run and fresh.TerminalVictimRef==token.TerminalVictimRef
   and fresh.TerminalVictimOwner==token.TerminalVictimOwner and valid()and type(args)=='table'and args.Name=='DeathSequenceMelBG'
   and ScreenAnchors and args.DestinationId==ScreenAnchors.DeathBackground then
   local copy={};for k,v in pairs(args)do copy[k]=v end
   copy.Name=descriptor.Animation;replaced=true;usedRun=CurrentRun
   return prior(copy,...)
  end
  return prior(args,...)
 end
 SetAnimation=scoped
 local outcome=table.pack(pcall(base,...))
 if SetAnimation==scoped then SetAnimation=prior end -- Never overwrite a foreign replacement.
 if not outcome[1]then error(outcome[2],0)end
 return table.unpack(outcome,2,outcome.n)
end
return M
