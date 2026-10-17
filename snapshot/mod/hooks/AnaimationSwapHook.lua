--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type SimpleHook
local SimpleHook = ModRequire "../utils/SimpleHook.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../logic/CoopPlayers.lua"

local ANIMATIONS_TO_SWAP = {
    ["MelinoeIdle"] = true;
    ["MelinoeDashStart"] = true;
    ["MelinoeDash"] = true;
    ["MelinoeSprint"] = true;
    ["MelinoeStart"] = true;
    ["MelinoeRun"] = true;
    ["MelinoeStop"] = true;
    ["MelinoeGetHit"] = true;
    ["Melinoe_GetHit_LastStand"] = true;

    ["Melinoe_Cast_Start"] = true;
    ["Melinoe_Cast_StartLoop"] = true;
    ["Melinoe_Cast_Fire"] = true;
    ["Melinoe_Cast_End"] = true;
    ["Melinoe_Cast_Fire_Quick"] = true;

    ["Melinoe_CrossCast_Start"] = true;
    ["Melinoe_ForwardCast_Unequip"] = true;

    ["MelinoeEquip"] = true;
    ["MelinoeActionIdle"] = true;
    ["MelinoeInteract"] = true;
    ["MelinoeBoonPreInteract"] = true;
}

local Character = ModRequire "../logic/LocalDuoCharacter.lua"
local CAST_ONLY = {
    Melinoe_Cast_Start = "LocalDuoH1_GroundCast_Charge",
    Melinoe_Cast_StartLoop = "LocalDuoH1_GroundCast_Hold",
    Melinoe_Cast_Fire = "LocalDuoH1_ZagreusSwordUpdateIdleLoop",
    Melinoe_Cast_Fire_Quick = "LocalDuoH1_ZagreusSwordUpdateIdleLoop",
    Melinoe_Cast_End = "LocalDuoH1_ZagreusSwordUpdateIdleLoop",
}
local function originalZagreusDestination(playerIndex,args)
    local hero=CoopPlayers.GetHero(playerIndex)
    if hero and CurrentRun and CurrentRun.Hero==hero and not hero.IsDead and hero.ObjectId and hero.LocalDuoOriginalActor==hero.ObjectId
        and Character.Name(playerIndex)=="Zagreus" then
        return CAST_ONLY[args.Name] or args.DestinationName
    end
    return args.DestinationName
end

local AnaimationSwapHook = SimpleHook.New()

function AnaimationSwapHook.wrap.SwapAnimation(baseFun, args)
    if ANIMATIONS_TO_SWAP[args.Name] then
        local playerIndex = CoopPlayers.GetCurrentPlayerId() or 1
        if args.Reverse then
            CoopRemoveAnimationSwap(playerIndex, args.Name)
        else
            CoopSetAnimationSwap(playerIndex, args.Name, originalZagreusDestination(playerIndex,args))
        end
    else
        baseFun(args)
    end
end

return AnaimationSwapHook
