local FamilyTrip = {}

local Ability = require "necro.game.system.Ability"
local Action = require "necro.game.system.Action"
local AffectorItem = require "necro.game.item.AffectorItem"
local Attack = require "necro.game.character.Attack"
local Beatmap = require "necro.audio.Beatmap"
local Boss = require "necro.game.level.Boss"
local Character = require "necro.game.character.Character"
local Collision = require "necro.game.tile.Collision"
local Components = require "necro.game.data.Components"
local Currency = require "necro.game.item.Currency"
local CurrentLevel = require "necro.game.level.CurrentLevel"
local CustomActions = require "necro.game.data.CustomActions"
local CustomEntities = require "necro.game.data.CustomEntities"
local Damage = require "necro.game.system.Damage"
local Delay = require "necro.game.system.Delay"
local Descent = require "necro.game.character.Descent"
local ECS = require "system.game.Entities"
local EnemySubstitutions = require "necro.game.system.EnemySubstitutions"
local EntitySelector = require "system.events.EntitySelector"
local Facing = require "necro.game.character.Facing"
local Focus = require "necro.game.character.Focus"
local GrooveChain = require "necro.game.character.GrooveChain"
local Interaction = require "necro.game.object.Interaction"
local Invincibility = require "necro.game.character.Invincibility"
local ItemBan = require "necro.game.item.ItemBan"
local ItemSlot = require "necro.game.item.ItemSlot"
local Kill = require "necro.game.character.Kill"
local LocalCoop = require "necro.client.LocalCoop"
local Move = require "necro.game.system.Move"
local Object = require "necro.game.object.Object"
local ObjectEvents = require "necro.game.object.ObjectEvents"
local ObjectMap = require "necro.game.object.Map"
local Player = require "necro.game.character.Player"
local ProceduralLevel = require "necro.game.data.level.ProceduralLevel"
local RNG = require "necro.game.system.RNG"
local Respawn = require "necro.game.character.Respawn"
local Settings = require "necro.config.Settings"
local SettingsMenu = require "necro.menu.settings.SettingsMenu"
local Snapshot = require "necro.game.system.Snapshot"
local StringUtilities = require "system.utils.StringUtilities"
local SoulLink = require "necro.game.character.SoulLink"
local Team = require "necro.game.character.Team"
local Tile = require "necro.game.tile.Tile"
local Turn = require "necro.cycles.Turn"
local Utilities = require "system.utils.Utilities"

local Utilities_squareDistance = Utilities.squareDistance

FamilyTrip.EnemySubstitutions_Type = EnemySubstitutions.Type.extend "FamilyTrip_FamilySoul"

local FamilyTrip_familyMemberGrooveChainIdleImmunity_types = Utilities.listToSet {
	GrooveChain.Type.IDLE,
	GrooveChain.Type.FAIL,
}

Components.register {
	FamilyTrip_attackableOverrideInLobby = {
		Components.constant.enum("attackFlags", Attack.Flag, Attack.Flag.mask(Attack.Flag.PLAYER_CONTROLLED, Attack.Flag.TRAP)),
	},
	FamilyTrip_autoAttackTarget = {},
	FamilyTrip_family = {
		Components.constant.table("initialMembers"),
		Components.constant.string("initialObjectLink", "FamilyTrip_ObjectLinkFamily"),
		Components.constant.string("initialSoulLink", "FamilyTrip_SoulLinkFamily"),
		Components.constant.bool("invisibleSprite", true),
		Components.field.table("members"),
		Components.constant.enum("moveFlagUnmask", Move.Flag, Move.Flag.mask(Move.Flag.ALLOW_PARTIAL_MOVE, Move.Flag.COLLIDE_DESTINATION, Move.Flag.COLLIDE_INTERMEDIATE)),
	},
	FamilyTrip_familyControlSpectator = {
		Components.dependency("spectator"),
	},
	FamilyTrip_familyDescent = {
		Components.dependency("FamilyTrip_family"),
		Components.dependency("descent"),
	},
	FamilyTrip_familyFocusLeader = {
		Components.dependency("FamilyTrip_family"),
	},
	FamilyTrip_familyFragile = {
		Components.field.bool("broken"),
		Components.constant.float("killDelay", .125),
		Components.dependency("FamilyTrip_family"),
	},
	FamilyTrip_familyRhythmInheritMember = {
		Components.dependency("FamilyTrip_family"),
	},
	FamilyTrip_familyTeleport = {
		Components.constant.bool("trappableImmune", true),
		Components.constant.enum("moveType", Move.Flag, Move.Flag.mask(Move.Flag.FORCED_MOVE, Move.Flag.TELEFRAG)),
		Components.dependency("FamilyTrip_family"),
	},
	FamilyTrip_familyThrowBomb = {
		Components.constant.bool("mustBeLeader", true),
		Components.constant.int("pushDistance", 1),
		Components.constant.enum("pushType", Move.Flag, Move.Type.NORMAL),
	},
	FamilyTrip_familyMember = {
		Components.field.entityID("family"),
		Components.dependency("character"),
		Components.dependency("gameObject"),
		Components.dependency("position"),
	},
	FamilyTrip_familyMemberActivation = {},
	FamilyTrip_familyMemberAutoAct = {
		Components.constant.table("directions"),
	},
	FamilyTrip_familyMemberAttacker = {},
	FamilyTrip_familyMemberDeathKillFamilyFragile = {},
	--- Dig cracked tiles automatically.
	FamilyTrip_familyMemberDigger = {},
	--- Family members that not leaders immune to specific groove chains.
	FamilyTrip_familyMemberGrooveChainIdleImmunity = {
		Components.constant.int("immuneTurns", 1),
		Components.field.int("turns"),
		Components.constant.table("types", FamilyTrip_familyMemberGrooveChainIdleImmunity_types),
		Components.dependency("FamilyTrip_familyMember"),
	},
	FamilyTrip_familyMemberMovable = {
		Components.field.bool("value"),
		Components.dependency("movable"),
	},
	FamilyTrip_familyMemberMover = {
		Components.dependency("FamilyTrip_familyMember"),
	},
	FamilyTrip_familyMemberChestOpener = {
		Components.dependency("FamilyTrip_familyMember"),
	},
	FamilyTrip_familyMemberPersistent = {
		Components.dependency("FamilyTrip_familyMember"),
	},
	FamilyTrip_familyMemberProtectWeaker = {
		Components.dependency("FamilyTrip_familyMember"),
		Components.dependency("health"),
	},
	--- Let entity use beat bar visual from family leader entity instead of self.
	FamilyTrip_familyMemberRefactorBeatBar = {},
	--- Share family leader's invincibility to family members.
	FamilyTrip_familyMemberShareInvincibilityOnDamage = {
		Components.dependency("FamilyTrip_familyMember"),
		Components.dependency("invincibility"),
		Components.dependency("invincibilityOnHit"),
	},
	FamilyTrip_familyUseLeaderSpriteOnPlayerList = {},
	--- Set gameplay facing.
	FamilyTrip_setFacingOnMove = {},
	FamilyTrip_soulLinkHeal = {},
	FamilyTrip_tagBomb = {},
	FamilyTrip_tagChest = {},
	FamilyTrip_tagPotion = {},
	-- Replaces the final boss in the run with story bosses.
	FamilyTrip_traitStoryBosses = {
		Components.constant.table("bosses"),
	},
}

event.entitySchemaLoadNamedEnemy.add("loadPixie", "pixie", function(ev)
	ev.entity.FamilyTrip_autoAttackTarget = false
end)

event.entitySchemaLoadEntity.add("autoAttackTarget", "overrides", function(ev)
	if (ev.entity.enemy or ev.entity.crateLike) and ev.entity.FamilyTrip_autoAttackTarget == nil then
		ev.entity.FamilyTrip_autoAttackTarget = {}
	end
end)

event.entitySchemaLoadNamedEntity.add("tagBomb", "BombLit", function(ev)
	ev.entity.FamilyTrip_tagBomb = {}
end)

for _, name in ipairs { "ChestRed", "ChestBlack", "ChestPurple" } do
	event.entitySchemaLoadNamedEntity.add("tagChest" .. name, name, function(ev)
		ev.entity.FamilyTrip_tagChest = {}
	end)
end

event.tileSchemaBuild.add("tagDigTarget", "modify", function(tiles)
	for _, tile in pairs(tiles) do
		if tile.cracked and tiles[tile.cracked] then
			tiles[tile.cracked].FamilyTrip_digTarget = true
		end
	end
end)

event.entitySchemaLoadNamedEnemy.add("familySoulSubstitutionEnemy", "blademaster", function(ev)
	local t = ev.entity
	t.enemySubstitutions = t.enemySubstitutions or {}
	t = t.enemySubstitutions
	t.types = t.types or {}
	t = t.types
	t[FamilyTrip.EnemySubstitutions_Type] = t[FamilyTrip.EnemySubstitutions_Type] or { "Harpy", "Lich2", "Warlock2" }
end)

--- @diagnostic disable: assign-type-mismatch, missing-fields

local linkInventory = {
	slots = Utilities.listToSet {
		ItemSlot.Type.ACTION,
		ItemSlot.Type.BODY,
		ItemSlot.Type.BOMB,
		ItemSlot.Type.FEET,
		ItemSlot.Type.HEAD,
		ItemSlot.Type.HUD,
		ItemSlot.Type.MISC,
		ItemSlot.Type.RING,
		ItemSlot.Type.SHIELD,
		ItemSlot.Type.SHOVEL,
		ItemSlot.Type.SHRINE,
		ItemSlot.Type.SPELL,
		ItemSlot.Type.TORCH,
		ItemSlot.Type.WEAPON,
	}
}

CustomEntities.register {
	name = "FamilyTrip_SoulLinkFamily",

	FamilyTrip_soulLinkHeal = {},

	soulLink = {},
	soulLinkCurrency = {},
	soulLinkGrooveChain = {},
	soulLinkInventory = linkInventory,
	soulLinkKillCredit = { mask = Kill.Credit.mask(Kill.Credit.GROOVE_CHAIN, Kill.Credit.SPELL_COOLDOWN, Kill.Credit.REGENERATION, Kill.Credit.DAMAGE_COUNTDOWN, Kill.Credit.INVINCIBILITY, Kill.Credit.ITEM_DROP) },
	soulLinkSpellcasts = {},
}

CustomEntities.extend {
	name = "FamilyTrip_Potion",
	template = CustomEntities.template.item "misc_potion",
}

FamilyTrip.FamilySoulName = CustomEntities.register {
	name = "FamilyTrip_FamilySoul",

	CharacterSkins_excludeFromSelector = {},

	FamilyTrip_attackableOverrideInLobby = {},
	FamilyTrip_family = {
		initialMembers = {
			"FamilyTrip_Daughter",
			"FamilyTrip_Mother",
			"FamilyTrip_GrandMother",
			"FamilyTrip_Father",
		},
	},
	-- FamilyTrip_familyControlSpectator = {},
	FamilyTrip_familyDescent = {},
	FamilyTrip_familyFocusLeader = {},
	FamilyTrip_familyFragile = {},
	FamilyTrip_familyRhythmInheritMember = {},
	FamilyTrip_familyTeleport = {},
	FamilyTrip_familyThrowBomb = {},
	FamilyTrip_familyUseLeaderSpriteOnPlayerList = {},

	actionFilter = {},
	attackable = { flags = Attack.Flag.NONE },
	character = {},
	controllable = {},
	descent = {},
	descentAllowAscent = {},
	descentIntangibleOnCompletion = {},
	descentOverlay = {},
	descentSpectateOnCompletion = {},
	editorName = { name = "Soul of Family" },
	focusable = {},
	friendlyName = { name = "Family Trip" },
	gameObject = {},
	inventory = {},
	killable = {},
	playableCharacter = { lobbyOrder = -10000.1 },
	position = {},
	positionalSprite = { offsetX = -36, offsetY = -24 },
	proximityReveal = {},
	respawn = {},
	respawnAutomatically = {},
	rhythmIgnoredTemporarily = {},
	rhythmLeniency = {},
	rhythmLeniencyOnLevelStart = {},
	spectator = {},
	spectatorIntangible = {},
	sprite = { texture = "mods/FamilyTrip/family.png", width = 96, height = 62, scale = .5, visible = false },
	targetable = { active = true },
	team = { id = Team.Id.PLAYER },
	traitSubstituteSomeEnemies = {
		priority = .5,
		type = FamilyTrip.EnemySubstitutions_Type,
		zoneRatios = { .75, .75, .75, .75, .75 },
	},
	trappable = {},
	tween = {},
	visibility = {},

	descentExitLevel = false,
}

local function generateDirectionalActions(entity)
	local list = {
		Action.Direction.RIGHT,
		Action.Direction.UP_RIGHT,
		Action.Direction.DOWN_RIGHT,
		Action.Direction.UP,
		Action.Direction.DOWN,
		Action.Direction.UP_LEFT,
		Action.Direction.DOWN_LEFT,
		Action.Direction.LEFT,
	}

	local ignoreActions = entity.actionFilter and entity.actionFilter.ignoreActions or {
		[Action.Direction.UP_RIGHT] = true,
		[Action.Direction.UP_LEFT] = true,
		[Action.Direction.DOWN_LEFT] = true,
		[Action.Direction.DOWN_RIGHT] = true,
	}

	Utilities.removeIf(list, function(direction)
		return ignoreActions[direction]
	end)

	return list
end

function FamilyTrip.familyMemberModifier(entity)
	entity.FamilyTrip_familyMember = {}
	entity.FamilyTrip_familyMemberActivation = {}
	entity.FamilyTrip_familyMemberAttacker = {}
	entity.FamilyTrip_familyMemberAutoAct = { directions = generateDirectionalActions(entity) }
	entity.FamilyTrip_familyMemberChestOpener = {}
	entity.FamilyTrip_familyMemberDeathKillFamilyFragile = {}
	entity.FamilyTrip_familyMemberDigger = {}
	entity.FamilyTrip_familyMemberGrooveChainIdleImmunity = {}
	entity.FamilyTrip_familyMemberMovable = {}
	entity.FamilyTrip_familyMemberMover = {}
	entity.FamilyTrip_familyMemberPersistent = {}
	if entity.health then
		entity.FamilyTrip_familyMemberProtectWeaker = {}
	end
	entity.FamilyTrip_familyMemberRefactorBeatBar = {}
	if entity.invincibility and entity.invincibilityOnHit then
		entity.FamilyTrip_familyMemberShareInvincibilityOnDamage = {}
	end

	if entity.collisionCheckOnMove then
		entity.collisionCheckOnMove.mask = Collision.Type.unmask(entity.collisionCheckOnMove.mask or 0, Collision.Type.PLAYER)
	end
	if entity.collisionCheckOnTeleport then
		entity.collisionCheckOnTeleport.mask = Collision.Type.unmask(entity.collisionCheckOnTeleport.mask or 0, Collision.Type.PLAYER)
	end
	entity.descentSpectateOnCompletion = {}
	if not entity.setFacingOnMove then
		entity.FamilyTrip_setFacingOnMove = {}
	end
	entity.songEndCast = { spell = "SpellcastSongEnd" }

	entity.collisionCheckPlayerSetting = false
	entity.controllable = false
	entity.enemyBans = false
	entity.healthBarHideByPlayerSetting = false
	entity.playableCharacter = false
	--- @diagnostic disable-next-line: inject-field
	entity.playableCharacterDLC = false
	entity.traitAddSarcophagus = false
	entity.traitAddSpiders = false
	entity.traitInnatePeace = false
	entity.traitSubstituteEnemies = false
	entity.traitSubstituteSomeEnemies = false
	entity.traitExtraEnemies = false
	entity.traitExtraEnemiesZ1Z2Z5 = false
	entity.traitExtraMiniboss = false
	entity.traitZone4NoMonkeys = false
	entity.traitZone4NoSpiders = false
end

CustomEntities.extend {
	name = "FamilyTrip_Daughter",
	template = CustomEntities.template.player(0),
	modifier = FamilyTrip.familyMemberModifier,
	components = {
		{
			sprite = { texture = "ext/entities/player1_armor_body.png" },
		},
		{
			sprite = { texture = "ext/entities/player1_heads.png" },
		},
	},
}

CustomEntities.extend {
	name = "FamilyTrip_Father",
	template = CustomEntities.template.player(3),
	modifier = FamilyTrip.familyMemberModifier,
	components = {
		{
			initialInventory = { items = { "ArmorPlatemailDorian", "FeetBootsLeaping", "Pickaxe", "RingMight" } },
			inventoryBannedItemTypes = { types = { Pickaxe = ItemBan.Type.LOCK, RingMight = ItemBan.Type.LOCK } },
			sprite = { texture = "ext/entities/char3_armor_body.png", width = 33, height = 32 },
		},
		{
			sprite = { texture = "ext/entities/char3_heads.png", width = 33, height = 32 },
		},
	},
}

CustomEntities.extend {
	name = "FamilyTrip_GrandMother",
	template = CustomEntities.template.player(2),
	modifier = FamilyTrip.familyMemberModifier,
	components = {
		{
			initialInventory = { items = { "WeaponDagger", "FamilyTrip_Potion" } },
			inventoryBannedItemTypes = { types = { FamilyTrip_Potion = ItemBan.Type.FULL } },
			sprite = { texture = "ext/entities/char2_armor_body.png" },
		},
		{
			sprite = { texture = "ext/entities/char2_heads.png" },
		},
	},
}

CustomEntities.extend {
	name = "FamilyTrip_Mother",
	template = CustomEntities.template.player(1),
	modifier = FamilyTrip.familyMemberModifier,
	components = {
		{
			FamilyTrip_familyMemberAttacker = false,

			initialInventory = { items = { "WeaponGoldenLute" } },
			inventoryBannedItemSlots = { slots = { [ItemSlot.Type.WEAPON] = ItemBan.Type.FULL } },
			sprite = { texture = "ext/entities/char1_armor_body.png" },
		},
		{
			sprite = { texture = "ext/entities/char1_heads.png" },
		},
	},
}

for index, name in ipairs {
	"Cadence",
	"Melody",
	"Aria",
	"Dorian",
	"Eli",
	"Monk",
	"Dove",
	"Coda",
	"Bolt",
	"Bard",
	"Nocturna",
	"Diamond",
	"Mary",
	"Tempo",
	"Reaper",
} do
	CustomEntities.extend {
		name = "FamilyTrip_" .. name,
		template = CustomEntities.template.player(index - 1),
		modifier = FamilyTrip.familyMemberModifier,
	}
end

SettingCustomFamilyMembers = Settings.entitySchema.string {
	id = "customFamilyMembers",
	name = "Custom family members",
	order = 0,
	default = "",
}

event.entitySchemaLoadNamedEntity.add("customFamilyMembers", "FamilyTrip_FamilySoul", function(ev)
	if ev.entity.FamilyTrip_family and SettingCustomFamilyMembers ~= "" then
		local members = {}

		for _, name in ipairs(StringUtilities.split(SettingCustomFamilyMembers, ",")) do
			members[#members + 1] = ("FamilyTrip_" .. name:match "^%s*(.-)%s*$")
		end

		ev.entity.FamilyTrip_family.initialMembers = members
		-- elseif ev.entity.FamilyTrip_traitStoryBosses == nil then
		-- 	ev.entity.FamilyTrip_traitStoryBosses = {
		-- 		bosses = {
		-- 			Boss.Type.DEAD_RINGER,
		-- 			Boss.Type.NECRODANCER,
		-- 			Boss.Type.NECRODANCER_2,
		-- 			Boss.Type.GOLDEN_LUTE,
		-- 		},
		-- 	}
	end
end)

--- @diagnostic enable: assign-type-mismatch, missing-fields

local iterateFamilyMembers
do
	local familyMemberIteratorIndex
	local familyMemberIteratorMembers
	local familyMemberIteratorIncludeDead

	local function familyMemberIterator()
		while true do
			familyMemberIteratorIndex = familyMemberIteratorIndex + 1
			local member = familyMemberIteratorMembers[familyMemberIteratorIndex]
			if not member then
				return
			end

			local memberEntity = ECS.getEntityByID(member)
			if memberEntity and memberEntity.FamilyTrip_familyMember
				and (familyMemberIteratorIncludeDead or Character.isAlive(memberEntity))
			then
				return familyMemberIteratorIndex, memberEntity
			end
		end
	end

	--- @param family Component.FamilyTrip_family
	--- @return function
	iterateFamilyMembers = function(family, includeDead)
		familyMemberIteratorIndex = 0
		familyMemberIteratorMembers = family.members
		familyMemberIteratorIncludeDead = includeDead
		return familyMemberIterator
	end
end

--- @param memberEntity Entity @A live and family member character entity
--- @return boolean
function FamilyTrip.familyMemberCanBeLeader(memberEntity)
	if memberEntity.descent and memberEntity.descent.active then
		return false
	end

	return true
end

local FamilyLeader_First = 1
local FamilyLeader_Sequential = 2
local FamilyLeader_Random = 3

SettingFamilyLeader = Settings.shared.choice {
	id = "familyLeader",
	name = "Family leader",
	order = 10,
	default = FamilyLeader_First,
	choices = {
		{ name = "First",      value = FamilyLeader_First },
		{ name = "Sequential", value = FamilyLeader_Sequential },
		{ name = "Random",     value = FamilyLeader_Random },
	},
}

local function getFamilyLeaderWithOffset(family, offset)
	local members = family.members
	local len = #members
	for i = 1, len do
		local memberEntity = ECS.getEntityByID(members[(i + offset) % len + 1])
		if memberEntity and Character.isAlive(memberEntity) and FamilyTrip.familyMemberCanBeLeader(memberEntity) then
			return memberEntity
		end
	end
end

--- @param family Component.FamilyTrip_family
--- @return Entity?
function FamilyTrip.getFamilyLeader(family)
	local option = SettingFamilyLeader
	if option == FamilyLeader_First then
		for _, memberEntity in iterateFamilyMembers(family) do
			if FamilyTrip.familyMemberCanBeLeader(memberEntity) then
				return memberEntity
			end
		end
	elseif option == FamilyLeader_Sequential then
		return getFamilyLeaderWithOffset(family, CurrentLevel.getNumber() - 2)
	elseif option == FamilyLeader_Random then
		return getFamilyLeaderWithOffset(family, bit.bxor(CurrentLevel.getSeed(), CurrentLevel.getNumber()))
	end
end

function FamilyTrip.getFamilyMembers(family, includeDead)
	local entities = Utilities.newTable(#family.members, 0)

	for _, memberEntity in iterateFamilyMembers(family, includeDead) do
		entities[#entities + 1] = memberEntity
	end

	return entities
end

--- @param memberEntity Entity
--- @return boolean? isLeader
--- @return Entity? familyEntity
function FamilyTrip.isFamilyLeader(memberEntity)
	if not memberEntity.FamilyTrip_familyMember then
		return nil
	end

	local familyEntity = ECS.getEntityByID(memberEntity.FamilyTrip_familyMember.family)
	local family = familyEntity and familyEntity.FamilyTrip_family
	if not family then
		return false, familyEntity
	end

	return FamilyTrip.getFamilyLeader(family) == memberEntity, familyEntity
end

function FamilyTrip.performFamilyMemberAction(entity, actionID)
	if not entity.FamilyTrip_familyMember then
		return
	end

	local familyEntity = ECS.getEntityByID(entity.FamilyTrip_familyMember.family)
	if not (familyEntity and familyEntity.controllable) then
		return
	end

	local ev = {
		entity = entity,
		action = actionID,
		flags = Ability.getActionFlags(actionID),
		playerID = familyEntity.controllable.playerID,
	}
	ObjectEvents.fire("checkAbility", entity, ev)

	local parameters = Character.performAction(entity, ev.action)
	Character.handleActionResult(entity, parameters)
	return parameters.result
end

function FamilyTrip.hasFamilyMemberAt(familyArg, x, y, excludeEntityID)
	local familyID
	if type(familyArg) == "number" then
		familyID = familyArg
	elseif familyArg.FamilyTrip_family then
		familyID = familyArg.FamilyTrip_family
	elseif familyArg.FamilyTrip_familyMember then
		local familyEntity = ECS.getEntityByID(familyArg.FamilyTrip_familyMember.family)
		familyID = familyEntity and familyEntity.FamilyTrip_family and familyEntity.id
	end

	if familyID then
		for _, memberEntity in ObjectMap.entitiesWithComponent(x, y, "FamilyTrip_familyMember") do
			if memberEntity.id ~= excludeEntityID and memberEntity.FamilyTrip_familyMember.family == familyID
				and memberEntity.gameObject.tangible
				and not (memberEntity.descent and memberEntity.descent.active)
			then
				return true
			end
		end

		return false
	end
end

SettingRandFamilyOrder = Settings.shared.bool {
	id = "randFamilyOrder",
	name = "Randomize member orders",
	order = 20,
	default = false,
}

FamilyTrip.RNGChannel_RandomizeOrder = RNG.Channel.extend "FamilyTrip_randomizeFamilyMemberOrder"

event.gameStateLevel.add("randomizeFamilyMembersOrders", "multiCharacter", function()
	if SettingRandFamilyOrder then
		for familyEntity in ECS.entitiesWithComponents { "FamilyTrip_family" } do
			RNG.shuffle(familyEntity.FamilyTrip_family.members, FamilyTrip.RNGChannel_RandomizeOrder)
		end
	end
end)

--- Prevent potential stack overflow errors.
local spawnFamilyMembersRecurseDetector

local function spawnFamilyMembers(familyEntity, x, y)
	spawnFamilyMembersRecurseDetector = spawnFamilyMembersRecurseDetector or {}
	if spawnFamilyMembersRecurseDetector[familyEntity.name] then
		return
	else
		spawnFamilyMembersRecurseDetector[familyEntity.name] = true
	end

	local family = assert(familyEntity.FamilyTrip_family)
	local entities = {}

	for _, entityType in ipairs(family.initialMembers) do
		--- @diagnostic disable-next-line: missing-fields
		local success, entity = pcall(Object.spawn, entityType, x, y, {
			FamilyTrip_familyMember = { family = familyEntity.id },
		})

		if success then
			entities[#entities + 1] = entity
			family.members[#family.members + 1] = entity.id
		end
	end

	spawnFamilyMembersRecurseDetector = nil

	if #entities > 1 then
		if family.initialSoulLink and ECS.isValidEntityType(family.initialSoulLink) then
			local soulLinkEntity = SoulLink.create(family.initialSoulLink)
			SoulLink.attach(soulLinkEntity, familyEntity)
			for _, entity in ipairs(entities) do
				SoulLink.attach(soulLinkEntity, entity)
			end
		end
	end
end

event.objectSpawn.add("familyInitialize", {
	filter = "FamilyTrip_family",
	order = "spawnExtras",
}, function(ev)
	spawnFamilyMembers(ev.entity, ev.x, ev.y)
end)

event.objectPostConvert.add("familyInitialize", {
	filter = { "FamilyTrip_family", "position" },
	order = "spawnExtras",
}, function(ev)
	spawnFamilyMembers(ev.entity, ev.entity.position.x, ev.entity.position.y)

	if ev.entity.FamilyTrip_family.invisibleSprite and ev.entity.sprite then
		ev.entity.sprite.visible = false
	end
end)

local function despawnFamilyMembers(familyEntity)
	for _, entity in ipairs(FamilyTrip.getFamilyMembers(familyEntity.FamilyTrip_family, true)) do
		Object.delete(entity)
	end
end

event.objectDespawn.add("familyUninitialize", {
	filter = "FamilyTrip_family",
	order = "despawnExtras",
}, function(ev)
	despawnFamilyMembers(ev.entity)
end)

event.objectPreConvert.add("familyUninitialize", {
	filter = "FamilyTrip_family",
	order = "despawnExtras",
}, function(ev)
	despawnFamilyMembers(ev.entity)

	if ev.entity.FamilyTrip_family.invisibleSprite and ev.entity.sprite then
		local entity = ECS.getEntityPrototype(ev.newType)
		if entity and entity.sprite then
			ev.entity.sprite.visible = entity.sprite.visible
		end
	end
end)

local function handleFamilyEntityAction(ev)
	if ev.result then
		return
	end

	local leaderEntity = FamilyTrip.getFamilyLeader(ev.entity.FamilyTrip_family)
	if not leaderEntity then
		return
	end

	ev.FamilyTrip_leader = leaderEntity

	-- A very silly fix of sliding issue.
	if leaderEntity.slideIgnoreActions
		and leaderEntity.slide and leaderEntity.slide.direction ~= Action.Direction.NONE
		and leaderEntity.slideIgnoreActions.actions[ev.direction]
	then
		ev.result = FamilyTrip.performFamilyMemberAction(leaderEntity, Action.Special.INVALID)
	else
		ev.result = FamilyTrip.performFamilyMemberAction(leaderEntity, ev.action)
	end
end

event.objectDirection.add("familyDirection", {
	filter = "FamilyTrip_family",
	order = "ai",
}, handleFamilyEntityAction)

event.objectSpecialAction.add("familyDirection", {
	filter = "FamilyTrip_family",
	order = "ai",
}, handleFamilyEntityAction)

local function newSpectatorHandler(eventTypeName)
	return function(ev)
		if not ev.suppressed then
			for _, memberEntity in ipairs(FamilyTrip.getFamilyMembers(ev.entity.FamilyTrip_family, true)) do
				local evClone = Utilities.deepCopy(ev)
				evClone.playerID = 0
				ObjectEvents.fire(eventTypeName, memberEntity, evClone)
			end
		end
	end
end

event.objectSpectate.add("familySpectateMembers", {
	filter = "FamilyTrip_family",
	order = "spectator",
}, newSpectatorHandler "spectate")

event.objectUnspectate.add("familyUnspectateMembers", {
	filter = "FamilyTrip_family",
	order = "spectator",
}, newSpectatorHandler "unspectate")

event.objectUpdateRhythm.add("familyRhythmInheritMember", {
	filter = "FamilyTrip_familyRhythmInheritMember",
	order = "inherit",
}, function(ev)
	local leaderEntity = FamilyTrip.getFamilyLeader(ev.entity.FamilyTrip_family)
	if leaderEntity then
		ObjectEvents.fire("updateRhythm", leaderEntity, ev)
	end
end)

event.objectSpecialAction.add("familyThrowBomb", {
	filter = "FamilyTrip_familyThrowBomb",
	order = "moveOverride",
}, function(ev)
	if ev.result ~= Action.Result.SPELL then
		return
	end

	for _, entity in ObjectMap.entitiesWithComponent(ev.x, ev.y, "FamilyTrip_tagBomb") do
		--- @type boolean | Action.Direction | integer
		local direction = true

		local casterEntity = entity.spawnable and ECS.getEntityByID(entity.spawnable.caster)
		if ev.entity.FamilyTrip_familyThrowBomb.mustBeLeader then
			if not (casterEntity and FamilyTrip.isFamilyLeader(casterEntity)) then
				direction = false
			end
		end

		if direction then
			if casterEntity and casterEntity.facingDirection then
				direction = casterEntity.facingDirection.direction
			elseif entity.facingDirection then
				direction = entity.facingDirection.direction
			else
				direction = Action.Direction.NONE
			end
		end

		if direction then
			--- @diagnostic disable-next-line: param-type-mismatch
			Move.direction(entity, direction, ev.entity.FamilyTrip_familyThrowBomb.pushDistance, ev.entity.FamilyTrip_familyThrowBomb.pushType)

			break
		end
	end
end)

TeleportFamilyMemberLater = Delay.new(function(entity, familyID)
	local familyEntity = ECS.getEntityByID(tonumber(familyID) or 0)
	local teleport = familyEntity and familyEntity.FamilyTrip_familyTeleport
	if teleport then
		Move.absolute(entity, familyEntity.position.x, familyEntity.position.y, teleport.moveType)

		if teleport.trappableImmune and entity.trappable then
			entity.trappable.immuneTurnID = Turn.getCurrentTurnID()
		end
	end
end)

event.objectMove.add("familyTeleportMoveMembers", {
	filter = "FamilyTrip_familyTeleport",
	order = "spell",
	sequence = 100,
}, function(ev)
	if Move.Flag.check(ev.moveType, Move.Flag.CONTINUOUS) or Move.Flag.check(ev.moveType, Move.Flag.FORCED_MOVE) then
		return
	end

	for _, memberEntity in ipairs(FamilyTrip.getFamilyMembers(ev.entity.FamilyTrip_family, true)) do
		TeleportFamilyMemberLater(memberEntity, ev.entity.id)
	end
end)

local familyMemberAutoActSelectorFire = EntitySelector.new(event.FamilyTrip_familyMemberAutoAct, {
	"attack",
	"dig",
	"reload",
	"chest",
}).fire

event.objectMoveResult.add("familyMemberAutoActs", {
	filter = "FamilyTrip_family",
	order = "ai",
}, function(ev)
	-- local leader = ev.FamilyTrip_leader or FamilyTrip.getFamilyLeader(ev.entity.FamilyTrip_family)

	-- for _, memberEntity in ipairs(FamilyTrip.getFamilyMembers(ev.entity.FamilyTrip_family)) do
	-- 	if memberEntity ~= leader and memberEntity.FamilyTrip_familyMemberAutoAct then
	-- 		local result

	-- 		if memberEntity.character.canAct and not (memberEntity.hasMoved and memberEntity.hasMoved.value) then
	-- 			local ev1 = {
	-- 				entity = memberEntity,
	-- 			}
	-- 			familyMemberAutoActSelectorFire(ev1, memberEntity.name)
	-- 			result = ev1.result
	-- 		end

	-- 		if not result then
	-- 			FamilyTrip.performFamilyMemberAction(memberEntity, Action.Special.IDLE)
	-- 		end
	-- 	end
	-- end
end)

local function handleFamilyMemberAutoActs(familyEntity)
	local leader = FamilyTrip.getFamilyLeader(familyEntity.FamilyTrip_family)

	for _, memberEntity in ipairs(FamilyTrip.getFamilyMembers(familyEntity.FamilyTrip_family)) do
		if memberEntity ~= leader and memberEntity.FamilyTrip_familyMemberAutoAct then
			local result

			if memberEntity.character.canAct and not memberEntity.character.hasActed and not (memberEntity.hasMoved and memberEntity.hasMoved.value) then
				local ev1 = {
					entity = memberEntity,
				}
				familyMemberAutoActSelectorFire(ev1, memberEntity.name)
				result = ev1.result
			end

			if not result or result < 0 then
				FamilyTrip.performFamilyMemberAction(memberEntity, Action.Special.IDLE)
			end
		end
	end
end

local componentsFamily = { "FamilyTrip_family" }

event.turn.add("familyMemberAutoActs", {
	order = "playerActions",
	sequence = 4,
}, function()
	for familyEntity in ECS.entitiesWithComponents(componentsFamily) do
		if familyEntity.gameObject.active then
			handleFamilyMemberAutoActs(familyEntity)
		end
	end
end)

local componentsFamilyMemberAutoActHasMoved = { "FamilyTrip_familyMemberAutoAct", "hasMoved" }

event.turn.add("familyMemberAutoActsResetHasMoved", "nextTurnEffect", function()
	for entity in ECS.entitiesWithComponents(componentsFamilyMemberAutoActHasMoved) do
		entity.hasMoved.value = false
	end
end)

event.objectRespawn.add("familyRespawnMembers", {
	filter = "FamilyTrip_family",
	order = "runSummary",
	sequence = 1,
}, function(ev)
	for _, memberEntity in ipairs(FamilyTrip.getFamilyMembers(ev.entity.FamilyTrip_family, true)) do
		if memberEntity.respawn and memberEntity.respawn.pending then
			Respawn.revive(memberEntity, Utilities.deepCopy(ev))
		end
	end
end)

event.objectRespawn.add("familyFragileRespawn", {
	filter = "FamilyTrip_familyFragile",
	order = "killableFlag",
}, function(ev)
	ev.entity.FamilyTrip_familyFragile.broken = false
end)

event.runScoreUpdate.add("familyCollectCurrency", "currency", function(ev)
	for _, familyEntity in ipairs(ev.players) do
		if familyEntity.FamilyTrip_family then
			local score = 0
			local count = 0

			for _, memberEntity in iterateFamilyMembers(familyEntity.FamilyTrip_family, true) do
				score = score + Currency.get(memberEntity, Currency.Type.GOLD)
				count = count + 1
			end

			if count > 0 then
				ev.score = ev.score + score / count
			end
		end
	end
end)

--- @param func function
local function foreachFamilyMemberAutoActDirection(ev, func, ...)
	if ev.result then
		return
	end

	local entity = ev.entity
	local rotation = entity.facingDirection and entity.facingDirection.direction or Action.Rotation.IDENTITY

	for _, direction in ipairs(ev.entity.FamilyTrip_familyMemberAutoAct.directions) do
		--- @diagnostic disable-next-line: param-type-mismatch
		direction = Action.rotateDirection(direction, rotation)
		local act = func(direction, entity, ...)
		if act then
			ev.result = FamilyTrip.performFamilyMemberAction(entity, direction)

			break
		end
	end
end

local function hasAutoAttackTarget(targets)
	for _, target in ipairs(targets) do
		if target.victim.FamilyTrip_autoAttackTarget then
			if not target.victim.shield then
				return true
			end

			if target.damage >= target.victim.shield.bypassDamage or Damage.Flag.check(target.type, target.victim.shield.bypassFlags) then
				return true
			end
		end
	end

	return false
end

local function autoActTryAttack(direction, entity)
	local ev = {
		--- @diagnostic disable-next-line: param-type-mismatch
		direction = direction
	}
	ObjectEvents.fire("checkAttack", entity, ev)

	if ev.result and ev.result.success and hasAutoAttackTarget(ev.result.targets) then
		local crossbow = AffectorItem.getItem(entity, "weaponReloadable")
		if crossbow then
			-- idk why but for reloadable weapons it has to +1 otherwise some weird behaviors happens XD
			crossbow.weaponReloadable.ammo = crossbow.weaponReloadable.ammo + 1
		end

		return true
	end
end

event.FamilyTrip_familyMemberAutoAct.add("attack", {
	filter = "FamilyTrip_familyMemberAttacker",
	order = "attack",
}, function(ev)
	foreachFamilyMemberAutoActDirection(ev, autoActTryAttack)
end)

local function autoActTryDig(direction, entity)
	local x, y = Action.getMovementOffset(direction)
	x = entity.position.x + x
	y = entity.position.y + y

	local tileInfo = Tile.getInfo(x, y)
	if not (tileInfo.FamilyTrip_digTarget and tileInfo.digResistance) then
		return
	end

	local parameters = {
		x = x,
		y = y,
		tileInfo = tileInfo,
		resistance = tileInfo.digResistance,
		flags = {},
	}
	ObjectEvents.fire("computeDigStrength", entity, parameters)
	return parameters.strength >= tileInfo.digResistance
end

event.FamilyTrip_familyMemberAutoAct.add("dig", {
	filter = "FamilyTrip_familyMemberDigger",
	order = "dig",
}, function(ev)
	foreachFamilyMemberAutoActDirection(ev, autoActTryDig)
end)

event.FamilyTrip_familyMemberAutoAct.add("reloadWeapon", {
	filter = "FamilyTrip_familyMemberAttacker",
	order = "reload",
}, function(ev)
	if not ev.result then
		local weapon = AffectorItem.getItem(ev.entity, "weaponReloadable")
		if weapon and weapon.weaponReloadable.ammo < weapon.weaponReloadable.maximumAmmo then
			ev.result = FamilyTrip.performFamilyMemberAction(ev.entity, Action.Special.THROW)
		end
	end
end)

local function autoActTryOpenChest(direction, entity)
	local dx, dy = Action.getMovementOffset(direction)
	return not not ObjectMap.firstWithComponent(entity.position.x + dx, entity.position.y + dy, "FamilyTrip_tagChest")
end

event.FamilyTrip_familyMemberAutoAct.add("openChest", {
	filter = "FamilyTrip_familyMemberChestOpener",
	order = "chest",
}, function(ev)
	foreachFamilyMemberAutoActDirection(ev, autoActTryOpenChest)
end)

event.objectDescentEnd.add("familyEnableSpectatorMode", {
	filter = "FamilyTrip_familyControlSpectator",
	order = "spectator",
}, function(ev)
	ev.entity.spectator.active = true
end)

local componentsFamilyDescent = { "FamilyTrip_familyDescent" }

local function updateDescentFamilies(ev)
	local forceUpdate = ev and type(ev.level) == "number"

	for familyEntity in ECS.entitiesWithComponents(componentsFamilyDescent) do
		if forceUpdate or familyEntity.gameObject.tangible then
			local shouldDescent = true

			--- @param memberEntity Entity
			for _, memberEntity in iterateFamilyMembers(familyEntity.FamilyTrip_family, true) do
				if memberEntity.descent and not memberEntity.descent.active then
					shouldDescent = false

					break
				end
			end

			if familyEntity.descent.active then
				if not shouldDescent then
					Descent.ascend(familyEntity)
				end
			else
				if shouldDescent then
					Descent.perform(familyEntity, Descent.Type.STAIRS)
				end
			end
		end
	end
end

event.turn.add("updateDescentFamilies", "descent", updateDescentFamilies)

event.gameStateLevel.add("restoreDescendedEntities", {
	order = "descent",
	sequence = 1,
}, updateDescentFamilies)

event.gameStateLevel.add("placeFamilyMembers", {
	order = "placePlayers",
	sequence = 1,
}, function()
	for entity in ECS.entitiesWithComponents { "FamilyTrip_familyMember" } do
		local familyEntity = ECS.getEntityByID(entity.FamilyTrip_familyMember.family)
		if familyEntity and familyEntity.position then
			Move.absolute(entity, familyEntity.position.x, familyEntity.position.y)
		end
	end
end)

event.objectDescentArrive.add("familyAscentMembers", {
	filter = "FamilyTrip_familyDescent",
	order = "follower"
}, function(ev)
	if ev.ascent then
		for _, memberEntity in iterateFamilyMembers(ev.entity.FamilyTrip_family, true) do
			Descent.ascend(memberEntity)
		end
	end
end)

event.turn.add("handleSongEnd", "songEnd", function(ev)
	local songEndActions = ev.actionMap[Action.System.SONG_ENDED]
	if not songEndActions then
		return
	end

	for _, actionData in ipairs(songEndActions) do
		local playerEntity = Player.getPlayerEntity(actionData.playerID)
		if playerEntity and playerEntity.FamilyTrip_family then
			for _, memberEntity in ipairs(FamilyTrip.getFamilyMembers(playerEntity.FamilyTrip_family)) do
				ObjectEvents.fire("songEnd", memberEntity)
			end
		end
	end
end)

event.updateFocusedEntities.add("focusFamilyMembers", "localDads", function(ev)
	for i = 1, #ev.entities do
		local entity = ev.entities[i]

		if entity.FamilyTrip_familyFocusLeader then
			local leaderEntity = FamilyTrip.getFamilyLeader(entity.FamilyTrip_family)
			if leaderEntity and leaderEntity.focusable and leaderEntity.gameObject and leaderEntity.gameObject.tangible then
				leaderEntity.focusable.flags = entity.focusable.flags
				table.insert(ev.entities, i, leaderEntity)
				i = i + 1

				if entity.focusable then
					entity.focusable.flags = Focus.Flag.mask(Focus.Flag.LOCALLY_KNOWN_PLAYER_NAME, Focus.Flag.BEAT_BARS)
				end
			end
		end
	end
end)

local killLater = Delay.register("killLater", function(entity, params)
	if entity.killable and not entity.killable.dead then
		Object.kill(entity, nil, params.killerName, params.damageType, params.silent)
	end
end)

event.objectDeath.add("familyMemberKillFragileFamily", {
	filter = "FamilyTrip_familyMemberDeathKillFamilyFragile",
	order = "boss",
}, function(ev)
	local familyEntity = ECS.getEntityByID(ev.entity.FamilyTrip_familyMember.family)
	local fragile = familyEntity and familyEntity.FamilyTrip_familyFragile
	if not (fragile and not fragile.broken) then --- @cast familyEntity Entity
		return
	end

	local killLaterArgs = {
		killerName = ev.killerName or Kill.getKillerName(ev.killer),
		damageType = ev.damageType,
		silent = ev.silent,
	}

	local time = 0

	if familyEntity.FamilyTrip_family then
		for _, memberEntity in iterateFamilyMembers(familyEntity.FamilyTrip_family, true) do
			local delayTime
			if memberEntity.descent and not (memberEntity.descent.active or memberEntity.descent.complete) then
				time = time + fragile.killDelay
				delayTime = time
			else
				delayTime = 0
			end

			killLater(memberEntity, delayTime, killLaterArgs)
		end
	end

	killLater(familyEntity, time, killLaterArgs)
end)

local componentsFamilyMemberActivation = { "FamilyTrip_familyMemberActivation" }
local componentsFamilyMemberMovable = { "FamilyTrip_familyMemberMovable" }

event.updateActivation.add("familyMemberActivations", {
	order = "defaultActability",
	sequence = 1,
}, function()
	for entity in ECS.entitiesWithComponents(componentsFamilyMemberActivation) do
		local familyEntity = ECS.getEntityByID(entity.FamilyTrip_familyMember.family)
		if familyEntity then
			entity.gameObject.active = familyEntity.gameObject.active

			if familyEntity.character then
				entity.character.canAct = familyEntity.character.canAct
			end
		end
	end

	for entity in ECS.entitiesWithComponents(componentsFamilyMemberMovable) do
		entity.FamilyTrip_familyMemberMovable.value = true
	end
end)

local zeroPosition = { x = 0, y = 0 }

function FamilyTrip.getFamilyDistanceValue(targetEntity, entities)
	local value = 0

	local targetPosition = targetEntity.position or zeroPosition
	for _, entity in ipairs(entities) do
		if targetEntity ~= entity then
			local position = entity.position or zeroPosition
			value = value + Utilities_squareDistance(targetPosition.x - position.x, targetPosition.y - position.y)
		end
	end

	return value
end

local sortFamilyMembersByLeaderPosition
do
	local memberEntitiesComparerLeaderX
	local memberEntitiesComparerLeaderY
	--- @type Entity[]?
	local memberEntitiesComparerEntities

	local function memberEntitiesComparer(l, r)
		local lp = l.position
		local rp = r.position
		local ld = Utilities_squareDistance(lp.x - memberEntitiesComparerLeaderX, lp.y - memberEntitiesComparerLeaderY)
		local rd = Utilities_squareDistance(rp.x - memberEntitiesComparerLeaderX, rp.y - memberEntitiesComparerLeaderY)
		if ld ~= rd then
			return ld < rd
		end

		ld = FamilyTrip.getFamilyDistanceValue(l, memberEntitiesComparerEntities)
		rd = FamilyTrip.getFamilyDistanceValue(r, memberEntitiesComparerEntities)
		if ld ~= rd then
			return ld < rd
		end

		return l.id < r.id
	end

	sortFamilyMembersByLeaderPosition = function(memberEntities, x, y)
		memberEntitiesComparerLeaderX = x
		memberEntitiesComparerLeaderY = y
		memberEntitiesComparerEntities = memberEntities
		table.sort(memberEntitiesComparerEntities, memberEntitiesComparer)
		memberEntitiesComparerEntities = nil
	end
end

event.objectMove.add("familyLeaderMoveFamily", {
	filter = "FamilyTrip_familyMember",
	order = "spell",
}, function(ev)
	local isLeader, familyEntity = FamilyTrip.isFamilyLeader(ev.entity)
	if isLeader and familyEntity then
		Move.absolute(familyEntity, ev.entity.position.x, ev.entity.position.y, Move.Flag.unmask(ev.moveType, familyEntity.FamilyTrip_family.moveFlagUnmask))
	end
end)

for i, component in ipairs {
	"interactableSelectCharacter",
	"interactableToggleExtraMode",
} do
	event.objectInteract.add("familyMemberLetFamilyActivate" .. i, {
		filter = component,
		order = "activate",
	}, function(ev)
		if not ev.result and ev.interactor.FamilyTrip_familyMember then
			local familyEntity = ECS.getEntityByID(ev.interactor.FamilyTrip_familyMember.family)
			if familyEntity then
				ev.result = Interaction.perform(familyEntity, ev.entity)
			end
		end
	end)
end

event.objectMove.add("familyMemberMover", {
	filter = "FamilyTrip_familyMemberMover",
	order = "followers",
}, function(ev)
	local entity = ev.entity
	local familyEntity = ECS.getEntityByID(entity.FamilyTrip_familyMember.family)
	local family = familyEntity and familyEntity.FamilyTrip_family
	if not (family and #family.members > 1) then
		return
	end --- @cast familyEntity Entity

	if not Move.Flag.check(ev.moveType, Move.Flag.CONTINUOUS) then
		return
	end

	local leaderEntity = FamilyTrip.getFamilyLeader(family)
	if entity == leaderEntity and FamilyTrip.hasFamilyMemberAt(familyEntity.id, ev.x, ev.y, entity.id) then
		return
	end

	if entity.FamilyTrip_familyMemberMovable then
		entity.FamilyTrip_familyMemberMovable.value = false
	end

	local memberEntities = Utilities.newTable(#family.members, 0)
	for _, memberEntity in iterateFamilyMembers(family) do
		if memberEntity ~= entity and memberEntity ~= leaderEntity
			and memberEntity.FamilyTrip_familyMemberMovable and memberEntity.FamilyTrip_familyMemberMovable.value
		then
			memberEntities[#memberEntities + 1] = memberEntity
		end
	end

	sortFamilyMembersByLeaderPosition(memberEntities, Utilities.lerp(ev.prevX, ev.x, -.25), Utilities.lerp(ev.prevY, ev.y, -.25))

	for _, memberEntity in ipairs(memberEntities) do
		memberEntity.FamilyTrip_familyMemberMovable.value = false
		if Move.absolute(memberEntity, ev.prevX, ev.prevY, memberEntity.movable.moveType) then
			break
		end
	end
end)

event.objectCheckPersistence.add("familyMemberPersistent", {
	filter = "FamilyTrip_familyMemberPersistent",
	order = "controllable",
}, function(ev)
	if ECS.entityExists(ev.entity.FamilyTrip_familyMember.family) then
		ev.persist = true
	end
end)

local function checkArmorCondition(comp, ev)
	return not Damage.Flag.check(ev.type, comp.bypassFlags) and (comp.bypassDamage < 0 or ev.damage < comp.bypassDamage)
end

local function protectorPriority(entity, ev)
	if entity.shield and checkArmorCondition(entity.shield, ev) then
		return math.huge
	end

	local value = entity.health.health

	if entity.cursedHealth then
		value = value + entity.cursedHealth.health
	end

	if entity.health.health > 1 then
		local potion = AffectorItem.getItem(entity, "itemTagPotion")
		if potion then
			value = value + entity.health.maxHealth
		end
	end

	if entity.health.health > 1 then
		for item in ECS.entitiesWithComponents { "item", "itemArmor" } do
			if item.item.holder == entity.id and checkArmorCondition(item.itemArmor, ev) then
				value = value + item.itemArmor.damageReduction
			end
		end

		for item in ECS.entitiesWithComponents { "item", "itemArmorLate" } do
			if item.item.holder == entity.id and checkArmorCondition(item.itemArmorLate, ev) then
				value = value + item.itemArmorLate.damageReduction
			end
		end
	end

	return value
end

event.objectTakeDamage.add("familyMemberProtectWeaker", {
	filter = "FamilyTrip_familyMemberProtectWeaker",
	order = "immunity"
}, function(ev)
	if ev.suppressed then
		return
	end

	local family = ev.entity.FamilyTrip_familyMember.family
	local members
	for _, entity in ObjectMap.entitiesWithComponent(ev.entity.position.x, ev.entity.position.y, "FamilyTrip_familyMemberProtectWeaker") do
		if entity ~= ev.entity and entity.FamilyTrip_familyMember.family == family and entity.health then
			members = members or {}
			members[#members + 1] = entity
		end
	end

	if members then
		local pri = protectorPriority(ev.entity, ev)
		local id = ev.entity.id

		for _, member in ipairs(members) do
			local mPri = protectorPriority(member, ev)
			if pri < mPri or (pri == mPri and id > member.id) then
				ev.suppressed = true
				ev.damage = 0

				return
			end
		end
	end
end)

event.objectGetHUDBeatBars.add("familyMemberRefactorBeatBar", {
	filter = "FamilyTrip_familyMemberRefactorBeatBar",
	order = "paceUser",
	sequence = -1,
}, function(ev)
	if ev.FamilyTip_beatmap == nil then
		local familyEntity = ECS.getEntityByID(ev.entity.FamilyTrip_familyMember.family)
		if familyEntity then
			ev.FamilyTip_beatmap = ev.beatmap
			ev.beatmap = Beatmap.getForEntity(familyEntity)
		end
	end
end)

FamilyMemberShareInvincibilityOnDamageLater = Delay.new(function(entity)
	if entity.invincibility then
		local isLeader, familyEntity = FamilyTrip.isFamilyLeader(entity)
		if isLeader and familyEntity then
			for _, memberEntity in iterateFamilyMembers(familyEntity.FamilyTrip_family) do
				Invincibility.activate(memberEntity, entity.invincibility.remainingTurns)
			end
		end
	end
end)

event.objectTakeDamage.add("familyMemberShareInvincibilityOnDamage", {
	filter = "FamilyTrip_familyMemberShareInvincibilityOnDamage",
	order = "grantInvincibility",
	sequence = 1,
}, function(ev)
	if not ev.suppressed then
		FamilyMemberShareInvincibilityOnDamageLater(ev.entity)
	end
end)

event.objectGrooveChain.add("familyMemberGrooveChainIdleImmunity", {
	filter = "FamilyTrip_familyMemberGrooveChainIdleImmunity",
	order = "immunity",
}, function(ev)
	local immunity = ev.entity.FamilyTrip_familyMemberGrooveChainIdleImmunity
	if immunity.turns > 0 and immunity.types[ev.type] then
		ev.suppressed = true
	end
end)

local componentsFamilyMemberGrooveChainIdleImmunity = { "FamilyTrip_familyMemberGrooveChainIdleImmunity" }

event.turn.add("familyMemberGrooveChainIdleImmunity", "nextTurnEffect", function()
	for memberEntity in ECS.entitiesWithComponents(componentsFamilyMemberGrooveChainIdleImmunity) do
		local component = memberEntity.FamilyTrip_familyMemberGrooveChainIdleImmunity
		if FamilyTrip.isFamilyLeader(memberEntity) then
			component.turns = math.max(0, component.turns - 1)
		else
			component.turns = component.immuneTurns
		end
	end
end)

event.gameStateLevel.add("attackableOverrideInLobby", "levelLoadingDone", function()
	for entity in ECS.entitiesWithComponents { "FamilyTrip_attackableOverrideInLobby" } do
		Attack.updateAttackability(entity)
	end
end)

event.objectUpdateAttackability.add("overrideInLobby", {
	filter = "FamilyTrip_attackableOverrideInLobby",
	order = "finalize",
}, function(ev)
	if CurrentLevel.isLobby() then
		ev.flags = ev.entity.FamilyTrip_attackableOverrideInLobby.attackFlags
	end
end)

event.holderDescentArrive.add("itemToggleableResetByFamilyMember", {
	filter = "itemToggleable",
	order = "contents",
}, function(ev)
	if ev.holder and FamilyTrip.isFamilyLeader(ev.holder) == false then
		ev.entity.itemToggleable.active = ECS.getEntityPrototype(ev.entity.name).itemToggleable.active
	end
end)

event.levelSequenceUpdate.add("familyStoryBosses", {
	order = "storyBosses",
	sequence = 1,
}, function(ev)
	if ev.options.type ~= ProceduralLevel.GENERATOR_TYPE then
		return
	end

	local bosses
	for _, proto in ipairs(ev.characterPrototypes) do
		if proto.FamilyTrip_traitStoryBosses then
			bosses = proto.FamilyTrip_traitStoryBosses.bosses
		else
			return
		end
	end

	if not (bosses and bosses[1]) then
		return
	end

	bosses = Utilities.arrayCopy(bosses)

	for i = #ev.sequence, 1, -1 do
		local entry = ev.sequence[i]
		if entry.boss then
			entry.boss = bosses[#bosses]
			bosses[#bosses] = nil

			if not bosses[1] then
				break
			end
		end
	end
end)

local function allPlayerHasTraitStoryBosses()
	for _, name in ipairs(Player.getInitialCharacterList()) do
		local prototype = ECS.getEntityPrototype(name)
		if prototype and not prototype.FamilyTrip_traitStoryBosses then
			return false
		end
	end

	return true
end

event.gameStateLevel.override("spawnDad", function(func, ev)
	if not allPlayerHasTraitStoryBosses() then
		func(ev)
	end
end)

event.bossFloorEnter.add("familySpawnLute", {
	key = Boss.Type.NECRODANCER_2,
	sequence = 1,
}, function()
	if allPlayerHasTraitStoryBosses() then
		Object.spawn("WeaponGoldenLute", 0, Boss.DOOR_Y - 1)
	end
end)

event.objectMove.add("setGameplayFacingOnMove", {
	filter = { "FamilyTrip_setFacingOnMove", "facingDirection" },
	order = "facing",
	sequence = 1,
}, function(ev)
	Facing.setDirection(ev.entity, Action.move(ev.x - ev.prevX, ev.y - ev.prevY))
end)

event.objectHeal.add("soulLinkHeal", {
	filter = "soulLinkable",
	order = "soulLink",
}, function(ev)
	if ev.FamilyTrip_soulLinkHeal or ev.healer == ev.entity or CurrentLevel.isLoading() then
		return
	end

	for _, entry in ipairs(SoulLink.list(ev.entity, "FamilyTrip_soulLinkHeal")) do
		for _, entity in ipairs(entry.targets) do
			local evClone = Utilities.deepCopy(ev)
			evClone.FamilyTrip_soulLinkHeal = entity
			ObjectEvents.fire("heal", entity, evClone)
		end
	end
end)

local updateClientCharOrderPending = true

function FamilyTrip.updateClientCharOrderPending()
	updateClientCharOrderPending = true
end

event.gameStateLevel.add("updateClientCharOrderPending", "resetLevelVariables", FamilyTrip.updateClientCharOrderPending)

SettingCustomCharOrder = Settings.user.table {
	id = "customCharOrder",
	name = "Custom character orders",
	desc = "Customize character orders of `Family Soul`.\
If you want Dorian always be the first and Aria to be second, fill in {\"Dorian\",\"Aria\"}\
Available values: Aria, Cadence, Dorian, Melody",
	setter = FamilyTrip.updateClientCharOrderPending,
	visibility = Settings.Visibility.VISIBLE,
}

SettingCanCustomizeCharOrder = Settings.shared.bool {
	id = "canCustomCharOrder",
	name = "Allow custom character orders",
	default = true,
	cheat = false,
	-- enableIf = function()
	-- 	return SettingsStorage.get "mod.FamilyTrip.customFamilyMembers" == ""
	-- end,
}

UserDefinedCharOrders = Snapshot.loopVariable {}

local updateUserDefinedCharOrder
FamilyTrip.Action_Special_DefineCharOrder, updateUserDefinedCharOrder = CustomActions.registerSystemAction {
	id = "updateUserCharOrder",
	callback = function(playerID, args)
		if type(args) ~= "table" or type(args.custom) ~= "table" or not SettingCanCustomizeCharOrder then
			return
		end

		UserDefinedCharOrders[playerID] = UserDefinedCharOrders[playerID] or {}
		local customizedSet = UserDefinedCharOrders[playerID]

		local playerEntity = Player.getPlayerEntity(playerID)
		if not (playerEntity and playerEntity.name == FamilyTrip.FamilySoulName and playerEntity.FamilyTrip_family) then
			return
		end

		local entityID = tonumber(playerID) or 0
		if customizedSet[entityID] then
			return
		end

		customizedSet[entityID] = true

		local customizedOrders = {}

		local nameMapping = {
			aria = "FamilyTrip_GrandMother",
			cadence = "FamilyTrip_Daughter",
			dorian = "FamilyTrip_Father",
			melody = "FamilyTrip_Mother",
		}
		for index, name in ipairs(args.custom) do
			customizedOrders[nameMapping[tostring(name):lower()] or false] = index
		end

		local defaultOrders = {}
		for index, member in ipairs(playerEntity.FamilyTrip_family.members) do
			defaultOrders[member] = index
		end

		table.sort(playerEntity.FamilyTrip_family.members, function(l, r)
			local le = ECS.getEntityByID(l)
			local re = ECS.getEntityByID(r)

			local lo = le and customizedOrders[le.name] or math.huge
			local ro = re and customizedOrders[re.name] or math.huge
			if lo ~= ro then
				return lo < ro
			end

			lo = defaultOrders[l]
			ro = defaultOrders[r]
			if lo ~= ro then
				return lo < ro
			end

			return (le and le.id or 0) < (re and re.id or 0)
		end)
	end,
}

event.tick.add("updateUserDefinedCharOrder", "pendingDelays", function()
	if updateClientCharOrderPending and next(SettingCustomCharOrder) then
		for _, playerID in ipairs(LocalCoop.getLocalPlayerIDs()) do
			local entity = Player.getPlayerEntity(playerID)
			if entity and entity.name == FamilyTrip.FamilySoulName and Character.isAlive(entity) then
				updateClientCharOrderPending = false
				updateUserDefinedCharOrder(playerID, { custom = SettingCustomCharOrder })
			end
		end
	end
end)

event.renderPlayerListEntry.add("familyUseLeaderSprite", {
	filter = "FamilyTrip_familyUseLeaderSpriteOnPlayerList",
	order = "head",
	sequence = -10,
}, function(ev)
	local leaderEntity = FamilyTrip.getFamilyLeader(ev.entity.FamilyTrip_family)
	if leaderEntity then
		ev.spriteEntity = leaderEntity
	end
end)

event.menu.add("pauseMenuAddFamilyUserSetting", {
	key = "pause",
	sequence = 10,
}, function(ev)
	if not (ev.menu and ev.menu.entries) then
		return
	end

	for _, playerID in ipairs(LocalCoop.getLocalPlayerIDs()) do
		local entity = Player.getPlayerEntity(playerID)
		if entity and entity.name == FamilyTrip.FamilySoulName then
			return table.insert(ev.menu.entries, 5, {
				label = "Family Trip",
				action = function()
					SettingsMenu.open {
						autoSave = true,
						emptySearchText = false,
						highlightChanges = true,
						isSearching = false,
						layer = Settings.Layer.LOCAL,
						minimumVisibility = Settings.Visibility.VISIBLE,
						overrideLayer = Settings.Layer.LOCAL,
						prefix = "mod.FamilyTrip",
						searchText = false,
						showSliders = true,
						submenu = true,
						title = false,
					}
				end,
			})
		end
	end
end)

return FamilyTrip
