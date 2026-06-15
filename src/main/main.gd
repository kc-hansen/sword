extends Node2D
## Playable match prototype for Sengoku: Way of the Sword.
##
## Round flow (faithful core):
##   1. Collect koku (auto, = max(3, provinces)).
##   2. SECRET ALLOCATION — clans split koku between a turn-order bid, a ninja bid,
##      and a levy budget, hidden behind a shield (two-step seal/commit).
##   3. REVEAL — turn order set by bids (highest first); ninja goes to top ninja bid.
##   4. WAR — in bid order: the ninja holder may attempt one assassination, each clan
##      spends its levy buying troops/ronin/castles, then maneuvers. Ronin disband
##      at end of the owner's turn.
##
## Combat: per-unit-type d12 in faithful order — ranged (archers, gunners) → casualties
## → melee (samurai, ronin, spearmen) → casualties, repeat. Castles add a temporary
## ashigaru garrison (level*2) that dies first.
##
## THROWAWAY prototype (immediate-mode _draw). Production systems are specified in
## design/gdd/systems-index.md and will be node-based per art-bible §8.4.

const DATA_PATH := "res://assets/data/provinces.json"
const DESIGN_W := 460.0
const DESIGN_H := 372.0
const TOP_BAR := 56.0
const BOTTOM_BAR := 64.0
const WIN_PROV := 10
const NINJA_SUCCESS := 8

enum Stage { MENU, ALLOCATE, REVEAL, WAR }
enum War { DEPLOY, MANEUVER }

const UNIT_KEYS := ["ash", "arc", "gun", "sam", "ron"]
const UNIT_NAME := {"ash": "Ashigaru", "arc": "Archer", "gun": "Gunner", "sam": "Samurai", "ron": "Ronin"}
const COST := {"ash": 1, "arc": 2, "gun": 4, "sam": 3, "ron": 3}
const VAL := {"ash": 3, "arc": 4, "gun": 6, "sam": 6, "ron": 7}
const CASTLE_COST := 2
const CASTLE_MAX := 3
const DAIMYO_MAX := 3
const DAIMYO_START := 2
const UNIT_DESC := {
	"ash": "Ashigaru — cheap melee fodder. Hits on a d12 of 3 or less (25%). Use them for numbers and to soak casualties.",
	"arc": "Archer — ranged. Fires in the volley BEFORE melee, so it deals damage without being hit back yet. Hits on 4 or less (33%).",
	"gun": "Gunner — ranged, fires first. Hits on 6 or less (50%) — your best damage per soldier, but costly.",
	"sam": "Samurai — elite melee. Hits on 6 or less (50%). Your hardest-hitting front line.",
	"ron": "Ronin — hired mercenaries. Powerful melee (hits on 7 or less, 58%) but they DISBAND at the end of your turn. Buy and strike the same turn.",
	"dai": "Daimyō (general) — leads an army into battle, adding several elite attacks. Each attack it launches from a province carries it forward; victories level it up (to Lv 3). It dies if its army is wiped out or its province is captured. You start with two.",
	"castle": "Castle — each level adds 2 garrison defenders that fight as ashigaru and die FIRST. Build on front-line provinces to hold them.",
}

# The Art of War — Sun Tzu (public domain, Lionel Giles translation)
const AOW_MENU := "If you know the enemy and know yourself, you need not fear the result of a hundred battles."
const AOW_DECEPTION := "All warfare is based on deception."
const AOW_SPIES := "Be subtle! Be subtle! — and use your spies for every kind of business."
const AOW_OPPORTUNITY := "Opportunities multiply as they are seized."
const AOW_VICTORY := "To win without fighting is the acme of skill — but Japan is yours all the same."
const AOW_DEFEAT := "He who knows when he can fight and when he cannot will be victorious. Today was not the day."
const AOW_ROUND := [
	"Let your plans be dark and impenetrable as night, and when you move, fall like a thunderbolt.",
	"The supreme art of war is to subdue the enemy without fighting.",
	"He will win who knows when to fight and when not to fight.",
	"In the midst of chaos, there is also opportunity.",
	"Victory comes from finding opportunities in problems.",
	"The greatest victory is that which requires no battle.",
	"Move swift as the wind, stay quiet as the forest.",
	"Strike where the enemy is unprepared; appear where you are not expected.",
	"He who is prudent and lies in wait for an enemy who is not, will be victorious.",
	"Plan for what is difficult while it is easy; do what is great while it is small.",
]

const C_SEA := Color(0.109804, 0.168627, 0.227451)
const C_PANEL := Color(0.043, 0.043, 0.043)
const C_PANEL2 := Color(0.082, 0.082, 0.082)
const C_IRON := Color(0.165, 0.180, 0.208)
const C_STEEL := Color(0.478, 0.518, 0.580)
const C_GOLD := Color(0.784, 0.592, 0.227)
const C_PARCH := Color(0.910, 0.875, 0.753)
const C_RED := Color(0.549, 0.110, 0.110)
const C_REDLT := Color(0.878, 0.565, 0.498)
const C_LABEL := Color(0.227, 0.227, 0.196)
const C_WHITE := Color(0.96, 0.95, 0.92)
const C_DIM := Color(0, 0, 0, 0.62)

var _provinces: Dictionary = {}
var _clans: Dictionary = {}
var _player: String = "A"
var _round: int = 0
var _stage: int = Stage.ALLOCATE
var _koku: Dictionary = {}
var _alloc: Dictionary = {}
var _order: Array = []
var _war_idx: int = 0
var _war_sub: int = War.DEPLOY
var _deploy_koku: int = 0
var _deploy_type: String = "ash"
var _shield: Dictionary = {"bid": 0, "ninja": 0, "levy": 0}
var _sealed: bool = false
var _difficulty: String = "normal"
var _ninja_holder: String = ""
var _ninja_used: bool = false
var _ninja_arm: bool = false
var _moved: Dictionary = {}
var _selected: String = ""
var _hovered: String = ""
var _events: Array = []
var _modal = null
var _game_over: bool = false
var _result: String = ""
var _auto: bool = false
var _show_help: bool = false
var _buttons: Array = []
var _font: Font
var _font_head: Font
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _roll_t := -1.0


func _process(delta: float) -> void:
	_t += delta
	var redraw := _stage == Stage.MENU
	if _roll_t >= 0.0:
		_roll_t += delta
		redraw = true
		if _roll_t >= 0.7:
			_roll_t = -1.0
	if _stage == Stage.WAR and _active() == _player and not _game_over:
		redraw = true
	if redraw:
		queue_redraw()


func _ready() -> void:
	var sysfb := ThemeDB.fallback_font
	_font = sysfb
	_font_head = sysfb
	var fb = load("res://assets/fonts/Inter.ttf")
	var fh = load("res://assets/fonts/Cinzel.ttf")
	if fb != null:
		fb.fallbacks = [sysfb]
		_font = fb
	if fh != null:
		fh.fallbacks = [fb if fb != null else sysfb, sysfb]
		_font_head = fh
	_rng.randomize()
	_compute_transform()
	_new_game()
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--autoplay" in args:
		_run_autoplay()
		return
	if "--shothelp" in args:
		_show_help = true
		await _shoot()
		return
	if "--shotdeploy" in args:
		_alloc[_player] = {"bid": 1, "ninja": 0, "levy": 10}
		_order = _clans.keys()
		_war_idx = 0
		_war_sub = War.DEPLOY
		_deploy_koku = 10
		_deploy_type = "ron"
		_stage = Stage.WAR
		_ninja_holder = _player
		_selected = "kanto"
		await _shoot()
		return
	if "--shotbattle" in args:
		_order = _clans.keys()
		_war_idx = 0
		_stage = Stage.WAR
		var force := _take_all_but_one(_provinces["kanto"])
		_resolve_battle("kanto", "mutsu", force)
		await _shoot()
		return
	if "--shot" in args:
		await _shoot()


func _new_game() -> void:
	_load_data()
	_assign_starting_daimyo()
	_round = 0
	_game_over = false
	_result = ""
	_events.clear()
	_modal = null
	_selected = ""
	_ninja_holder = ""
	_log("The Sengoku wars begin. Bid for initiative and the ninja, then conquer Japan.")
	_stage = Stage.MENU


func _start_campaign() -> void:
	_apply_difficulty()
	_begin_round()


func _apply_difficulty() -> void:
	for cid in _clans:
		if _difficulty == "easy":
			_clans[cid]["ai"] = "easy"
		elif _difficulty == "hard":
			_clans[cid]["ai"] = "hard"
		else:
			_clans[cid]["ai"] = {"B": "hard", "C": "medium", "D": "medium", "E": "easy"}.get(cid, "medium")


# ---------------------------------------------------------------- unit helpers

func _new_comp() -> Dictionary:
	var c := {}
	for k in UNIT_KEYS:
		c[k] = 0
	return c


func _army(p: Dictionary) -> int:
	var u: Dictionary = p["units"]
	var s := 0
	for k in UNIT_KEYS:
		s += int(u[k])
	return s


func _sum4(c: Dictionary) -> int:
	var s := 0
	for k in UNIT_KEYS:
		s += int(c.get(k, 0))
	return s


func _sync(p: Dictionary) -> void:
	p["army"] = _army(p)


func _comp_str(p: Dictionary) -> String:
	var u: Dictionary = p["units"]
	return "Ash %d · Arc %d · Gun %d · Sam %d · Rōn %d" % [int(u["ash"]), int(u["arc"]), int(u["gun"]), int(u["sam"]), int(u["ron"])]


func _comp_inline(c: Dictionary) -> String:
	var parts := []
	for k in UNIT_KEYS:
		if int(c.get(k, 0)) > 0:
			parts.append("%d %s" % [int(c[k]), UNIT_NAME[k].to_lower()])
	return " · ".join(parts) if parts.size() > 0 else "—"


func _loss_str(start: Dictionary, ending: Dictionary) -> String:
	var parts := []
	for k in UNIT_KEYS:
		var d := int(start.get(k, 0)) - int(ending.get(k, 0))
		if d > 0:
			parts.append("%d %s" % [d, UNIT_NAME[k].to_lower()])
	return " · ".join(parts) if parts.size() > 0 else "none"


func _type_name(t: String) -> String:
	return "Castle" if t == "castle" else String(UNIT_NAME.get(t, t))


func _take_all_but_one(p: Dictionary) -> Dictionary:
	var committed: Dictionary = (p["units"] as Dictionary).duplicate()
	var remain := _new_comp()
	for k in UNIT_KEYS:
		if int(committed[k]) > 0:
			committed[k] -= 1
			remain[k] += 1
			break
	p["units"] = remain
	_sync(p)
	return committed


func _assign_starting_daimyo() -> void:
	for cid in _clans:
		var owned := _owned(cid)
		owned.sort_custom(func(a, b): return _army(_provinces[a]) > _army(_provinces[b]))
		for i in min(DAIMYO_START, owned.size()):
			_provinces[owned[i]]["daimyo"] = 1


func _expire_ronin(cid: String) -> void:
	for pid in _owned(cid):
		var p: Dictionary = _provinces[pid]
		if int(p["units"]["ron"]) > 0:
			p["units"]["ron"] = 0
			_sync(p)


# ---------------------------------------------------------------- round flow

func _begin_round() -> void:
	_round += 1
	_moved = {}
	_log("Sun Tzu — \"%s\"" % AOW_ROUND[(_round - 1) % AOW_ROUND.size()])
	for cid in _clans:
		if _count(cid) > 0:
			_koku[cid] = max(3, _count(cid) + int(_count(cid) / 2))
	_alloc = {}
	for cid in _clans:
		if _count(cid) > 0 and cid != _player:
			_alloc[cid] = _ai_allocate(cid)
	_shield = {"bid": 0, "ninja": 0, "levy": 0}
	_sealed = false
	_stage = Stage.ALLOCATE
	if _provinces.has("kanto") and _provinces["kanto"].get("owner") == _player:
		_selected = "kanto"
	queue_redraw()


func _commit_allocation() -> void:
	_alloc[_player] = {"bid": int(_shield["bid"]), "ninja": int(_shield["ninja"]), "levy": int(_shield["levy"])}
	_do_reveal()


func _do_reveal() -> void:
	var alive := []
	for cid in _clans:
		if _count(cid) > 0:
			alive.append(cid)
	alive.sort_custom(func(a, b):
		var ba := int(_alloc[a]["bid"]) if _alloc.has(a) else 0
		var bb := int(_alloc[b]["bid"]) if _alloc.has(b) else 0
		if ba != bb:
			return ba > bb
		return _count(a) > _count(b))
	_order = alive
	# ninja goes to the highest ninja bid (must be > 0)
	_ninja_holder = ""
	var best := 0
	for cid in alive:
		var nb := int(_alloc.get(cid, {}).get("ninja", 0))
		if nb > best:
			best = nb
			_ninja_holder = cid
	_ninja_used = false
	_stage = Stage.REVEAL
	queue_redraw()


func _begin_war() -> void:
	_war_idx = -1
	_advance_war()


func _advance_war() -> void:
	_selected = ""
	_ninja_arm = false
	while not _game_over:
		_war_idx += 1
		if _war_idx >= _order.size():
			_begin_round()
			return
		var cid: String = _order[_war_idx]
		if _count(cid) == 0:
			continue
		_moved = {}
		if cid == _player and not _auto:
			_deploy_koku = int(_alloc.get(_player, {}).get("levy", 0))
			_deploy_type = "ash"
			_war_sub = War.DEPLOY
			_stage = Stage.WAR
			var owned := _owned(_player)
			if owned.size() > 0:
				_selected = owned[0]
			queue_redraw()
			return
		else:
			_ai_war_turn(cid)
			_check_victory()
	queue_redraw()


# ---------------------------------------------------------------- helpers

func _count(cid: String) -> int:
	var n := 0
	for pid in _provinces:
		if _provinces[pid].get("owner") == cid:
			n += 1
	return n


func _owned(cid: String) -> Array:
	var a := []
	for pid in _provinces:
		if _provinces[pid].get("owner") == cid:
			a.append(pid)
	return a


func _is_border(pid: String) -> bool:
	var p: Dictionary = _provinces[pid]
	for aid in p["adj"]:
		if _provinces.has(aid) and _provinces[aid].get("owner") != p.get("owner"):
			return true
	return false


func _clan_name(cid) -> String:
	return "neutral" if cid == null else String(_clans[cid]["name"])


func _active() -> String:
	if _stage == Stage.WAR and _war_idx >= 0 and _war_idx < _order.size():
		return _order[_war_idx]
	return _player


func _log(s: String) -> void:
	_events.append(s)
	while _events.size() > 6:
		_events.pop_front()


# ---------------------------------------------------------------- ninja

func _ninja_strike(target_id: String) -> void:
	if _ninja_used:
		return
	var p: Dictionary = _provinces[target_id]
	if p.get("owner") == _ninja_holder or p.get("owner") == null:
		return
	_ninja_used = true
	_ninja_arm = false
	var roll := _rng.randi_range(1, 12)
	if roll <= NINJA_SUCCESS:
		for k in ["sam", "gun", "arc", "ron", "ash"]:
			if int(p["units"][k]) > 0:
				p["units"][k] -= 1
				_sync(p)
				_log("%s's ninja assassinated a %s in %s (rolled %d)." % [_clan_name(_ninja_holder), UNIT_NAME[k].to_lower(), p["name"], roll])
				return
		_log("%s's ninja found %s undefended." % [_clan_name(_ninja_holder), p["name"]])
	else:
		_log("%s's ninja was discovered in %s — the strike failed (rolled %d)." % [_clan_name(_ninja_holder), p["name"], roll])


func _ai_ninja(cid: String) -> void:
	if _ninja_holder != cid or _ninja_used:
		return
	var best := ""
	var best_army := -1
	for pid in _provinces:
		var p: Dictionary = _provinces[pid]
		if p.get("owner") != null and p.get("owner") != cid and _army(p) > best_army:
			best_army = _army(p)
			best = pid
	if best != "":
		_ninja_strike(best)


# ---------------------------------------------------------------- combat

func _rh(n: int, value: int) -> int:
	var hits := 0
	for i in n:
		if _rng.randi_range(1, 12) <= value:
			hits += 1
	return hits


func _rm(comp: Dictionary, hits: int, order: Array) -> void:
	for k in order:
		if hits <= 0:
			break
		var take: int = min(int(comp[k]), hits)
		comp[k] -= take
		hits -= take


func _resolve_battle(att_id: String, def_id: String, att: Dictionary, att_dai: int = 0) -> void:
	var ap: Dictionary = _provinces[att_id]
	var dp: Dictionary = _provinces[def_id]
	var attacker = ap.get("owner")
	var def_owner = dp.get("owner")
	var def_dai := int(dp["daimyo"])
	var du: Dictionary = dp["units"]
	var gar0 := int(dp["castle"]) * 2
	var defw := {"ash": int(du["ash"]), "arc": int(du["arc"]), "gun": int(du["gun"]), "sam": int(du["sam"]), "ron": int(du["ron"]), "gar": gar0}
	var att_start := att.duplicate()
	var def_start := {"ash": int(du["ash"]), "arc": int(du["arc"]), "gun": int(du["gun"]), "sam": int(du["sam"]), "ron": int(du["ron"])}
	var a0 := _sum4(att)
	var d0 := _sum4(du) + gar0
	var att_order := ["ash", "ron", "arc", "gun", "sam"]
	var def_order := ["gar", "ash", "ron", "arc", "gun", "sam"]
	var guard := 0
	while _sum4(att) > 0 and (_sum4(defw) + int(defw["gar"])) > 0 and guard < 400:
		guard += 1
		var on_def := _rh(int(att["arc"]), VAL["arc"]) + _rh(int(att["gun"]), VAL["gun"])
		var on_att := _rh(int(defw["arc"]), VAL["arc"]) + _rh(int(defw["gun"]), VAL["gun"])
		_rm(defw, on_def, def_order)
		_rm(att, on_att, att_order)
		if _sum4(att) <= 0 or (_sum4(defw) + int(defw["gar"])) <= 0:
			break
		on_def = _rh(int(att["sam"]), VAL["sam"]) + _rh(int(att["ron"]), VAL["ron"]) + _rh(int(att["ash"]), VAL["ash"])
		on_att = _rh(int(defw["sam"]), VAL["sam"]) + _rh(int(defw["ron"]), VAL["ron"]) + _rh(int(defw["ash"]) + int(defw["gar"]), VAL["ash"])
		if att_dai > 0:
			on_def += _rh(2 + att_dai, VAL["sam"])
		if def_dai > 0:
			on_att += _rh(2 + def_dai, VAL["sam"])
		_rm(defw, on_def, def_order)
		_rm(att, on_att, att_order)
	var won := (_sum4(defw) + int(defw["gar"])) <= 0
	if won:
		dp["units"] = {"ash": int(att["ash"]), "arc": int(att["arc"]), "gun": int(att["gun"]), "sam": int(att["sam"]), "ron": int(att["ron"])}
		dp["owner"] = attacker
		dp["daimyo"] = min(att_dai + 1, DAIMYO_MAX) if att_dai > 0 else 0
		_sync(dp)
		_log("%s seized %s from %s." % [_clan_name(attacker), dp["name"], _clan_name(def_owner)])
		if def_dai > 0:
			_log("%s's daimyō fell at %s!" % [_clan_name(def_owner), dp["name"]])
		if att_dai > 0 and att_dai + 1 <= DAIMYO_MAX:
			_log("%s's victorious daimyō rises to Lv %d." % [_clan_name(attacker), att_dai + 1])
		if def_owner != null and _count(def_owner) == 0:
			_log("The %s clan has been destroyed!" % _clan_name(def_owner))
	else:
		var home: Dictionary = ap["units"]
		for k in UNIT_KEYS:
			home[k] += int(att[k])
		if att_dai > 0:
			if _sum4(att) > 0:
				ap["daimyo"] = att_dai
			else:
				_log("%s's daimyō was slain assaulting %s." % [_clan_name(attacker), dp["name"]])
		_sync(ap)
		dp["units"] = {"ash": int(defw["ash"]), "arc": int(defw["arc"]), "gun": int(defw["gun"]), "sam": int(defw["sam"]), "ron": int(defw["ron"])}
		if def_dai > 0:
			dp["daimyo"] = min(def_dai + 1, DAIMYO_MAX)
		_sync(dp)
		_log("%s's assault on %s was repelled." % [_clan_name(attacker), dp["name"]])
	if attacker == _player or def_owner == _player:
		var def_end := {"ash": int(defw["ash"]), "arc": int(defw["arc"]), "gun": int(defw["gun"]), "sam": int(defw["sam"]), "ron": int(defw["ron"])}
		_modal = {
			"prov": dp["name"], "att": _clan_name(attacker), "def": _clan_name(def_owner),
			"a0": a0, "d0": d0, "gar0": gar0, "rounds": guard,
			"won": won, "by_player": attacker == _player,
			"att_start": _comp_inline(att_start), "att_surv": (_comp_inline(att) if won else "retreated " + _comp_inline(att)),
			"att_loss": _loss_str(att_start, att),
			"def_start": _comp_inline(def_start), "def_surv": ("none" if won else _comp_inline(def_end)),
			"def_loss": _loss_str(def_start, def_end),
		}
		_roll_t = 0.0


# ---------------------------------------------------------------- AI

func _ai_allocate(cid: String) -> Dictionary:
	var koku: int = int(_koku.get(cid, 3))
	var diff: String = _clans[cid].get("ai", "medium")
	var nmax := 1
	var f := 0.3
	match diff:
		"hard":
			f = 0.42
			nmax = 2
		"easy":
			f = 0.15
			nmax = 1
	var ninja := clampi(_rng.randi_range(0, nmax), 0, koku)
	var rem := koku - ninja
	var bid := int(round(rem * f)) + _rng.randi_range(-1, 1)
	bid = clampi(bid, 0, rem)
	return {"bid": bid, "ninja": ninja, "levy": rem - bid}


func _aggr(diff: String) -> int:
	match diff:
		"hard": return 0
		"easy": return 2
		_: return 1


func _ai_war_turn(cid: String) -> void:
	_ai_ninja(cid)
	_ai_deploy(cid, int(_alloc.get(cid, {}).get("levy", 0)))
	_ai_maneuver(cid)
	_expire_ronin(cid)


func _ai_deploy(cid: String, koku: int) -> void:
	var borders := []
	for pid in _owned(cid):
		if _is_border(pid):
			borders.append(pid)
	var targets: Array = borders if borders.size() > 0 else _owned(cid)
	if targets.size() == 0:
		return
	var diff: String = _clans[cid].get("ai", "medium")
	var cycle := ["ash", "sam", "ash", "arc"]
	if diff == "hard":
		cycle = ["sam", "ash", "gun", "ron", "arc"]
	var ci := 0
	var ti := 0
	var guard := 0
	while koku > 0 and guard < 400:
		guard += 1
		var t: String = cycle[ci % cycle.size()]
		ci += 1
		if int(COST[t]) <= koku:
			_provinces[targets[ti % targets.size()]]["units"][t] += 1
			_sync(_provinces[targets[ti % targets.size()]])
			koku -= int(COST[t])
			ti += 1
		elif koku < int(COST["ash"]):
			break


func _ai_maneuver(cid: String) -> void:
	var diff: String = _clans[cid].get("ai", "medium")
	for pid in _owned(cid):
		var p: Dictionary = _provinces[pid]
		if _army(p) < 2 or _moved.has(pid):
			continue
		var committed: int = _army(p) - 1
		var best := ""
		var best_margin := -9999
		for aid in p["adj"]:
			if not _provinces.has(aid):
				continue
			var ap: Dictionary = _provinces[aid]
			if ap.get("owner") == cid:
				continue
			var defv: int = _army(ap) + int(ap["castle"]) * 2
			var margin: int = committed - defv
			if margin >= _aggr(diff) and margin > best_margin:
				best_margin = margin
				best = aid
		if best != "":
			var force := _take_all_but_one(p)
			var src_dai := int(p["daimyo"])
			p["daimyo"] = 0
			_resolve_battle(pid, best, force, src_dai)
			_moved[pid] = true
			if _count(_player) == 0:
				return
		elif not _is_border(pid):
			for aid in p["adj"]:
				if _provinces.has(aid) and _provinces[aid].get("owner") == cid and _is_border(aid):
					var force2 := _take_all_but_one(p)
					var tgt: Dictionary = _provinces[aid]
					for k in UNIT_KEYS:
						tgt["units"][k] += int(force2[k])
					_sync(tgt)
					_moved[pid] = true
					break


func _check_victory() -> void:
	if _game_over:
		return
	if _count(_player) == 0:
		_game_over = true
		_result = "Defeat"
		_log("Your clan has fallen. The dream of unification ends.")
		return
	var alive := 0
	for cid in _clans:
		if _count(cid) > 0:
			alive += 1
	if _count(_player) >= WIN_PROV or alive == 1:
		_game_over = true
		_result = "Victory"
		_log("Japan bows before the %s clan. You are Shogun!" % _clan_name(_player))


# ---------------------------------------------------------------- input

func _province_at(point: Vector2) -> String:
	for pid in _provinces:
		if Geometry2D.is_point_in_polygon(point, _provinces[pid]["poly"]):
			return pid
	return ""


func _button_at(point: Vector2) -> String:
	for b in _buttons:
		if b["enabled"] and (b["rect"] as Rect2).has_point(point):
			return b["id"]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _province_at(event.position)
		if h != _hovered:
			_hovered = h
			queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _modal != null:
		if _roll_t >= 0.0:
			_roll_t = -1.0
		else:
			_modal = null
		queue_redraw()
		return
	if _show_help:
		_show_help = false
		queue_redraw()
		return
	var bid := _button_at(event.position)
	if bid != "":
		_on_button(bid)
		return
	if _game_over:
		return
	if _stage == Stage.WAR and _active() == _player:
		var hit := _province_at(event.position)
		if hit == "":
			return
		if _ninja_arm:
			var tp: Dictionary = _provinces[hit]
			if tp.get("owner") != _player and tp.get("owner") != null:
				_ninja_strike(hit)
			_ninja_arm = false
			queue_redraw()
			return
		if _war_sub == War.DEPLOY:
			_handle_deploy(hit)
		else:
			_handle_maneuver(hit)
		queue_redraw()


func _on_button(bid: String) -> void:
	match bid:
		"bid_plus": _alloc_adjust("bid", 1)
		"bid_minus": _alloc_adjust("bid", -1)
		"ninja_plus": _alloc_adjust("ninja", 1)
		"ninja_minus": _alloc_adjust("ninja", -1)
		"levy_plus": _alloc_adjust("levy", 1)
		"levy_minus": _alloc_adjust("levy", -1)
		"seal": _sealed = true
		"edit": _sealed = false
		"commit": _commit_allocation()
		"begin_war": _begin_war()
		"buy_ash": _deploy_type = "ash"
		"buy_arc": _deploy_type = "arc"
		"buy_gun": _deploy_type = "gun"
		"buy_sam": _deploy_type = "sam"
		"buy_ron": _deploy_type = "ron"
		"buy_castle": _deploy_type = "castle"
		"ninja_arm": _ninja_arm = not _ninja_arm
		"help": _show_help = not _show_help
		"diff_easy": _difficulty = "easy"
		"diff_normal": _difficulty = "normal"
		"diff_hard": _difficulty = "hard"
		"begin_campaign": _start_campaign()
		"done_deploy": _war_sub = War.MANEUVER
		"end_turn":
			_expire_ronin(_player)
			_advance_war()
		"newgame": _new_game()
	queue_redraw()


func _alloc_adjust(key: String, delta: int) -> void:
	if _sealed:
		return
	var koku: int = int(_koku.get(_player, 0))
	var remaining: int = koku - int(_shield["bid"]) - int(_shield["ninja"]) - int(_shield["levy"])
	if delta > 0 and remaining <= 0:
		return
	_shield[key] = max(0, int(_shield[key]) + delta)


func _handle_deploy(pid: String) -> void:
	var p: Dictionary = _provinces[pid]
	if p.get("owner") == _player:
		if _deploy_type == "castle":
			if _deploy_koku >= CASTLE_COST and int(p["castle"]) < CASTLE_MAX:
				p["castle"] = int(p["castle"]) + 1
				_deploy_koku -= CASTLE_COST
		elif _deploy_koku >= int(COST[_deploy_type]):
			p["units"][_deploy_type] += 1
			_sync(p)
			_deploy_koku -= int(COST[_deploy_type])
	_selected = pid


func _handle_maneuver(pid: String) -> void:
	var p: Dictionary = _provinces[pid]
	if p.get("owner") == _player and _army(p) >= 2 and not _moved.has(pid):
		_selected = pid
		return
	if _selected != "" and _provinces.has(_selected):
		var sp: Dictionary = _provinces[_selected]
		if sp.get("owner") == _player and _army(sp) >= 2 and not _moved.has(_selected) and pid in sp["adj"]:
			var force := _take_all_but_one(sp)
			if p.get("owner") == _player:
				for k in UNIT_KEYS:
					p["units"][k] += int(force[k])
				_sync(p)
				_moved[_selected] = true
				_log("Reinforced %s." % p["name"])
			else:
				var src_dai := int(sp["daimyo"])
				sp["daimyo"] = 0
				_resolve_battle(_selected, pid, force, src_dai)
				_moved[_selected] = true
				_check_victory()
			_selected = ""
			return
	_selected = pid


# ---------------------------------------------------------------- rendering

func _fill_for(p: Dictionary) -> Color:
	var owner = p.get("owner")
	if owner != null and _clans.has(owner):
		return _clans[owner]["tint"]
	return C_PARCH


func _owner_color(p: Dictionary) -> Color:
	var owner = p.get("owner")
	if owner != null and _clans.has(owner):
		return _clans[owner]["color"]
	return C_STEEL


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var c := poly.duplicate()
	if c.size() > 0:
		c.append(c[0])
	return c


func _text_centered(text: String, baseline_center: Vector2, size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, baseline_center - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _head(text: String, pos: Vector2, size: int, col: Color) -> void:
	draw_string(_font_head, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _head_centered(text: String, baseline_center: Vector2, size: int, col: Color) -> void:
	var w := _font_head.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font_head, baseline_center - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _panel(r: Rect2, fill: Color, border: Color, bw: float = 1.0, cut: float = 12.0) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := x0 + r.size.x
	var y1 := y0 + r.size.y
	var pts := PackedVector2Array([Vector2(x0, y0), Vector2(x1 - cut, y0), Vector2(x1, y0 + cut), Vector2(x1, y1), Vector2(x0, y1)])
	draw_colored_polygon(pts, fill)
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, border, bw, true)


func _draw_mon(c: Vector2, r: float, cid: String) -> void:
	var col: Color = _clans[cid]["color"]
	draw_circle(c, r, Color(0.05, 0.05, 0.05))
	draw_arc(c, r, 0.0, TAU, 28, col, maxf(1.0, r * 0.16), true)
	match cid:
		"A":
			draw_circle(c, r * 0.42, col)
			for i in 8:
				var a := i * PI / 4.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.55, c + Vector2(cos(a), sin(a)) * r * 0.82, col, maxf(1.0, r * 0.1))
		"B":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.55, 0), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.55, 0)]), col)
		"C":
			for off in [Vector2(0, -r * 0.38), Vector2(-r * 0.36, r * 0.24), Vector2(r * 0.36, r * 0.24)]:
				draw_circle(c + off, r * 0.26, col)
		"D":
			var s := r * 0.55
			draw_rect(Rect2(c.x - s, c.y - s, s * 2, s * 2), col, false, maxf(1.0, r * 0.13))
			var s2 := r * 0.3
			draw_rect(Rect2(c.x - s2, c.y - s2, s2 * 2, s2 * 2), col, true)
		"E":
			for i in 6:
				var a := i * PI / 3.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.62, col, maxf(1.0, r * 0.12))
		_:
			draw_circle(c, r * 0.4, col)


func _draw_unit_icon(t: String, c: Vector2, s: float, col: Color) -> void:
	var w := 1.8
	match t:
		"ash":  # spear
			draw_line(c + Vector2(s * 0.4, s), c + Vector2(-s * 0.4, -s), col, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.4, -s), c + Vector2(-s * 0.05, -s * 0.7), c + Vector2(-s * 0.7, -s * 0.65)]), col)
		"arc":  # bow + arrow
			draw_arc(c + Vector2(-s * 0.2, 0), s, -PI * 0.45, PI * 0.45, 10, col, w)
			draw_line(c + Vector2(-s * 0.7, 0), c + Vector2(s * 0.8, 0), col, w * 0.7)
		"gun":  # barrel + smoke
			draw_line(c + Vector2(-s, s * 0.3), c + Vector2(s * 0.5, -s * 0.2), col, w * 1.3)
			draw_circle(c + Vector2(s * 0.7, -s * 0.4), s * 0.22, col)
		"sam":  # sword
			draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, -s * 0.7), col, w)
			draw_line(c + Vector2(-s * 0.55, s * 0.2), c + Vector2(-s * 0.1, s * 0.55), col, w)
		"ron":  # crossed swords
			draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, -s * 0.7), col, w)
			draw_line(c + Vector2(s * 0.7, s * 0.7), c + Vector2(-s * 0.7, -s * 0.7), col, w)
		"dai":  # kabuto helmet
			draw_arc(c + Vector2(0, s * 0.3), s * 0.8, PI, TAU, 12, col, w)
			draw_arc(c + Vector2(0, -s * 0.35), s * 0.55, PI * 1.15, TAU * 0.92, 10, col, w)
		"castle":  # tower
			draw_rect(Rect2(c.x - s * 0.6, c.y - s * 0.3, s * 1.2, s), col, false, w)
			for dx in [-s * 0.6, -s * 0.1, s * 0.4]:
				draw_rect(Rect2(c.x + dx, c.y - s * 0.6, s * 0.3, s * 0.35), col, true)


func _draw() -> void:
	if _stage == Stage.MENU:
		_draw_menu()
		_draw_buttons()
		if _show_help:
			_draw_help()
		return
	for sy in range(int(TOP_BAR) + 14, 720 - int(BOTTOM_BAR), 24):
		draw_line(Vector2(0, sy), Vector2(1280, sy), Color(0.16, 0.22, 0.30, 0.22), 1.0)
	for pid in _provinces:
		var p: Dictionary = _provinces[pid]
		_draw_coast(p["poly"])
		draw_colored_polygon(p["poly"], _fill_for(p))
		var w := 1.4
		if pid == _hovered and _stage == Stage.WAR:
			w = 2.4
		draw_polyline(_closed(p["poly"]), C_STEEL, w, true)

	var human_war := _stage == Stage.WAR and _active() == _player and not _game_over
	if human_war and _war_sub == War.MANEUVER:
		var pa := 0.30 + 0.28 * sin(_t * 3.5)
		for pid4 in _provinces:
			var pw4: Dictionary = _provinces[pid4]
			if pw4.get("owner") == _player and _army(pw4) >= 2 and not _moved.has(pid4):
				draw_polyline(_closed(pw4["poly"]), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, pa), 1.6, true)
	if _selected != "" and _provinces.has(_selected):
		var sel: Dictionary = _provinces[_selected]
		var actionable: bool = human_war and not _ninja_arm and _war_sub == War.MANEUVER and sel.get("owner") == _player and _army(sel) >= 2 and not _moved.has(_selected)
		if actionable:
			for aid in sel["adj"]:
				if not _provinces.has(aid):
					continue
				var ap: Dictionary = _provinces[aid]
				draw_polyline(_closed(ap["poly"]), C_GOLD, 2.0, true)
				_draw_marker((sel["centroid"] + ap["centroid"]) * 0.5, ap.get("owner") != _player)
		draw_polyline(_closed(sel["poly"]), C_GOLD, 3.0, true)

	if human_war and _ninja_arm:
		for pid3 in _provinces:
			var pp: Dictionary = _provinces[pid3]
			if pp.get("owner") != _player and pp.get("owner") != null:
				draw_polyline(_closed(pp["poly"]), C_RED, 2.4, true)

	for pid2 in _provinces:
		var p2: Dictionary = _provinces[pid2]
		var tot := _army(p2)
		if tot <= 0:
			continue
		var cen: Vector2 = p2["centroid"]
		var ring := C_GOLD if int(p2["castle"]) >= 2 else C_PANEL
		draw_circle(cen + Vector2(0, 1), 13.0, Color(0, 0, 0, 0.35))
		draw_circle(cen, 12.0, _owner_color(p2))
		draw_arc(cen, 12.0, 0.0, TAU, 24, ring, 2.0, true)
		draw_arc(cen, 8.5, 0.0, TAU, 18, Color(1, 1, 1, 0.10), 1.0, true)
		_text_centered(str(tot), cen + Vector2(0, 4), 12, C_WHITE)
		if int(p2["castle"]) > 0:
			draw_rect(Rect2(cen.x + 9, cen.y - 17, 8, 8), _owner_color(p2), true)
			draw_rect(Rect2(cen.x + 9, cen.y - 17, 8, 8), C_GOLD, false, 1.0)
		if int(p2.get("daimyo", 0)) > 0:
			draw_circle(cen + Vector2(-13, -14), 7.5, C_GOLD)
			_text_centered(str(int(p2["daimyo"])), cen + Vector2(-13, -10), 11, C_PANEL)
		_text_centered(String(p2["name"]), cen + Vector2(0, 30), 10, C_LABEL)

	_draw_top_bar()
	_draw_side_panel()
	_draw_bottom_hud()
	if _stage == Stage.ALLOCATE and not _auto and not _game_over:
		_draw_shield()
	elif _stage == Stage.REVEAL and not _game_over:
		_draw_reveal()
	_draw_buttons()
	if _modal != null:
		_draw_modal()
	if _game_over:
		_draw_gameover()
	if _show_help:
		_draw_help()


func _draw_marker(pos: Vector2, enemy: bool) -> void:
	draw_circle(pos, 9.0, C_PANEL)
	if enemy:
		draw_arc(pos, 9.0, 0.0, TAU, 18, C_RED, 1.6, true)
		draw_line(pos + Vector2(-3.4, -3.4), pos + Vector2(3.4, 3.4), C_REDLT, 1.8, true)
		draw_line(pos + Vector2(3.4, -3.4), pos + Vector2(-3.4, 3.4), C_REDLT, 1.8, true)
	else:
		draw_arc(pos, 9.0, 0.0, TAU, 18, C_STEEL, 1.6, true)
		draw_polyline(PackedVector2Array([
			pos + Vector2(-3.5, 0), pos + Vector2(2.5, 0),
			pos + Vector2(-0.5, -3), pos + Vector2(3, 0), pos + Vector2(-0.5, 3),
		]), C_PARCH, 1.5, true)


func _draw_top_bar() -> void:
	draw_rect(Rect2(0, 0, 1280, TOP_BAR), C_PANEL, true)
	draw_rect(Rect2(0, TOP_BAR - 2, 1280, 2), C_GOLD, true)
	_head("ROUND %d" % _round, Vector2(16, 35), 15, C_STEEL)
	var cid := _active()
	draw_rect(Rect2(470, 16, 4, 24), _clans[cid]["color"], true)
	var who := ""
	match _stage:
		Stage.ALLOCATE: who = "Secret allocation — all clans bid at once"
		Stage.REVEAL: who = "The bids are revealed…"
		Stage.WAR:
			who = "%s — your war turn" % _clans[cid]["name"] if cid == _player else "%s marches…" % _clans[cid]["name"]
	draw_string(_font, Vector2(484, 35), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_PARCH)
	if _stage == Stage.WAR and cid == _player and not _game_over:
		if _war_sub == War.DEPLOY:
			draw_string(_font, Vector2(1280 - 400, 35), "Deploy koku  %d   ·   placing %s" % [_deploy_koku, _type_name(_deploy_type)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_GOLD)
		else:
			draw_string(_font, Vector2(1280 - 200, 35), "Phase  Maneuver", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_GOLD)


func _draw_side_panel() -> void:
	var x := 14.0
	var y := TOP_BAR + 12.0
	if _selected != "" and _provinces.has(_selected):
		var p: Dictionary = _provinces[_selected]
		_panel(Rect2(x, y, 250, 150), C_PANEL, C_IRON, 1.0, 12.0)
		_head("SELECTED PROVINCE", Vector2(x + 14, y + 24), 11, C_STEEL)
		_head(String(p["name"]), Vector2(x + 14, y + 54), 22, C_PARCH)
		var owner = p.get("owner")
		var oname := "Unclaimed"
		if owner != null:
			oname = _clans[owner]["name"] + (" (you)" if owner == _player else " clan")
		if int(p["daimyo"]) > 0:
			oname += "  ·  ⚑ Daimyō Lv %d" % int(p["daimyo"])
		draw_rect(Rect2(x + 14, y + 66, 14, 14), _owner_color(p), true)
		draw_string(_font, Vector2(x + 34, y + 78), oname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_PARCH)
		var cl := int(p["castle"])
		var castle_txt: String = ("Lv %d · +%d garrison" % [cl, cl * 2]) if cl > 0 else "none"
		draw_string(_font, Vector2(x + 14, y + 102), "Army %d    Castle: %s" % [_army(p), castle_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_PARCH)
		draw_string(_font, Vector2(x + 14, y + 126), _comp_str(p), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_STEEL)
	var ly := y + 164.0
	_panel(Rect2(x, ly, 250, 140), C_PANEL, C_IRON, 1.0, 12.0)
	_head("DISPATCHES", Vector2(x + 14, ly + 22), 11, C_STEEL)
	var ey := ly + 42.0
	for e in _events:
		for line in _wrap(e, 222, 12):
			draw_string(_font, Vector2(x + 14, ey), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_PARCH)
			ey += 16.0


func _wrap(text: String, max_w: float, size: int) -> Array:
	var lines := []
	var cur := ""
	for wd in text.split(" "):
		var trial := wd if cur == "" else cur + " " + wd
		if _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w and cur != "":
			lines.append(cur)
			cur = wd
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	return lines


func _draw_bottom_hud() -> void:
	draw_rect(Rect2(0, 720 - BOTTOM_BAR, 1280, BOTTOM_BAR), C_IRON, true)
	draw_rect(Rect2(0, 720 - BOTTOM_BAR, 1280, 2), C_GOLD, true)
	var ids := _clans.keys()
	var slot_w := 1280.0 / float(ids.size())
	for i in ids.size():
		var cid: String = ids[i]
		var sx := slot_w * i
		var cy := 720.0 - BOTTOM_BAR
		var alive := _count(cid) > 0
		if cid == _active() and not _game_over and _stage == Stage.WAR:
			draw_rect(Rect2(sx, cy, slot_w, BOTTOM_BAR), Color(0.20, 0.22, 0.25), true)
			draw_rect(Rect2(sx, cy, slot_w, 2), _clans[cid]["color"], true)
		var center := Vector2(sx + 24, cy + BOTTOM_BAR * 0.5)
		if alive:
			_draw_mon(center, 11.0, cid)
		else:
			draw_circle(center, 11.0, C_STEEL)
		var nm: String = _clans[cid]["name"] + ("" if alive else " ✕")
		if cid == _ninja_holder and alive:
			nm += "  ⚔"
		draw_string(_font_head, Vector2(sx + 44, cy + 28), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_PARCH if cid == _player else C_STEEL)
		var aitag: String = "" if cid == _player else "  · " + String(_clans[cid].get("ai", ""))
		draw_string(_font, Vector2(sx + 38, cy + 48), "%d prov%s" % [_count(cid), aitag], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_GOLD)


func _draw_shield() -> void:
	draw_rect(Rect2(0, TOP_BAR, 1280, 720 - TOP_BAR - BOTTOM_BAR), C_DIM, true)
	var pw := 700.0
	var ph := 300.0
	var px := (1280 - pw) * 0.5
	var py := (720 - ph) * 0.5
	_panel(Rect2(px, py, pw, ph), C_PANEL, _clans[_player]["color"], 1.6, 16.0)
	_head_centered("SECRET ALLOCATION", Vector2(px + pw * 0.5, py + 36), 20, C_GOLD)
	var koku: int = int(_koku.get(_player, 0))
	var remaining: int = koku - int(_shield["bid"]) - int(_shield["ninja"]) - int(_shield["levy"])
	_text_centered("Koku: %d        Remaining: %d" % [koku, remaining], Vector2(px + pw * 0.5, py + 62), 14, C_PARCH if remaining >= 0 else C_REDLT)
	if _sealed:
		_text_centered("SEALED — review, then commit (or edit).", Vector2(px + pw * 0.5, py + 210), 15, C_STEEL)
		draw_string(_font, Vector2(px + 110, py + 110), "Turn-order bid:  %d koku" % int(_shield["bid"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_GOLD)
		draw_string(_font, Vector2(px + 110, py + 146), "Ninja bid:       %d koku" % int(_shield["ninja"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_GOLD)
		draw_string(_font, Vector2(px + 110, py + 182), "Levy budget:     %d koku" % int(_shield["levy"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_GOLD)
	else:
		_shield_row("Turn-order bid", "(highest goes first)", int(_shield["bid"]), px, py + 96)
		_shield_row("Ninja bid", "(highest wins the ninja)", int(_shield["ninja"]), px, py + 146)
		_shield_row("Levy budget", "(spend on troops in war)", int(_shield["levy"]), px, py + 196)
	_text_centered("“%s”  — Sun Tzu" % AOW_DECEPTION, Vector2(px + pw * 0.5, py + ph - 14), 12, C_GOLD)


func _shield_row(label: String, sub: String, value: int, px: float, ry: float) -> void:
	draw_string(_font, Vector2(px + 60, ry + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_PARCH)
	draw_string(_font, Vector2(px + 60, ry + 24), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_STEEL)
	_text_centered(str(value), Vector2(px + 380, ry + 12), 20, C_GOLD)


func _draw_reveal() -> void:
	draw_rect(Rect2(0, TOP_BAR, 1280, 720 - TOP_BAR - BOTTOM_BAR), C_DIM, true)
	var pw := 540.0
	var ph := 92.0 + _order.size() * 34.0
	var px := (1280 - pw) * 0.5
	var py := (720 - ph) * 0.5
	_panel(Rect2(px, py, pw, ph), C_PANEL, C_GOLD, 1.6, 14.0)
	_head_centered("TURN ORDER", Vector2(px + pw * 0.5, py + 34), 18, C_GOLD)
	var ry := py + 62.0
	for i in _order.size():
		var cid: String = _order[i]
		var b: int = int(_alloc.get(cid, {}).get("bid", 0))
		var nb: int = int(_alloc.get(cid, {}).get("ninja", 0))
		_draw_mon(Vector2(px + 40, ry - 4), 9.0, cid)
		var label := "%d.  %s%s" % [i + 1, _clans[cid]["name"], "  (you)" if cid == _player else ""]
		draw_string(_font, Vector2(px + 60, ry), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_PARCH if cid == _player else C_STEEL)
		draw_string(_font, Vector2(px + pw - 200, ry), "bid %d · ninja %d" % [b, nb], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_GOLD)
		ry += 34.0
	var nh := ("Ninja → %s" % _clan_name(_ninja_holder)) if _ninja_holder != "" else "Ninja → unhired this round"
	_text_centered(nh, Vector2(px + pw * 0.5, ry + 8), 14, C_REDLT)


func _draw_buttons() -> void:
	_buttons = []
	_add_button("help", Rect2(1240, 14, 28, 28), "?", true, _show_help)
	if _stage == Stage.MENU:
		var dn := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
		var bx := 433.0
		for d in ["easy", "normal", "hard"]:
			_add_button("diff_" + d, Rect2(bx, 504, 130, 40), dn[d], true, _difficulty == d)
			bx += 142.0
		_add_button("begin_campaign", Rect2(540, 564, 200, 48), "Begin Campaign →", true, true)
	elif _game_over:
		_add_button("newgame", Rect2(1040, 560, 210, 44), "New game", true, true)
	elif _stage == Stage.ALLOCATE and not _auto:
		var pw := 700.0
		var px := (1280 - pw) * 0.5
		var py := (720 - 300.0) * 0.5
		if _sealed:
			_add_button("edit", Rect2(px + 360, py + 248, 130, 34), "← Edit", true, false)
			_add_button("commit", Rect2(px + 510, py + 248, 150, 34), "Commit ✓", true, true)
		else:
			_add_button("bid_minus", Rect2(px + 340, py + 100, 30, 30), "–", true, false)
			_add_button("bid_plus", Rect2(px + 416, py + 100, 30, 30), "+", true, false)
			_add_button("ninja_minus", Rect2(px + 340, py + 150, 30, 30), "–", true, false)
			_add_button("ninja_plus", Rect2(px + 416, py + 150, 30, 30), "+", true, false)
			_add_button("levy_minus", Rect2(px + 340, py + 200, 30, 30), "–", true, false)
			_add_button("levy_plus", Rect2(px + 416, py + 200, 30, 30), "+", true, false)
			_add_button("seal", Rect2(px + 500, py + 250, 150, 34), "Seal →", true, true)
	elif _stage == Stage.REVEAL and not _auto:
		var pw2 := 540.0
		var ph2 := 92.0 + _order.size() * 34.0
		_add_button("begin_war", Rect2((1280 - pw2) * 0.5 + pw2 - 170, (720 - ph2) * 0.5 + ph2 - 46, 150, 34), "Begin war →", true, true)
	elif _stage == Stage.WAR and _active() == _player and _modal == null:
		if _ninja_holder == _player and not _ninja_used:
			var lbl := "Ninja: pick target" if _ninja_arm else "Send ninja ⚔"
			_add_button("ninja_arm", Rect2(1040, 70, 210, 36), lbl, true, _ninja_arm)
		if _war_sub == War.DEPLOY:
			_head("UNIT GUIDE — %s" % _type_name(_deploy_type), Vector2(1042, 130), 13, C_GOLD)
			var dy := 150.0
			for line in _wrap(UNIT_DESC[_deploy_type], 212, 12):
				draw_string(_font, Vector2(1042, dy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_PARCH)
				dy += 15.0
			draw_string(_font, Vector2(1042, 252), "DEPLOY — pick a type, click a province", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_STEEL)
			var by := 266.0
			for k in UNIT_KEYS:
				_add_button("buy_" + k, Rect2(1040, by, 210, 34), "%s  (%d koku)" % [UNIT_NAME[k], COST[k]], true, _deploy_type == k)
				by += 38.0
			_add_button("buy_castle", Rect2(1040, by, 210, 34), "Castle  (%d koku)" % CASTLE_COST, true, _deploy_type == "castle")
			by += 38.0
			_add_button("done_deploy", Rect2(1040, by + 6, 210, 40), "Done deploying →", true, true)
		else:
			_add_button("end_turn", Rect2(1040, 560, 210, 44), "End turn →", true, true)
	for b in _buttons:
		var r: Rect2 = b["rect"]
		var primary: bool = b["primary"]
		_panel(r, C_GOLD if primary else C_PANEL2, C_GOLD, 1.2, 6.0)
		var lblcol := C_PANEL if primary else C_GOLD
		var bids := String(b["id"])
		if bids.begins_with("buy_"):
			_draw_unit_icon(bids.substr(4), Vector2(r.position.x + 20, r.position.y + r.size.y * 0.5), 9.0, lblcol)
		_text_centered(String(b["label"]), Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 5), 13, lblcol)


func _add_button(id: String, rect: Rect2, label: String, enabled: bool, primary: bool) -> void:
	_buttons.append({"id": id, "rect": rect, "label": label, "enabled": enabled, "primary": primary})


func _draw_modal() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), C_DIM, true)
	var w := 540.0
	var h := 340.0
	var x := (1280 - w) * 0.5
	var y := (720 - h) * 0.5
	_panel(Rect2(x, y, w, h), C_PANEL, C_GOLD, 1.6, 14.0)
	var m: Dictionary = _modal
	_head_centered("BATTLE FOR %s" % String(m["prov"]).to_upper(), Vector2(x + w * 0.5, y + 36), 16, C_STEEL)
	if _roll_t >= 0.0:
		var n := int(_roll_t * 36.0) % 12 + 1
		_head_centered("⚔  %d  ⚔" % n, Vector2(x + w * 0.5, y + h * 0.5 - 6), 46, C_GOLD)
		_text_centered("the dice fall…", Vector2(x + w * 0.5, y + h * 0.5 + 34), 13, C_STEEL)
		_text_centered("click to skip", Vector2(x + w * 0.5, y + h - 16), 12, C_STEEL)
		return
	_text_centered("%d rounds of fire and steel" % int(m["rounds"]), Vector2(x + w * 0.5, y + 54), 11, C_STEEL)
	var verdict := ""
	if m["by_player"]:
		verdict = "Victory — the province is yours!" if m["won"] else "Repelled — your assault failed."
	else:
		verdict = "Your defenders held!" if not m["won"] else "The enemy overran your defenders."
	var vc := C_GOLD if (m["won"] == m["by_player"]) else C_REDLT
	_text_centered(verdict, Vector2(x + w * 0.5, y + 66), 18, vc)
	var lx := x + 34
	var ly := y + 104
	draw_string(_font, Vector2(lx, ly), "ATTACKER — %s (%d)" % [m["att"], int(m["a0"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_GOLD)
	draw_string(_font, Vector2(lx + 16, ly + 24), "fielded: %s" % m["att_start"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_PARCH)
	draw_string(_font, Vector2(lx + 16, ly + 46), "lost: %s" % m["att_loss"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_REDLT)
	draw_string(_font, Vector2(lx + 16, ly + 68), "survivors: %s" % m["att_surv"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_STEEL)
	var dy := ly + 100
	var dstart: String = m["def_start"]
	if int(m["gar0"]) > 0:
		dstart += "  (+%d castle garrison)" % int(m["gar0"])
	draw_string(_font, Vector2(lx, dy), "DEFENDER — %s (%d)" % [m["def"], int(m["d0"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_GOLD)
	draw_string(_font, Vector2(lx + 16, dy + 24), "fielded: %s" % dstart, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_PARCH)
	draw_string(_font, Vector2(lx + 16, dy + 46), "lost: %s" % m["def_loss"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_REDLT)
	draw_string(_font, Vector2(lx + 16, dy + 68), "survivors: %s" % m["def_surv"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_STEEL)
	_text_centered("click to continue", Vector2(x + w * 0.5, y + h - 16), 12, C_STEEL)


func _draw_help() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), C_DIM, true)
	var w := 680.0
	var h := 588.0
	var x := (1280 - w) * 0.5
	var y := (720 - h) * 0.5
	_panel(Rect2(x, y, w, h), C_PANEL, C_GOLD, 1.6, 16.0)
	_head_centered("FIELD GUIDE", Vector2(x + w * 0.5, y + 32), 20, C_GOLD)
	var lx := x + 30
	var ly := y + 56.0
	for k in ["ash", "arc", "gun", "sam", "ron", "dai", "castle"]:
		var head := ""
		if k == "castle":
			head = "Castle  (%d koku to build)" % CASTLE_COST
		elif k == "dai":
			head = "Daimyō (general)"
		else:
			head = "%s  (%d koku)" % [UNIT_NAME[k], COST[k]]
		_draw_unit_icon(k, Vector2(lx + 9, ly - 5), 8.0, C_GOLD)
		_head(head, Vector2(lx + 26, ly), 14, C_GOLD)
		ly += 18.0
		for line in _wrap(UNIT_DESC[k], w - 60, 12):
			draw_string(_font, Vector2(lx + 12, ly), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_PARCH)
			ly += 15.0
		ly += 5.0
	ly += 2.0
	var flow := "Each round: bid koku for turn order and the ninja, then a levy budget. The ninja holder may attempt one assassination (d12 of 8 or less) on any enemy province. In battle: Archers & Gunners fire first (ranged), then Samurai, Ronin, Ashigaru & the castle garrison clash (melee). Win by holding 10 provinces, or being the last clan standing."
	for line in _wrap(flow, w - 60, 12):
		draw_string(_font, Vector2(lx, ly), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_STEEL)
		ly += 15.0
	_text_centered("click anywhere to close", Vector2(x + w * 0.5, y + h - 14), 12, C_STEEL)


func _draw_gameover() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), C_DIM, true)
	var col := C_GOLD if _result == "Victory" else C_REDLT
	_head_centered(_result.to_upper(), Vector2(640, 312), 64, col)
	_text_centered("Round %d · %d provinces held" % [_round, _count(_player)], Vector2(640, 364), 18, C_PARCH)
	var q: String = AOW_VICTORY if _result == "Victory" else AOW_DEFEAT
	var qy := 408.0
	for line in _wrap("“" + q + "”", 760, 16):
		_text_centered(line, Vector2(640, qy), 16, C_PARCH)
		qy += 23.0
	_text_centered("— Sun Tzu, The Art of War", Vector2(640, qy + 4), 12, C_GOLD)


func _draw_coast(poly: PackedVector2Array) -> void:
	draw_polyline(_closed(poly), Color(0.04, 0.07, 0.11), 4.0, true)


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.05), true)
	draw_rect(Rect2(0, 0, 1280, 3), C_GOLD, true)
	draw_rect(Rect2(0, 717, 1280, 3), C_GOLD, true)
	_draw_mon(Vector2(640, 176), 64.0 + sin(_t * 1.6) * 4.0, _player)
	_head_centered("SENGOKU", Vector2(640, 308), 64, C_GOLD)
	_head_centered("WAY OF THE SWORD", Vector2(640, 348), 22, C_PARCH)
	_text_centered("A digital homage to the Samurai Swords board game", Vector2(640, 380), 13, C_STEEL)
	var qy := 414.0
	for line in _wrap("“" + AOW_MENU + "”", 720, 15):
		_text_centered(line, Vector2(640, qy), 15, C_PARCH)
		qy += 21.0
	_text_centered("— Sun Tzu, The Art of War", Vector2(640, qy + 4), 12, C_GOLD)
	_head_centered("KNOW YOUR ENEMY", Vector2(640, 488), 13, C_STEEL)
	_text_centered("Click ? at any time for the field guide.", Vector2(640, 624), 12, C_STEEL)


# ---------------------------------------------------------------- data + dev

func _compute_transform() -> void:
	var vp := Vector2(1280, 720)
	_scale = min((vp.x - 48.0) / DESIGN_W, (vp.y - TOP_BAR - BOTTOM_BAR - 16.0) / DESIGN_H)
	var map_w := DESIGN_W * _scale
	var map_h := DESIGN_H * _scale
	_offset = Vector2((vp.x - map_w) * 0.5, TOP_BAR + ((vp.y - TOP_BAR - BOTTOM_BAR) - map_h) * 0.5)


func _to_screen(p: Vector2) -> Vector2:
	return Vector2(p.x * _scale + _offset.x, p.y * _scale + _offset.y)


func _load_data() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("provinces.json did not parse to a dictionary")
		return
	var data: Dictionary = parsed
	_player = data.get("player", "A")
	_clans = {}
	var ai_levels := {"B": "hard", "C": "medium", "D": "medium", "E": "easy"}
	for cid in data.get("clans", {}).keys():
		var c: Dictionary = data["clans"][cid]
		var col: Array = c["color"]
		var tnt: Array = c["tint"]
		_clans[cid] = {
			"name": c["name"],
			"color": Color(col[0], col[1], col[2]),
			"tint": Color(tnt[0], tnt[1], tnt[2]),
			"ai": ai_levels.get(cid, "medium"),
		}
	_provinces = {}
	for pid in data.get("provinces", {}).keys():
		var p: Dictionary = data["provinces"][pid]
		var poly := PackedVector2Array()
		for pt in p["points"]:
			poly.append(_to_screen(Vector2(pt[0], pt[1])))
		var cen: Array = p["centroid"]
		var n := int(p.get("army", 0))
		var sam := int(n / 5)
		var arc := int(n / 5)
		var units := {"ash": n - sam - arc, "arc": arc, "gun": 0, "sam": sam, "ron": 0}
		_provinces[pid] = {
			"name": p["name"], "poly": poly, "centroid": _to_screen(Vector2(cen[0], cen[1])),
			"owner": p.get("owner"), "units": units, "army": n, "daimyo": 0,
			"castle": int(p.get("castle", 0)), "adj": p.get("adj", []),
		}


func _run_autoplay() -> void:
	_auto = true
	var guard := 0
	while not _game_over and guard < 10000:
		guard += 1
		match _stage:
			Stage.ALLOCATE:
				_alloc[_player] = _ai_allocate(_player)
				_do_reveal()
			Stage.REVEAL:
				_begin_war()
			_:
				_begin_round()
	var tally := []
	for cid in _clans:
		tally.append("%s=%d" % [_clans[cid]["name"], _count(cid)])
	print("AUTOPLAY done: result=%s round=%d guard=%d [%s]" % [_result, _round, guard, ", ".join(tally)])
	get_tree().quit()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.preview_shot.png")
	get_tree().quit()
