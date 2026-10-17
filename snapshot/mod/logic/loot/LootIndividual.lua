-- Room upgrades belong to each hero; permanent resources remain shared once.
local Shared = ModRequire "LootShared.lua"
local Players = ModRequire "../CoopPlayers.lua"
local Context = ModRequire "../HeroContext.lua"
local RenderProbe = ModRequire "../LocalDuoRenderProbe.lua"
local CentaurModule = ModRequire "../LocalDuoSharedCentaurHeart.lua"
local ManaModule = ModRequire "../LocalDuoSharedMaxManaDrop.lua"
local Individual = {}
Individual.PersonalSpawnDepth = 0
local PersonalRewards = {
    Boon = true, WeaponUpgrade = true, StackUpgrade = true,
    HermesUpgrade = true, MaxHealthDrop = true, MaxManaDrop = true,
    SpellDrop = true, TalentDrop = true, MinorTalentDrop = true, TalentBigDrop = true,
    StackUpgradeBig = true, StackUpgradeTriple = true,
}

Individual.InitHooks = Shared.InitHooks
Individual.Reset = Shared.Reset
Individual.GiveLoot = Shared.GiveLoot
Individual.GiveBlindLoot = Shared.GiveBlindLoot

function Individual.OnUnlockedRewardedRoom(base, run, room)
    -- Generate doors once. Do not advance alternating-player reward queues.
    return base(run, room)
end

function Individual.IsPersonalReward(room, args)
    local encounter = room.Encounter or {}
    local kind = (args or {}).RewardOverride or encounter.EncounterRoomRewardOverride
        or room.ChangeReward or room.ChosenRewardType
    return PersonalRewards[kind] == true and not room.DeferReward
        and not (room.Reward and room.Reward.FunctionName)
end

function Individual.CanUseHeroLoot(loot, hero)
    if LocalDuoCoopModeActive==true and RenderProbe.IsTestProfile()==true then
        if loot.LocalDuoCommonCarrier then return false end
        if loot.LocalDuoCommonRoot then return hero==Players.GetHero(1)or hero==Players.GetHero(2)end
    end
    local owner = loot.LocalDuoOwner
    if not owner then return true end
    local assigned = Players.GetHero(owner)
    -- A fallen player's uncollected reward must not lock the room.
    return assigned == hero or not assigned or assigned.IsDead == true
end

function Individual.SpawnRoomReward(base, source, args)
    local room = CurrentRun.CurrentRoom
    local centaur=CentaurModule.Runtime
    if centaur and centaur.IsRoomReward(room,args) then return centaur.Spawn(base,source,args) end
    local mana=ManaModule.Runtime
    if mana and mana.IsRoomReward(room,args) then return mana.Spawn(base,source,args) end
    if not Individual.IsPersonalReward(room, args) then
        return Shared.SpawnRoomReward(base, source, args)
    end
    local heroes = Players.GetAliveHeroes()
    room.LocalDuoRewardSerial=(room.LocalDuoRewardSerial or 0)+1
    local bundle=room.LocalDuoRewardSerial
    Individual.PersonalSpawnDepth = Individual.PersonalSpawnDepth + 1
    local result
    local rewards = {}
    local startingCount = CurrentRun.BiomeRewardsSpawned or 0
    local ok, failure = pcall(function()
    for _, hero in ipairs(heroes) do
        local options = DeepCopyTable(args or {})
        options.SpawnRewardOnId = hero.ObjectId
        options.OffsetX = (Players.GetPlayerByHero(hero) == 1 and -120 or 120)
        options.IgnoreRoomSpawnOnLootPoint = true
        -- Spawn all rewards before waiting, otherwise simultaneous pickups can deadlock.
        options.WaitUntilPickup = false
        local reward
        local rootReward=rewards[1]
        local common=LocalDuoCoopModeActive==true and RenderProbe.IsTestProfile()==true and #heroes==2
            and rootReward and rootReward.OnUsedFunctionName=='UseLoot' and rootReward.UpgradeOptions
            and not rootReward.ResourceCosts and not rootReward.BoughtFromShop and not rootReward.UpgradeOnPick
        if common then
            reward=DeepCopyTable(rootReward)
            local id=SpawnObstacle({Name='BlankObstacle',DestinationId=rootReward.ObjectId,Group='Standing'})
            reward.ObjectId=id;reward.LocalDuoCommonRoot=nil;reward.LocalDuoCommonCarrier=true
            reward.LocalDuoCommonRootId=rootReward.ObjectId;rootReward.LocalDuoCommonRoot=true
            reward.LocalDuoOwner=Players.GetPlayerByHero(hero);reward.LocalDuoBundle=bundle
            -- J1's source already rolled in base. Generate J2 once with the same god,
            -- fresh native personal eligibility/rarity/swap decisions, never copy its offers.
            reward.UpgradeOptions=nil;reward.RarityChances=nil;reward.RarityBoosted=nil
            reward.ForceCommon=nil;reward.ForceCommonWithoutCurse=nil;reward.UseSwapTrait=nil
            Context.RunWithHeroContextAwait(hero,SetTraitsOnLoot,reward,options)
            assert(CurrentRun.CurrentRoom==room and Players.GetHero(reward.LocalDuoOwner)==hero
                and reward.Name==rootReward.Name and type(reward.UpgradeOptions)=='table','Personal native roll changed owner/room/god')
            reward.InteractBlocks={};reward.CanReceiveGift=false
            AttachLua({Id=id,Table=reward});UseableOff({Id=id})
            SetObstacleProperty({DestinationId=id,Property='CollidesWithObstacles',Value=false})
            SetAlpha({Id=id,Fraction=0,Duration=0})
            LootObjects[id]=reward;MapState.RoomRequiredObjects[id]=reward
        else
            reward = Context.RunWithHeroContextAwait(hero, base, source, options)
        end
        if reward then
            reward.LocalDuoOwner = Players.GetPlayerByHero(hero)
            reward.LocalDuoBundle = bundle
            local location = GetLocation({ Id = hero.ObjectId })
            if not reward.LocalDuoCommonCarrier and location and type(location.X)=="number" and type(location.Y)=="number" then
                Teleport({ Id = reward.ObjectId,
                    OffsetX = location.X + (reward.LocalDuoOwner == 1 and -150 or 150),
                    OffsetY = location.Y + 100 })
            end
            table.insert(rewards, reward)
            result = result or reward
            local commonLabel=LocalDuoCoopModeActive==true and RenderProbe.IsTestProfile()==true and #heroes==2
                and reward.OnUsedFunctionName=='UseLoot' and reward.UpgradeOptions and not reward.ResourceCosts
                and not reward.BoughtFromShop and not reward.UpgradeOnPick
            if CreateTextBox and not reward.LocalDuoCommonCarrier and not commonLabel then
                CreateTextBox({ Id = reward.ObjectId,
                    Text = "JOGADOR " .. tostring(reward.LocalDuoOwner),
                    Font = "LatoMedium", FontSize = 18, OffsetY = -75,
                    Color = reward.LocalDuoOwner == 1 and {100,160,255,255} or {205,135,255,255},
                    Justification = "Center", })
            end
        end
    end
    end)
    Individual.PersonalSpawnDepth = Individual.PersonalSpawnDepth - 1
    -- Keep biome counters in rooms rather than copies of the same room reward.
    if result then CurrentRun.BiomeRewardsSpawned = startingCount + 1 end
    if not ok then error(failure, 0) end
    if type(LocalDuoTrySingleVisibleBoonPair)=='function' then
        pcall(LocalDuoTrySingleVisibleBoonPair,rewards,room,bundle)
    end
    if args and args.WaitUntilPickup and result then
        while CurrentRun.CurrentRoom == room do
            local pending = false
            for _, loot in ipairs(rewards) do
                if MapState and MapState.RoomRequiredObjects
                    and MapState.RoomRequiredObjects[loot.ObjectId] then pending = true; break end
            end
            if not pending then break end
            wait(0.1)
        end
    end
    return result
end

return Individual
