-- Existing Hades semantic control API only. No OS polling or input injection.
local M={}
function M.New(d)
 assert(type(d.Game.IsControlDown)=='function','Real Hades IsControlDown required')
 assert(type(d.NativeContext.RunWithNativeHeroContext)=='function','Existing native owner selector required')
 assert(type(d.Context.RunWithHeroContextAwait)=='function','Existing hero context required')
 assert(type(d.GetSchemas)=='function'and type(d.HasFocus)=='function')
 local heroRef,instance
 local function unavailable(reason)return {Connected=false,Focused=false,Reason=reason}end
 return function(player,request)
  local schemas=d.GetSchemas()
  if player~=1 or not schemas or not schemas[1]or schemas[1].Device~='Keyboard'then return unavailable('J1 keyboard schema required')end
  if not request or request.Focused~=true or d.HasFocus()~=true then return unavailable('Hades is not focused')end
  local hero=d.Players.GetHero(1)
  if not hero or hero.IsDead or d.Players.GetPlayerByHero(hero)~=1 then return unavailable('Keyboard owner unavailable')end
  if heroRef~=hero then heroRef=hero;instance={}end -- stable identity of actual engine keyboard role
  local ok,value=pcall(d.Context.RunWithHeroContextAwait,hero,function()
   assert(d.Context.GetCurrentHeroContext()==hero,'Wrong Lua keyboard owner')
   return d.NativeContext.RunWithNativeHeroContext(1,function()
    -- No yield while engine root points to owner1. No undocumented PlayerIndex arg.
    local function down(name)
     local held=d.Game.IsControlDown({Name=name})
     assert(type(held)=='boolean','Hades control reader returned no boolean')
     return held
    end
    return {Connected=true,Focused=true,Instance=instance,
     Up=down('Up')or down('MenuUp'),Down=down('Down')or down('MenuDown'),
     Left=down('Left'),Right=down('Right'),Confirm=down('Confirm'),Cancel=down('Cancel'),
     PagePrevious=down('MenuLeft'),PageNext=down('MenuRight')}
   end)
  end)
  if not ok then return unavailable('Native keyboard read failed: '..tostring(value))end
  if d.HasFocus()~=true or d.Players.GetHero(1)~=hero then return unavailable('Keyboard scope changed while sampling')end
  return value
 end
end
return M
