if not require "necro.game.data.resource.GameMod".isModLoaded "CharacterSkins" then
	return {}
end

local FamilyTrip = require "FamilyTrip.FamilyTrip"
local FamilyTripCharacterSkins = {}

local CharacterSkins = require "CharacterSkins.CharacterSkins"
local SkinStorage = require "CharacterSkins.SkinStorage"
local SkinTemplate = require "CharacterSkins.SkinTemplate"
local SkinVirtualResource = require "CharacterSkins.SkinVirtualResource"

local Array = require "system.utils.Array"
local Config = require "necro.config.Config"
local Enum = require "system.utils.Enum"
local Event = require "necro.event.Event"
local FileIO = require "system.game.FileIO"
local Components = require "necro.game.data.Components"
local ECS = require "system.game.Entities"
local GFX = require "system.gfx.GFX"
local LocalCoop = require "necro.client.LocalCoop"
local Netplay = require "necro.network.Netplay"
local Player = require "necro.game.character.Player"
local PlayerList = require("necro.client.PlayerList")
local StringUtilities = require "system.utils.StringUtilities"
local Utilities = require "system.utils.Utilities"

FamilyTripCharacterSkins.PlayerAttribute = Netplay.PlayerAttribute.extend("FamilyTrip_Skin", Enum.data { user = true })

Components.register {
	FamilyTrip_characterSkins = {}
}

event.entitySchemaLoadNamedEntity.add("familySoulCharacterSkins", FamilyTrip.FamilySoulName, function(ev)
	ev.entity.FamilyTrip_characterSkins = {}
end)

local function isSameTexture(tex1, tex2)
	return SkinVirtualResource.getUnsubstitutedFile(tex1) == SkinVirtualResource.getUnsubstitutedFile(tex2)
end

local function applySprite(entity, sprite)
	local proto = ECS.getEntityPrototype(entity.name)
	local mirrorOffsetX = 0
	if entity.positionalSprite then
		local oldOffsetY = entity.positionalSprite.offsetY
		entity.positionalSprite.offsetX = sprite.offsetX or proto.positionalSprite.offsetX
		entity.positionalSprite.offsetY = sprite.offsetY or proto.positionalSprite.offsetY
		entity.rowOrder.z = entity.rowOrder.z + oldOffsetY - entity.positionalSprite.offsetY
		mirrorOffsetX = 2 * entity.positionalSprite.offsetX
	end
	entity.sprite.texture = sprite.texture or SkinVirtualResource.getUnsubstitutedFile(proto.sprite.texture)
	entity.sprite.width = sprite.width or proto.sprite.width
	entity.sprite.height = sprite.height or proto.sprite.height
	entity.sprite.mirrorOffsetX = 24 - entity.sprite.width - mirrorOffsetX
	if entity.attachmentCopySpritePosition then
		local protoHead = proto.attachmentCopySpritePosition
		entity.attachmentCopySpritePosition.offsetX = sprite.offsetX or protoHead.offsetX
		entity.attachmentCopySpritePosition.offsetY = sprite.offsetY or protoHead.offsetY
		entity.attachmentCopySpritePosition.offsetZ = sprite.offsetY and -sprite.offsetY or protoHead.offsetZ
	end
	if entity.CharacterSkins_textureBounds then
		local sheetWidth = sprite.sheetWidth or GFX.getImageWidth(entity.sprite.texture)
		local sheetHeight = sprite.sheetHeight or GFX.getImageHeight(entity.sprite.texture)
		local spriteWidth, spriteHeight = entity.sprite.width, entity.sprite.height
		entity.CharacterSkins_textureBounds.width = math.max(1, math.floor(sheetWidth / spriteWidth)) * spriteWidth
		entity.CharacterSkins_textureBounds.height = math.max(1, math.floor(sheetHeight / spriteHeight)) * spriteHeight
	end
	if entity.CharacterSkins_hideIfUnskinned then
		entity.CharacterSkins_hideIfUnskinned.active = sprite.hideIfTransformed or isSameTexture(entity.sprite.texture, proto.sprite.texture)
	end
end

local function applyFamilyMemberSkin(memberEntity, playerID, characterName)
	local attribute = PlayerList.getAttribute(playerID, FamilyTripCharacterSkins.PlayerAttribute)
	if type(attribute) ~= "table" or type(attribute[characterName]) ~= "table" then
		return
	end

	local sprites = attribute[characterName].sprites
	if not sprites then
		return
	end

	local sprite = sprites[memberEntity.CharacterSkins_skinnable.imageType]
	if not sprite then
		return
	end

	sprite = Utilities.fastCopy(sprite)
	local prototype = ECS.getEntityPrototype(memberEntity.name)
	sprite.texture = FamilyTripCharacterSkins.getPathForPlayer(playerID, sprite.texture, characterName, prototype and prototype.sprite and prototype.sprite.texture)
	applySprite(memberEntity, sprite)

	if memberEntity.characterWithAttachment then
		local attachment = ECS.getEntityByID(memberEntity.characterWithAttachment.attachmentID or 0)
		if attachment then
			applyFamilyMemberSkin(attachment, playerID, characterName)
		end
	end
end

local memberNameMapping = {
	FamilyTrip_Daughter = "Cadence",
	FamilyTrip_Father = "Dorian",
	FamilyTrip_GrandMother = "Aria",
	FamilyTrip_Mother = "Melody",
}

function FamilyTripCharacterSkins.applyFamilyMemberSkins()
	for _, entity in ipairs(Player.getPlayerEntities()) do
		if entity.name == FamilyTrip.FamilySoulName and entity.FamilyTrip_family and entity.controllable and entity.controllable.playerID ~= 0 then
			for _, member in ipairs(entity.FamilyTrip_family.members) do
				local memberEntity = ECS.getEntityByID(member)
				local name = memberEntity and memberNameMapping[memberEntity.name]
				if name and memberEntity.CharacterSkins_skinnable then
					applyFamilyMemberSkin(memberEntity, entity.controllable.playerID, name)
				end
			end
		end
	end
end

local virtualResourceID = "FamilyTrip_characterSkin"

function FamilyTripCharacterSkins.getPathForPlayer(playerID, imageName, characterName, fallback)
	return StringUtilities.buildQueryString(string.format("virtual/%s", virtualResourceID), {
		playerID = playerID,
		name = imageName,
		character = characterName,
		fallback = fallback,
	})
end

local function getAssetReloadKey(playerID)
	return string.format("FamilyTrip_CharacterSkinsBase%s", playerID or "")
end

function FamilyTripCharacterSkins.update(playerID)
	return event.assetReload.fire({ name = getAssetReloadKey(playerID) })
end

Event.loadVirtualResource.add("characterSkins", virtualResourceID, function(ev)
	local args = ev.args
	local playerID = tonumber(args.playerID)

	ev.dependencies = { getAssetReloadKey(), getAssetReloadKey(playerID), args.fallback }

	local imageData
	if Config.modSkinVisibility then
		local attribute = PlayerList.getAttribute(playerID, FamilyTripCharacterSkins.PlayerAttribute)
		if type(attribute) == "table" and type(attribute._data) == "table" then
			imageData = attribute._data[args.name]
		end
	end

	ev.data = Array.fromString(Array.Type.UINT8, imageData or FileIO.readFileToString(SkinVirtualResource.getUnsubstitutedFile(args.fallback)))
end)

local function tryReadFile(filename)
	if filename then
		return FileIO.readFileToString(filename)
	end
end

local function applyEquipmentVisibility(skin)
	if CharacterSkins.getEquipmentVisibility() ~= CharacterSkins.EquipmentVisibility.DEFAULT_SKIN then
		skin = skin or {}
		skin.equipment = (CharacterSkins.getEquipmentVisibility() == CharacterSkins.EquipmentVisibility.ON)
	end

	return skin
end

local function makeNetworkSkin(skin, characterName, data, playerID)
	if skin and skin.sprites then
		local customized = false
		skin = Utilities.fastCopy(skin)
		for name, sprite in pairs(skin.sprites) do
			if sprite.texture then
				local identifier = characterName .. "_" .. name
				data[identifier] = tryReadFile(sprite.texture)

				sprite.sheetWidth, sprite.sheetHeight = GFX.getImageSize(sprite.texture)
				if sprite.sheetWidth == 0 or sprite.sheetHeight == 0 then
					sprite.sheetWidth, sprite.sheetHeight = nil, nil
				end
				sprite.texture = identifier
				customized = true
			end
		end

		if skin.equipment == nil then
			skin.equipment = not customized
		end
	end

	return applyEquipmentVisibility(skin)
end

local revisionCounter = 0

function FamilyTripCharacterSkins.upload(coopID)
	local playerID = LocalCoop.getLocalPlayerIDs()[coopID]
	if playerID then
		revisionCounter = revisionCounter + 1
		local attribute = { _data = {}, _rev = revisionCounter }

		for _, characterName in pairs(memberNameMapping) do
			attribute[characterName] = makeNetworkSkin(SkinStorage.get(coopID, characterName), characterName, attribute._data, playerID)
		end

		LocalCoop.setPlayerAttribute(playerID, FamilyTripCharacterSkins.PlayerAttribute, attribute)
	end
end

-- just put apply function in tick event, too lazy to optimize xD
local function todoOptimizeUpdateConditions()
	for coopID, playerID in ipairs(LocalCoop.getLocalPlayerIDs()) do
		local entity = Player.getPlayerEntity(playerID)
		if entity and entity.name == FamilyTrip.FamilySoulName then
			FamilyTripCharacterSkins.upload(coopID)
		end
	end

	FamilyTripCharacterSkins.applyFamilyMemberSkins()
end

event.periodicCheck.add("familyMemberSkins", "init", todoOptimizeUpdateConditions)
event.gameStateLevel.add("familyMemberSkins", "levelLoadingDone", todoOptimizeUpdateConditions)

return FamilyTripCharacterSkins
