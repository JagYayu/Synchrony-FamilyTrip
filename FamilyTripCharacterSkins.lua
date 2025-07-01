if not require "necro.game.data.resource.GameMod".isModLoaded "CharacterSkins" then
	return {}
end

local FamilyTrip = require "FamilyTrip.FamilyTrip"
local FamilyTripCharacterSkins = {}

local CharacterSkins = require "CharacterSkins.CharacterSkins"
local SkinStorage = require "CharacterSkins.SkinStorage"
local SkinVirtualResource = require "CharacterSkins.SkinVirtualResource"

local Array = require "system.utils.Array"
local Components = require "necro.game.data.Components"
local Config = require "necro.config.Config"
local ECS = require "system.game.Entities"
local Enum = require "system.utils.Enum"
local FileIO = require "system.game.FileIO"
local GFX = require "system.gfx.GFX"
local LocalCoop = require "necro.client.LocalCoop"
local Menu = require "necro.menu.Menu"
local Netplay = require "necro.network.Netplay"
local Player = require "necro.game.character.Player"
local PlayerList = require("necro.client.PlayerList")
local Settings = require "necro.config.Settings"
local StringUtilities = require "system.utils.StringUtilities"
local Utilities = require "system.utils.Utilities"
local VisualUpdate = require "necro.cycles.VisualUpdate"

FamilyTripCharacterSkins.PlayerAttribute = Netplay.PlayerAttribute.extend("FamilyTrip_Skin", Enum.data { user = true })

Components.register {
	FamilyTrip_characterSkins = {}
}

event.entitySchemaLoadNamedEntity.add("familySoulCharacterSkins", FamilyTrip.FamilySoulName, function(ev)
	ev.entity.FamilyTrip_characterSkins = {}
end)

local function isSkinVisibleForPlayerID(playerID)
	local visibility = CharacterSkins.getSkinVisibility()
	if visibility == CharacterSkins.Visibility.LOCAL_PLAYERS then
		return LocalCoop.isLocal(playerID)
	else
		return visibility == CharacterSkins.Visibility.ALWAYS
	end
end

local function isSameTexture(tex1, tex2)
	return SkinVirtualResource.getUnsubstitutedFile(tex1) == SkinVirtualResource.getUnsubstitutedFile(tex2)
end

local function applySprite(entity, sprite, remap)
	local proto = ECS.getEntityPrototype(remap or entity.name)
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
		entity.attachmentCopySpritePosition.offsetX = sprite.offsetX or (protoHead and protoHead.offsetX)
			or entity.attachmentCopySpritePosition.offsetX
		entity.attachmentCopySpritePosition.offsetY = sprite.offsetY or (protoHead and protoHead.offsetY)
			or entity.attachmentCopySpritePosition.offsetY
		entity.attachmentCopySpritePosition.offsetZ = sprite.offsetY and -sprite.offsetY
			or (protoHead and protoHead.offsetZ) or entity.attachmentCopySpritePosition.offsetZ
	end
	if entity.CharacterSkins_textureBounds then
		local sheetWidth = sprite.sheetWidth or GFX.getImageWidth(entity.sprite.texture)
		local sheetHeight = sprite.sheetHeight or GFX.getImageHeight(entity.sprite.texture)
		local spriteWidth, spriteHeight = entity.sprite.width, entity.sprite.height
		entity.CharacterSkins_textureBounds.width = math.max(1, math.floor(sheetWidth / spriteWidth)) * spriteWidth
		entity.CharacterSkins_textureBounds.height = math.max(1, math.floor(sheetHeight / spriteHeight)) * spriteHeight
	end
	if entity.CharacterSkins_hideIfUnskinned then
		entity.CharacterSkins_hideIfUnskinned.active = sprite.hideIfTransformed or
			isSameTexture(entity.sprite.texture, proto.sprite.texture)
	end
end

local function applyDefaultSkin(entity, remap)
	applySprite(entity, {}, remap)
end

local characterNameSet = {
	Cadence = true,
	Dorian = true,
	Aria = true,
	Melody = true,
}

local function applySkin(entity, playerID, characterName)
	if not isSkinVisibleForPlayerID(playerID) then
		return applyDefaultSkin(entity)
	end

	local attribute = PlayerList.getAttribute(playerID, FamilyTripCharacterSkins.PlayerAttribute)
	if type(attribute) ~= "table" or type(attribute[characterName]) ~= "table" then
		return applyDefaultSkin(entity)
	end

	-- characterName = attribute[characterName].remap or characterName
	-- if not attribute[characterName] then
	-- 	return applyDefaultSkin(entity)
	-- end

	local sprites = attribute[characterName].sprites
	if not sprites then
		return applyDefaultSkin(entity)
	end

	local sprite = sprites[entity.CharacterSkins_skinnable.imageType]
	if not sprite then
		return applyDefaultSkin(entity)
	end

	sprite = Utilities.fastCopy(sprite)
	local prototype = ECS.getEntityPrototype(entity.name)
	sprite.texture = FamilyTripCharacterSkins.getPathForPlayer(playerID, sprite.texture, characterName,
		prototype and prototype.sprite and prototype.sprite.texture)
	applySprite(entity, sprite)
end

local function appendHead(what)
	return what .. "Head"
end

local function applyAttachmentSkin(memberEntity, playerID, characterName)
	if memberEntity.characterWithAttachment then
		local attachment = ECS.getEntityByID(memberEntity.characterWithAttachment.attachmentID or 0)
		if attachment then
			applySkin(attachment, playerID, characterName, appendHead)
		end
	end
end

local uploadPending = false

local function handlerUploadPending()
	uploadPending = true
end

FamilyTripCharacterSkins.uploadPending = handlerUploadPending

local memberNameMapping = {
	FamilyTrip_Daughter = "Cadence",
	FamilyTrip_Father = "Dorian",
	FamilyTrip_GrandMother = "Aria",
	FamilyTrip_Mother = "Melody",
}

-- TODO not implement yet
SettingSkinMap = Settings.user.table {
	id = "skinMap",
	name = "Skin remapping",
	visibility = Settings.Visibility.HIDDEN,
	-- default = {
	-- 	Cadence = "Cadence",
	-- 	Dorian = "Dorian",
	-- 	Aria = "Aria",
	-- 	Melody = "Melody",
	-- },
	setter = handlerUploadPending,
}

local function applySpecificFamilyMemberSkins(playerID)
	local entity = Player.getPlayerEntity(playerID)
	if not entity or entity.name ~= FamilyTrip.FamilySoulName or not entity.FamilyTrip_family then
		return
	end

	for _, member in ipairs(entity.FamilyTrip_family.members) do
		local memberEntity = ECS.getEntityByID(member)
		local character = memberEntity and memberNameMapping[memberEntity.name]
		if character and memberEntity.CharacterSkins_skinnable then
			applySkin(memberEntity, playerID, character)
			applyAttachmentSkin(memberEntity, playerID, character)
		end
	end
end

function FamilyTripCharacterSkins.applyFamilyMemberSkins(playerID)
	if playerID then
		return applySpecificFamilyMemberSkins(playerID)
	end

	for _, playerID in ipairs(PlayerList.getPlayerList()) do
		applySpecificFamilyMemberSkins(playerID)
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

event.loadVirtualResource.add("characterSkins", virtualResourceID, function(ev)
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

	ev.data = Array.fromString(Array.Type.UINT8,
		imageData or FileIO.readFileToString(SkinVirtualResource.getUnsubstitutedFile(args.fallback)))
end)

event.clientDisconnect.add("undateCharacterSkins", "reset", FamilyTripCharacterSkins.update)

event.clientPlayerList.add("reloadCharacterSkins", FamilyTripCharacterSkins.PlayerAttribute, function(ev)
	FamilyTripCharacterSkins.update(ev.playerID)
	applySpecificFamilyMemberSkins(ev.playerID)
	VisualUpdate.trigger()
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

local function makeNetworkSkin(skin, characterName, data, remap)
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

	skin = applyEquipmentVisibility(skin)
	skin.remap = remap

	return skin
end

local revisionCounter = 0

function FamilyTripCharacterSkins.upload(coopID)
	local playerID = LocalCoop.getLocalPlayerIDs()[coopID]
	if playerID then
		revisionCounter = revisionCounter + 1
		local attribute = { _data = {}, _rev = revisionCounter }

		for _, characterName in pairs(memberNameMapping) do
			local remapName = characterName
			local prototype = ECS.getEntityPrototype(SettingSkinMap[characterName])
			if prototype and prototype.playableCharacter then
				remapName = SettingSkinMap[characterName]
			end

			if remapName then
				attribute[characterName] = makeNetworkSkin(SkinStorage.get(coopID, remapName),
					remapName, attribute._data, remapName)
			else
				attribute[remapName] = makeNetworkSkin(SkinStorage.get(coopID, remapName), remapName, attribute._data)
			end
		end

		LocalCoop.setPlayerAttribute(playerID, FamilyTripCharacterSkins.PlayerAttribute, attribute)
	end
end

event.objectControllerChanged.add("queueCharacterSkinUpload", {
	filter = "CharacterSkins_skinUseControllerPlayerID",
	order = "persistence",
	sequence = -1,
}, handlerUploadPending)

event.objectCharacterSwitchTo.add("queueCharacterSkinUpload", {
	filter = "CharacterSkins_skinUseControllerPlayerID",
	order = "skin",
}, handlerUploadPending)

event.clientLogIn.add("queueCharacterSkinUpload", "playerList", handlerUploadPending)

event.menu.add("queueCharacterSkinUpload", "CharacterSkins_skinSelector", handlerUploadPending)

event.periodicCheck.add("familyMemberSkins", "init", function()
	if uploadPending and not Menu.isOpen() then
		for coopID, playerID in ipairs(LocalCoop.getLocalPlayerIDs()) do
			local entity = Player.getPlayerEntity(playerID)
			if entity and entity.name == FamilyTrip.FamilySoulName then
				FamilyTripCharacterSkins.upload(coopID)
			end
		end

		uploadPending = false
	end

	FamilyTripCharacterSkins.applyFamilyMemberSkins()
end)

return FamilyTripCharacterSkins
