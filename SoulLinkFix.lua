local comp = (require "system.utils.Enum".string {}.extend "") .. "soulLinkBugFix"

require "necro.game.data.Components".register { [comp] = {} }

event.entitySchemaLoadEntity.add(nil, "mystery", function(ev)
	if ev.entity.soulLink and ev.entity.target == nil then
		ev.entity.target = {}
		ev.entity[comp] = {}
	end
end)

event.objectSpawn.add(nil, {
	filter = comp,
	order = "attributes",
	sequence = -1,
}, function(ev)
	if ev.attributes and ev.attributes.soulLink then
		ev.attributes.target = ev.attributes.target or {}
		ev.attributes.target.entity = ev.attributes.soulLink.target
	end
end)
