"""The sound bank: name -> (recipe, variant count, target peak dBFS, format).

`stereo` recipes return (n, 2) arrays; others are mono. `fmt` is "wav" for
one-shots (Godot can then verify sample data in headless tests) or "ogg" for
long or looping material. `bus` is the mix routing the game applies:
  sfx      dry effects bus (already carry any baked tail)
  room     light room reverb bus (small foley)
  canyon   big canyon reverb send (howls, bells, roars, gunfire)
  ui       interface bus
"""
import sfx_creatures as cr
import sfx_weapons as wp
import sfx_world as wd

# name: (fn, variants, peak_dbfs, fmt, bus)
SOUNDS = {
	# --- player weapon ---
	"shot": (wp.carbine_shot, 3, -1.0, "wav", "sfx"),
	"click": (wp.dry_click, 1, -8.0, "wav", "sfx"),
	"bolt": (wp.bolt_cycle, 2, -8.0, "wav", "room"),
	"mag_out": (wp.mag_out, 1, -9.0, "wav", "room"),
	"mag_in": (wp.mag_in, 1, -9.0, "wav", "room"),
	"reload": (wp.reload_full, 1, -8.0, "wav", "room"),
	"casing": (wp.casing, 3, -14.0, "wav", "room"),
	"casing_snow": (wp.casing_snow, 3, -20.0, "wav", "room"),
	# --- impacts ---
	"hit": (wp.hit, 3, -6.0, "wav", "room"),
	"headshot": (wp.headshot, 2, -4.0, "wav", "room"),
	"impact_flesh": (wp.impact_flesh, 3, -6.0, "wav", "room"),
	"impact_snow": (wp.impact_snow, 3, -12.0, "wav", "room"),
	"impact_wood": (wp.impact_wood, 3, -8.0, "wav", "room"),
	"impact_stone": (wp.impact_stone, 3, -8.0, "wav", "canyon"),
	"impact_metal": (wp.impact_metal, 3, -8.0, "wav", "canyon"),
	"hitmarker": (wp.hitmarker, 1, -16.0, "wav", "ui"),
	"kill": (wp.kill_confirm, 1, -10.0, "wav", "ui"),
	# --- player body ---
	"hurt": (wp.player_hurt, 3, -6.0, "wav", "room"),
	"land": (wp.land, 2, -12.0, "wav", "room"),
	"heartbeat": (wp.heartbeat, 1, -10.0, "wav", "sfx"),
	"tinnitus": (wp.tinnitus, 1, -22.0, "wav", "sfx"),
	"whoosh": (wp.whoosh, 3, -14.0, "wav", "room"),
	"throw": (wp.throw, 2, -14.0, "wav", "room"),
	"takedown": (wp.takedown, 2, -4.0, "wav", "room"),
	"snuff": (wp.snuff, 2, -12.0, "wav", "room"),
	"stone_land": (wp.stone_land, 2, -8.0, "wav", "room"),
	"gate": (wp.gate_grind, 1, -4.0, "ogg", "canyon"),
	# --- warpack ---
	"rifle_crack": (wp.rifle_crack, 3, -2.0, "wav", "sfx"),
	"growl": (cr.growl, 3, -8.0, "wav", "room"),
	"snarl": (cr.snarl, 2, -8.0, "wav", "room"),
	"growl_windup": (cr.growl_windup, 1, -7.0, "wav", "room"),
	"howl": (cr.howl, 3, -6.0, "wav", "canyon"),
	"yelp": (cr.yelp, 2, -8.0, "wav", "room"),
	"death": (cr.death, 2, -7.0, "wav", "room"),
	"huff": (cr.huff, 3, -14.0, "wav", "room"),
	"wolf_breath": (cr.wolf_breath, 2, -18.0, "wav", "room"),
	"bite": (cr.bite, 3, -5.0, "wav", "room"),
	"wolf_footstep": (cr.wolf_footstep, 4, -20.0, "wav", "room"),
	"wolf_footstep_heavy": (cr.wolf_footstep_heavy, 4, -14.0, "wav", "room"),
	"armor_clink": (cr.armor_clink, 3, -18.0, "wav", "room"),
	"armor_break": (cr.armor_break, 1, -3.0, "ogg", "canyon"),
	"roar": (cr.roar, 1, -3.0, "ogg", "canyon"),
	"charge_rumble": (cr.charge_rumble, 1, -6.0, "ogg", "room"),
	"quake": (cr.quake, 1, -2.0, "ogg", "canyon"),
	# --- bells and Remembrance ---
	"bell": (wd.mother_bell, 1, -3.0, "ogg", "canyon"),
	"bell_toll": (wd.bell_toll, 3, -8.0, "ogg", "canyon"),
	"chime": (wd.chime, 3, -12.0, "wav", "sfx"),
	"bell_pickup": (wd.bell_pickup, 3, -9.0, "ogg", "sfx"),
	"pickup": (wd.pickup, 1, -12.0, "wav", "sfx"),
	"ammo_pickup": (wd.ammo_pickup, 2, -16.0, "wav", "sfx"),
	"hang": (wd.hang, 1, -10.0, "ogg", "sfx"),
	"sense": (wd.sense, 1, -12.0, "wav", "sfx"),
	"converge": (wd.converge, 1, -8.0, "wav", "sfx"),
	"volley": (wd.volley, 1, -3.0, "ogg", "sfx"),
	"sting": (wd.sting, 1, -8.0, "ogg", "sfx"),
	# --- interface ---
	"ui_click": (wd.ui_click, 2, -12.0, "wav", "ui"),
	"ui_hover": (wd.ui_hover, 1, -20.0, "wav", "ui"),
	"ui_confirm": (wd.ui_confirm, 1, -12.0, "wav", "ui"),
	"ui_back": (wd.ui_back, 1, -14.0, "wav", "ui"),
	"pause_in": (wd.pause_in, 1, -12.0, "wav", "ui"),
	"pause_out": (wd.pause_out, 1, -12.0, "wav", "ui"),
	# --- scattered ambient one-shots ---
	"amb_creak_pine": (wd.amb_creak_pine, 3, -20.0, "wav", "canyon"),
	"amb_bell_far": (wd.amb_bell_far, 3, -20.0, "ogg", "canyon"),
	"amb_ember": (wd.amb_ember, 3, -22.0, "wav", "room"),
	"amb_rope": (wd.amb_rope, 2, -22.0, "wav", "room"),
	"amb_cage": (wd.amb_cage, 2, -20.0, "wav", "canyon"),
	"amb_chain": (wd.amb_chain, 2, -20.0, "wav", "canyon"),
	"amb_snow": (wd.amb_snow, 2, -24.0, "wav", "canyon"),
	"amb_rock": (wd.amb_rock, 2, -20.0, "wav", "canyon"),
}
