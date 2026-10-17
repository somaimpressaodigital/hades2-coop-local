-- Both owners use native Melinoe and Hades II mechanics; J2 tint is a separate helper.
local Character={}
-- Native ModRequire must first load this module on the main Lua stack.
local personalRecolor=ModRequire "PersonalRecolorV2.lua"
function Character.Name(player)
    -- Human policy: both owners use Melinoe/H2; old saved appearance is not a backend selector.
    return "Melinoe"
end
function Character.Swap(melinoeHero)
    -- No character or Arcana ownership transfer when both owners are Melinoe.
    return false
end
function Character.Apply(player,hero)
    if not hero or hero.IsDead or not hero.ObjectId then return end
    local players=ModRequire "CoopPlayers.lua"
    if (player~=1 and player~=2) or players.GetHero(player)~=hero
        or players.GetPlayerByHero(hero)~=player then return end
    -- Fresh actors stay native Melinoe. Preserve all H2 weapons, boons and personal Arcana.
    -- No model/texture/animation force or legacy path from a cosmetic actor marker.
    hero.LocalDuoCharacter="Melinoe"
    personalRecolor.ApplyPersonal(hero)
end
return Character
