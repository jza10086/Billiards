## Business-owned setting defaults, constraints and UI hierarchy. No runtime side effects.
extends RefCounted

static func schema() -> Dictionary:
	return {
		"schema_format": 3,
		"settings_version": 1,
		"fields": {
			"shot_seconds": {
				"type": "int",
				"default": 30,
				"title": "每杆秒数（包括摆白球）",
				"audience": "room",
				"apply": "next_round",
				"min": 10,
				"max": 90,
				"control": "number"
			},
			"duration": {
				"type": "int",
				"default": 600,
				"title": "赛事保护时限（秒）",
				"audience": "room",
				"apply": "next_round",
				"min": 120,
				"max": 1800,
				"control": "number"
			}
		},
		"layout": [
			{
				"id": "room",
				"title": "游戏规则",
				"expanded": true,
				"children": [
					{
						"field": "shot_seconds"
					},
					{
						"field": "duration"
					}
				]
			}
		]
	}
