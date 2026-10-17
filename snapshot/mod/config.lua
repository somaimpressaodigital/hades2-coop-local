--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@class CoopModConfig
local Config = {
    -- Choose loot delivery type here
    -- Possible values: "Shared"
    --
    -- Shared - rooms generate one reward. Only one player can pick it up.
    -- The game has a query that select a player context for a reward.
    -- E.g. Player 1 boon room, meta progress room, Player 2 boon room, Player 1 boon room...
    LootDelivery = "Individual",
    LocalDuo = {
        AutoEnable = false,
        ControllerIds = { 0, 1 },
        RequireControllerConfirmation = false,
        UnlockAllWeapons = true,
        DifficultyFromStart = true,
        QuickPreparation = true,
        EnemyResistance = 1.70,
        BossResistance = 1.90,
        EnemyDamage = 1.10,
        CameraMinimumZoom = 0.22,
        Player2Tint = { 185, 115, 235, 255 },
    },
    Player1HasOutline = true;
    Player1Outline = {
        R = 0,
        G = 0,
        B = 200,
        Opacity = 0.6,
        Thickness = 2,
        Threshold = 0.6,
    };
    Player2HasOutline = true,
    Player2Outline = {
        R = 180,
        G = 70,
        B = 240,
        Opacity = 0.6,
        Thickness = 2,
        Threshold = 0.6,
    };
    TextAbovePlayersEnabled = true;
    TextAbovePlayersParams = {
        -- CreateTextBox params
        OffsetX = 0,
        Width = 96,
        VerticalJustification = "Bottom",
        OffsetY = -180,
        FontSize = 24,
        Color = { 255, 255, 255, 255 },
        ShadowColor = { 0, 0, 0, 240 },
        ShadowOffset = { 0, 2 },
        ShadowBlur = 0,
        OutlineThickness = 3,
        OutlineColor = { 0, 0, 0, 1 },
        Font = "LatoMedium",
        Justification = "Center"
    },
    Debug = {
        OneHit = false,
        P1GodMode = false,
        P2GodMode = false,
    }
}

return Config
