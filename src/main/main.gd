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
const SAVE_PATH := "user://sengoku_save.json"
const DESIGN_W := 1000.0
const DESIGN_H := 760.0
const TOP_BAR := 56.0
const BOTTOM_BAR := 64.0
const WIN_PROV := 24
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
	"dai": "Daimyō (general) — leads an army into battle, adding several elite attacks. Each attack it launches from a province carries it forward; victories level it up (to Lv 3). It dies if its army is wiped out or its province is captured. You start with two — and if your LAST daimyō falls, your clan is eliminated and its lands pass to the conqueror. Guard them, and hunt the enemy's.",
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
const C_GREEN := Color(0.431, 0.659, 0.361)
const C_AMBER := Color(0.847, 0.651, 0.271)
const C_RISK := Color(0.780, 0.318, 0.282)
const ODDS_TRIALS := 200
const C_SEA2 := Color(0.071, 0.118, 0.165)   # deeper sea for the vignette
const C_INK := Color(0.094, 0.122, 0.157)    # coastline ink
const C_BORDER := Color(0.353, 0.337, 0.286) # muted land border
# Parchment shading per historical region, so neutral land reads by area.
const REGION_TINT := {
	"Kinai": Color(0.890, 0.835, 0.624),
	"Kantō": Color(0.871, 0.812, 0.663),
	"Tōkai": Color(0.878, 0.800, 0.651),
	"Chūbu": Color(0.792, 0.804, 0.659),
	"Hokuriku": Color(0.804, 0.824, 0.749),
	"Tōhoku": Color(0.820, 0.812, 0.722),
	"Chūgoku": Color(0.878, 0.792, 0.643),
	"Shikoku": Color(0.855, 0.792, 0.682),
	"Kyūshū": Color(0.886, 0.804, 0.620),
	"Ezo": Color(0.800, 0.835, 0.816),
}

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
var _ninja_spy_arm: bool = false
var _scouted: Dictionary = {}
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
var _map_min: Vector2 = Vector2.ZERO
var _map_max: Vector2 = Vector2(DESIGN_W, DESIGN_H)
var _region_cen: Dictionary = {}
var _zoom: float = 1.0
var _focus: Vector2 = Vector2.ZERO
var _map_rect: Rect2 = Rect2()
var _panning: bool = false
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _roll_t := -1.0
var _odds_cache: Dictionary = {}
var _odds_for: String = "__none__"


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
		_selected = _owned(_player)[0]
		await _shoot()
		return
	if "--shotodds" in args:
		_order = _clans.keys()
		_war_idx = _order.find(_player)
		_stage = Stage.WAR
		_war_sub = War.MANEUVER
		_selected = _owned(_player)[0]
		for aid in _provinces[_selected]["adj"]:
			if _provinces.has(aid) and _provinces[aid].get("owner") != _player:
				_hovered = aid
				break
		await _shoot()
		return
	if "--testsave" in args:
		var home: String = _owned(_player)[0]
		var enemy: String = _owned("B")[0]
		_stage = Stage.WAR
		_war_sub = War.MANEUVER
		_round = 7
		_provinces[home]["castle"] = 3
		_provinces[home]["units"]["sam"] = 9
		_sync(_provinces[home])
		_scouted[enemy] = true
		_save_game()
		_provinces[home]["castle"] = 0
		_provinces[home]["units"]["sam"] = 0
		_round = 0
		_scouted = {}
		_load_game()
		var ok: bool = int(_provinces[home]["castle"]) == 3 and int(_provinces[home]["units"]["sam"]) == 9 and _round == 7 and _scouted.has(enemy) and _stage == Stage.WAR
		print("SAVELOAD test: ok=%s castle=%d sam=%d round=%d scouted=%s stage=%d" % [ok, int(_provinces[home]["castle"]), int(_provinces[home]["units"]["sam"]), _round, _scouted.has(enemy), _stage])
		get_tree().quit()
		return
	if "--shotzoom" in args:
		_order = _clans.keys()
		_war_idx = _order.find(_player)
		_stage = Stage.WAR
		_war_sub = War.MANEUVER
		_selected = _owned(_player)[0]
		_zoom = 2.6
		_focus = _provinces[_selected]["centroid"]
		_clamp_focus()
		await _shoot()
		return
	if "--shotfog" in args:
		_order = _clans.keys()
		_war_idx = _order.find(_player)
		_stage = Stage.WAR
		_war_sub = War.MANEUVER
		_selected = _owned("B")[0]
		_ninja_holder = _player
		_ninja_spy_arm = true
		await _shoot()
		return
	if "--shotbattle" in args:
		_order = _clans.keys()
		_war_idx = 0
		_stage = Stage.WAR
		var src: String = _owned(_player)[0]
		var tgt := ""
		for aid in _provinces[src]["adj"]:
			if _provinces.has(aid) and _provinces[aid].get("owner") != _player:
				tgt = aid
				break
		var force := _take_all_but_one(_provinces[src])
		_resolve_battle(src, tgt, force)
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
	_ninja_arm = false
	_ninja_spy_arm = false
	_scouted = {}
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


## Enemy provinces hide their unit breakdown (the total stays visible) until a ninja scouts
## them. Your own and neutral provinces are always legible.
func _is_fogged(pid: String) -> bool:
	if _scouted.has(pid):
		return false
	var o = _provinces[pid].get("owner")
	return o != null and o != _player


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
	var _home := _owned(_player)
	if _home.size() > 0:
		_selected = _home[0]
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


## How many of a clan's provinces still hold a daimyō. Reaching zero eliminates the clan.
func _daimyo_count(cid: String) -> int:
	var n := 0
	for pid in _provinces:
		var p: Dictionary = _provinces[pid]
		if p.get("owner") == cid and int(p.get("daimyo", 0)) > 0:
			n += 1
	return n


## Transfers every remaining province of [param cid] to [param slayer] (or to neutral if
## the slayer is null), then logs the clan's fall. Called the instant a clan loses its
## last daimyō — the iconic Samurai Swords elimination rule.
func _eliminate_clan(cid: String, slayer) -> void:
	var lands := _owned(cid)
	var to_clan: bool = slayer != null and _clans.has(slayer) and slayer != cid
	for pid in lands:
		_provinces[pid]["owner"] = slayer if to_clan else null
		_sync(_provinces[pid])
	if to_clan:
		_log("%s's last daimyō has fallen — the clan is eliminated, and %s claims its %d provinces." % [_clan_name(cid), _clan_name(slayer), lands.size()])
	else:
		_log("%s's last daimyō has fallen — the leaderless clan scatters." % _clan_name(cid))


## Warn the human the moment they are reduced to a single daimyō, so sudden elimination
## never comes without notice.
func _maybe_warn_last_daimyo(cid) -> void:
	if cid == _player and _count(cid) > 0 and _daimyo_count(cid) == 1:
		_log("⚠ Only one daimyō remains to you — if it falls, your clan falls with it.")


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
	_dirty_odds()
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


## Ninja SPY — the holder's alternative to assassination. Permanently reveals a province's
## troop composition (lifts the fog), and is consumed like a strike (one ninja act per round).
func _ninja_spy(target_id: String) -> void:
	if _ninja_used:
		return
	var p: Dictionary = _provinces[target_id]
	if p.get("owner") == _ninja_holder or p.get("owner") == null:
		return
	_ninja_used = true
	_ninja_spy_arm = false
	_scouted[target_id] = true
	_log("%s's ninja scouted %s — %s." % [_clan_name(_ninja_holder), p["name"], _comp_inline(p["units"])])


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
	var guard := _simulate(att, defw, att_dai, def_dai)
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
		if def_owner != null and _count(def_owner) > 0 and _daimyo_count(def_owner) == 0:
			_eliminate_clan(def_owner, attacker)
		elif def_owner != null and _count(def_owner) == 0:
			_log("The %s clan has been destroyed!" % _clan_name(def_owner))
		elif def_dai > 0:
			_maybe_warn_last_daimyo(def_owner)
	else:
		var home: Dictionary = ap["units"]
		for k in UNIT_KEYS:
			home[k] += int(att[k])
		if att_dai > 0:
			if _sum4(att) > 0:
				ap["daimyo"] = att_dai
			else:
				_log("%s's daimyō was slain assaulting %s." % [_clan_name(attacker), dp["name"]])
				if attacker != null and _count(attacker) > 0 and _daimyo_count(attacker) == 0:
					_eliminate_clan(attacker, def_owner)
				else:
					_maybe_warn_last_daimyo(attacker)
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


## Runs the faithful ranged→melee combat loop in place, mutating [param att] and
## [param defw] (which carries a "gar" garrison key) down to survivors. Returns the
## number of rounds fought. Single source of truth for both real battles and the
## odds preview, so the preview can never drift from how combat actually resolves.
func _simulate(att: Dictionary, defw: Dictionary, att_dai: int, def_dai: int) -> int:
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
	return guard


## The force a maneuver would commit: the whole army minus one unit left behind,
## matching [method _take_all_but_one] without mutating the province.
func _committed_comp(p: Dictionary) -> Dictionary:
	var c := (p["units"] as Dictionary).duplicate()
	for k in UNIT_KEYS:
		if int(c[k]) > 0:
			c[k] -= 1
			break
	return c


## Monte-Carlo estimate of an attack from [param src_id] into [param def_id], by
## running the real combat sim ODDS_TRIALS times. Returns win %, force sizes, and
## a risk band ("favorable" / "even" / "risky").
func _attack_odds(src_id: String, def_id: String) -> Dictionary:
	var sp: Dictionary = _provinces[src_id]
	var dp: Dictionary = _provinces[def_id]
	var att_dai := int(sp["daimyo"])
	var def_dai := int(dp["daimyo"])
	var gar0 := int(dp["castle"]) * 2
	var committed := _committed_comp(sp)
	var du: Dictionary = dp["units"]
	var wins := 0
	for i in ODDS_TRIALS:
		var att := committed.duplicate()
		var defw := {"ash": int(du["ash"]), "arc": int(du["arc"]), "gun": int(du["gun"]), "sam": int(du["sam"]), "ron": int(du["ron"]), "gar": gar0}
		_simulate(att, defw, att_dai, def_dai)
		if (_sum4(defw) + int(defw["gar"])) <= 0:
			wins += 1
	var pct := int(round(100.0 * wins / ODDS_TRIALS))
	var band := "risky"
	if pct >= 70:
		band = "favorable"
	elif pct >= 45:
		band = "even"
	return {"pct": pct, "att": _sum4(committed), "def": _sum4(du) + gar0, "gar": gar0, "band": band, "dai": att_dai > 0}


## Rebuild the cached odds for every enemy province adjacent to the selected army,
## but only when the selection (or game state via [method _dirty_odds]) has changed —
## the Monte-Carlo sims are far too costly to run every frame.
func _ensure_odds() -> void:
	if _odds_for == _selected:
		return
	_odds_for = _selected
	_odds_cache = {}
	if _selected == "" or not _provinces.has(_selected):
		return
	var sp: Dictionary = _provinces[_selected]
	if sp.get("owner") != _player or _army(sp) < 2 or _moved.has(_selected):
		return
	for aid in sp["adj"]:
		if _provinces.has(aid) and _provinces[aid].get("owner") != _player:
			_odds_cache[aid] = _attack_odds(_selected, aid)


## Force the next [method _ensure_odds] to recompute even if the selection is unchanged
## (e.g. after a ninja strike alters an enemy garrison).
func _dirty_odds() -> void:
	_odds_for = "__dirty__"


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
	# Personality reshapes how koku is split between initiative, the ninja, and the levy.
	match _clans[cid].get("persona", "opportunist"):
		"aggressive": f *= 0.6           # pour koku into the levy and attack
		"defensive": f *= 0.8            # modest bids, save for troops + castles
		"economic": f *= 0.6             # hoard buying power for cheap mass
		"opportunist":
			nmax += 1                    # prizes the ninja
			f *= 1.15
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


## Aggression threshold combining the clan's difficulty (skill) with its personality
## (temperament). Lower = attacks on slimmer margins.
func _aggr_for(cid: String) -> int:
	var base := _aggr(_clans[cid].get("ai", "medium"))
	match _clans[cid].get("persona", "opportunist"):
		"aggressive": return maxi(0, base - 1)
		"defensive": return base + 2
		"economic": return base + 1
		_: return base


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
	var persona: String = _clans[cid].get("persona", "opportunist")
	# Each temperament buys a different army: brawlers favor elite melee, turtles favor
	# ranged + fodder, economists buy cheap mass, opportunists stay flexible.
	var cycle := ["ash", "sam", "ash", "arc"]
	match persona:
		"aggressive": cycle = ["sam", "ron", "ash", "gun"]
		"defensive": cycle = ["ash", "arc", "ash", "gun"]
		"economic": cycle = ["ash", "ash", "arc"]
		"opportunist": cycle = ["sam", "arc", "ash", "gun"]
	if diff == "hard":
		cycle = cycle + ["gun"]
	# A turtle spends first on raising a fortress where it can.
	if persona == "defensive" and koku >= CASTLE_COST:
		for pid in targets:
			if int(_provinces[pid]["castle"]) < CASTLE_MAX:
				_provinces[pid]["castle"] = int(_provinces[pid]["castle"]) + 1
				koku -= CASTLE_COST
				break
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
	for pid in _owned(cid):
		var p: Dictionary = _provinces[pid]
		if _army(p) < 2 or _moved.has(pid):
			continue
		var committed: int = _army(p) - 1
		# Aggression blends difficulty + personality; a daimyō leading demands an extra
		# margin, since losing the last general ends the clan.
		var need: int = _aggr_for(cid) + (2 if int(p["daimyo"]) > 0 else 0)
		var best := ""
		var best_score := -9999
		for aid in p["adj"]:
			if not _provinces.has(aid):
				continue
			var ap: Dictionary = _provinces[aid]
			if ap.get("owner") == cid:
				continue
			var defv: int = _army(ap) + int(ap["castle"]) * 2
			var margin: int = committed - defv
			# Hunt enemy daimyō: a viable strike that also fells a general is worth more.
			var score: int = margin + (3 if int(ap.get("daimyo", 0)) > 0 else 0)
			if margin >= need and score > best_score:
				best_score = score
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
	var w := _screen_to_world(point)
	for pid in _provinces:
		if Geometry2D.is_point_in_polygon(w, _provinces[pid]["poly"]):
			return pid
	return ""


func _button_at(point: Vector2) -> String:
	for b in _buttons:
		if b["enabled"] and (b["rect"] as Rect2).has_point(point):
			return b["id"]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	# Map view: wheel zooms toward the cursor; right-drag pans.
	if event is InputEventMouseButton and _stage != Stage.MENU:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.18)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.18)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			return
	if event is InputEventMouseMotion:
		if _panning:
			_focus -= event.relative / _zoom
			_clamp_focus()
			queue_redraw()
			return
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
		if _ninja_spy_arm:
			var sp2: Dictionary = _provinces[hit]
			if sp2.get("owner") != _player and sp2.get("owner") != null:
				_ninja_spy(hit)
			_ninja_spy_arm = false
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
		"ninja_arm":
			_ninja_arm = not _ninja_arm
			_ninja_spy_arm = false
		"ninja_spy":
			_ninja_spy_arm = not _ninja_spy_arm
			_ninja_arm = false
		"help": _show_help = not _show_help
		"diff_easy": _difficulty = "easy"
		"diff_normal": _difficulty = "normal"
		"diff_hard": _difficulty = "hard"
		"begin_campaign": _start_campaign()
		"done_deploy":
			_war_sub = War.MANEUVER
			_dirty_odds()
		"end_turn":
			_expire_ronin(_player)
			_advance_war()
		"newgame": _new_game()
		"continue": _load_game()
		"save_game": _save_game()
		"zoom_in": _zoom_at(_view_center(), 1.25)
		"zoom_out": _zoom_at(_view_center(), 0.8)
		"zoom_reset": _reset_view()
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
	# Land base is the region's parchment shade; clan ownership is a bright overlay on top.
	return REGION_TINT.get(p.get("region", ""), C_PARCH)


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
	_draw_sea()
	draw_set_transform(_view_off(), 0.0, Vector2(_zoom, _zoom))  # enter map view (zoom/pan)
	# Land: shoreline + region parchment base.
	for pid in _provinces:
		var p: Dictionary = _provinces[pid]
		_draw_coast(p["poly"])
		draw_colored_polygon(p["poly"], _fill_for(p))
	# Terrain relief — scattered mountains/hills give the geography-map feel.
	_draw_terrain()
	# Bright clan-coloured territory overlay (terrain still shows through).
	for pid in _provinces:
		var po: Dictionary = _provinces[pid]
		var owner = po.get("owner")
		if owner != null and _clans.has(owner):
			var cc: Color = _clans[owner]["color"]
			draw_colored_polygon(po["poly"], Color(cc.r, cc.g, cc.b, 0.52))
	# Faint region names beneath the tokens, for orientation.
	for rg in _region_cen:
		_head_centered(rg, _region_cen[rg] as Vector2, 19, Color(0.18, 0.15, 0.10, 0.26))
	# Province borders (muted; brighter on hover).
	for pid in _provinces:
		var pb: Dictionary = _provinces[pid]
		var bw := 1.0
		var bc := C_BORDER
		if pid == _hovered and _stage == Stage.WAR:
			bw = 2.4
			bc = C_PARCH
		draw_polyline(_closed(pb["poly"]), bc, bw, true)

	var human_war := _stage == Stage.WAR and _active() == _player and not _game_over
	if human_war and _war_sub == War.MANEUVER:
		_ensure_odds()
		var pa := 0.30 + 0.28 * sin(_t * 3.5)
		for pid4 in _provinces:
			var pw4: Dictionary = _provinces[pid4]
			if pw4.get("owner") == _player and _army(pw4) >= 2 and not _moved.has(pid4):
				draw_polyline(_closed(pw4["poly"]), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, pa), 1.6, true)
	if _selected != "" and _provinces.has(_selected):
		var sel: Dictionary = _provinces[_selected]
		var actionable: bool = human_war and not _ninja_arm and not _ninja_spy_arm and _war_sub == War.MANEUVER and sel.get("owner") == _player and _army(sel) >= 2 and not _moved.has(_selected)
		if actionable:
			for aid in sel["adj"]:
				if not _provinces.has(aid):
					continue
				var ap: Dictionary = _provinces[aid]
				draw_polyline(_closed(ap["poly"]), C_GOLD, 2.0, true)
				var band := String(_odds_cache.get(aid, {}).get("band", ""))
				_draw_marker((sel["centroid"] + ap["centroid"]) * 0.5, ap.get("owner") != _player, band)
		draw_polyline(_closed(sel["poly"]), C_GOLD, 3.0, true)

	if human_war and (_ninja_arm or _ninja_spy_arm):
		var glow: Color = C_RED if _ninja_arm else C_STEEL
		for pid3 in _provinces:
			var pp: Dictionary = _provinces[pid3]
			if pp.get("owner") != _player and pp.get("owner") != null:
				draw_polyline(_closed(pp["poly"]), glow, 2.4, true)

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

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # leave map view — UI below is screen-space
	# Province name on hover (replaces the old always-on labels — too dense at 72).
	if _stage == Stage.WAR and _hovered != "" and _provinces.has(_hovered):
		var hp: Dictionary = _provinces[_hovered]
		var nm := String(hp["name"])
		var hc: Vector2 = _world_to_screen(hp["centroid"])
		var tw := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_rect(Rect2(hc.x - tw * 0.5 - 6, hc.y - 33, tw + 12, 18), Color(0.04, 0.05, 0.06, 0.85), true)
		_text_centered(nm, Vector2(hc.x, hc.y - 20), 13, C_PARCH)

	if human_war and _war_sub == War.MANEUVER and not _ninja_arm and not _ninja_spy_arm:
		_draw_odds_tip()
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


func _draw_marker(pos: Vector2, enemy: bool, band: String = "") -> void:
	draw_circle(pos, 9.0, C_PANEL)
	if enemy:
		var ec := C_RED
		match band:
			"favorable": ec = C_GREEN
			"even": ec = C_AMBER
			"risky": ec = C_RISK
		draw_arc(pos, 9.0, 0.0, TAU, 18, ec, 1.6, true)
		var xc := C_REDLT if band == "" else ec
		draw_line(pos + Vector2(-3.4, -3.4), pos + Vector2(3.4, 3.4), xc, 1.8, true)
		draw_line(pos + Vector2(3.4, -3.4), pos + Vector2(-3.4, 3.4), xc, 1.8, true)
	else:
		draw_arc(pos, 9.0, 0.0, TAU, 18, C_STEEL, 1.6, true)
		draw_polyline(PackedVector2Array([
			pos + Vector2(-3.5, 0), pos + Vector2(2.5, 0),
			pos + Vector2(-0.5, -3), pos + Vector2(3, 0), pos + Vector2(-0.5, 3),
		]), C_PARCH, 1.5, true)


func _draw_odds_tip() -> void:
	if _hovered == "" or not _odds_cache.has(_hovered):
		return
	var o: Dictionary = _odds_cache[_hovered]
	var cen: Vector2 = _world_to_screen(_provinces[_hovered]["centroid"])
	var w := 172.0
	var h := 98.0
	var x := clampf(cen.x + 18, 8, 1280 - w - 8)
	var y := clampf(cen.y - h - 14, TOP_BAR + 6, 720 - BOTTOM_BAR - h - 6)
	var bc := C_RISK
	match String(o["band"]):
		"favorable": bc = C_GREEN
		"even": bc = C_AMBER
	_panel(Rect2(x, y, w, h), C_PANEL, bc, 1.4, 8.0)
	_head("ATTACK ODDS", Vector2(x + 12, y + 22), 11, C_STEEL)
	_head("%d%%" % int(o["pct"]), Vector2(x + 12, y + 54), 28, bc)
	_text_centered(String(o["band"]).to_upper(), Vector2(x + w - 50, y + 50), 12, bc)
	var gar_txt: String = "" if int(o["gar"]) == 0 else "  (+%d garrison)" % int(o["gar"])
	draw_string(_font, Vector2(x + 12, y + 74), "you %d  vs  %d%s" % [int(o["att"]), int(o["def"]), gar_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_PARCH)
	if bool(o["dai"]):
		draw_string(_font, Vector2(x + 12, y + 90), "⚑ your daimyō leads the charge", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_GOLD)


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
		if _is_fogged(_selected):
			draw_string(_font, Vector2(x + 14, y + 126), "Composition hidden — send your ninja to scout", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_REDLT)
		else:
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
		var aitag: String = "" if cid == _player else "  · " + String(_clans[cid].get("persona", ""))
		var dtag: String = "  · ⚑%d" % _daimyo_count(cid) if alive else ""
		draw_string(_font, Vector2(sx + 38, cy + 48), "%d prov%s%s" % [_count(cid), dtag, aitag], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_GOLD)


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
	if _stage != Stage.MENU and not _game_over:
		_add_button("zoom_in", Rect2(16, 600, 30, 30), "+", true, false)
		_add_button("zoom_out", Rect2(50, 600, 30, 30), "–", true, false)
		_add_button("zoom_reset", Rect2(84, 600, 46, 30), "Fit", true, _zoom <= 1.001)
	if _stage == Stage.MENU:
		var dn := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
		var bx := 433.0
		for d in ["easy", "normal", "hard"]:
			_add_button("diff_" + d, Rect2(bx, 504, 130, 40), dn[d], true, _difficulty == d)
			bx += 142.0
		_add_button("begin_campaign", Rect2(540, 564, 200, 48), "Begin Campaign →", true, true)
		if _has_save():
			_add_button("continue", Rect2(540, 624, 200, 38), "Continue saved game", true, false)
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
			var albl := "Pick a foe" if _ninja_arm else "Strike ⚔"
			_add_button("ninja_arm", Rect2(1040, 70, 103, 36), albl, true, _ninja_arm)
			var slbl := "Pick a foe" if _ninja_spy_arm else "Spy"
			_add_button("ninja_spy", Rect2(1147, 70, 103, 36), slbl, true, _ninja_spy_arm)
		_add_button("save_game", Rect2(1040, 612, 210, 30), "Save game", true, false)
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
	var flow := "Each round: bid koku for turn order and the ninja, then a levy budget. The ninja holder gets ONE act per round — either ASSASSINATE an enemy province (d12 of 8 or less kills a defender) or SPY on one (reveal its hidden troop makeup). Enemy unit composition stays fogged until you scout it; only the total is visible. In battle: Archers & Gunners fire first (ranged), then Samurai, Ronin, Ashigaru & the castle garrison clash (melee). In the Maneuver phase, select one of your armies and hover an enemy border to read your ATTACK ODDS — green is favorable, amber even, red risky. A clan is also eliminated the instant it loses its LAST daimyō (⚑ count is shown under each clan) — its provinces pass to the slayer, so guard your generals and hunt theirs. Win by holding 10 provinces, or being the last clan standing."
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
	var c := _closed(poly)
	draw_polyline(c, Color(0.043, 0.071, 0.106, 0.55), 6.0, true)  # soft shoreline halo
	draw_polyline(c, C_INK, 3.0, true)                              # crisp coastline


## Draws the precomputed mountain marks across the land for a relief-map feel.
func _draw_terrain() -> void:
	for pid in _provinces:
		for m in _provinces[pid].get("mtns", []):
			_draw_mtn(m as Vector2)


func _draw_mtn(c: Vector2) -> void:
	var dark := Color(0.451, 0.388, 0.290, 0.80)
	var lite := Color(0.776, 0.706, 0.545, 0.85)
	var snow := Color(0.93, 0.91, 0.86, 0.9)
	var w := 5.2
	var h := 6.6
	var apex := c + Vector2(0, -h)
	# shaded body
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w, h * 0.55), apex, c + Vector2(w, h * 0.55)]), dark)
	# lit left face
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w, h * 0.55), apex, c + Vector2(-w * 0.12, h * 0.18)]), lite)
	# snowcap
	draw_colored_polygon(PackedVector2Array([apex, apex + Vector2(-w * 0.34, h * 0.42), apex + Vector2(w * 0.34, h * 0.42)]), snow)


## The sea: a filled play area with a faint nautical grid and an edge vignette.
func _draw_sea() -> void:
	var top := TOP_BAR
	var h := 720.0 - TOP_BAR - BOTTOM_BAR
	draw_rect(Rect2(0, top, 1280, h), C_SEA, true)
	for sy in range(int(top) + 16, int(top + h), 26):
		draw_line(Vector2(0, sy), Vector2(1280, sy), Color(0.16, 0.22, 0.30, 0.16), 1.0)
	for sx in range(48, 1280, 64):
		draw_line(Vector2(sx, top), Vector2(sx, top + h), Color(0.16, 0.22, 0.30, 0.09), 1.0)
	for i in 6:
		var inset := i * 7.0
		draw_rect(Rect2(inset, top + inset, 1280 - inset * 2, h - inset * 2), Color(C_SEA2.r, C_SEA2.g, C_SEA2.b, 0.05), false, 13.0)


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
	_text_centered("Click ? at any time for the field guide.", Vector2(640, 694), 12, C_STEEL)


# ---------------------------------------------------------------- data + dev

## Fits the map's actual bounding box (_map_min.._map_max, set in _load_data) into the
## play area, so any map — 16 provinces or 72 — fills the screen the same way.
func _compute_transform() -> void:
	var vp := Vector2(1280, 720)
	var span := _map_max - _map_min
	if span.x <= 0.0 or span.y <= 0.0:
		span = Vector2(DESIGN_W, DESIGN_H)
	_scale = min((vp.x - 48.0) / span.x, (vp.y - TOP_BAR - BOTTOM_BAR - 16.0) / span.y)
	var map_w := span.x * _scale
	var map_h := span.y * _scale
	_offset = Vector2((vp.x - map_w) * 0.5, TOP_BAR + ((vp.y - TOP_BAR - BOTTOM_BAR) - map_h) * 0.5)
	_map_rect = Rect2(_offset, Vector2(map_w, map_h))
	_reset_view()


func _to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - _map_min.x) * _scale + _offset.x, (p.y - _map_min.y) * _scale + _offset.y)


# ---------------------------------------------------------------- map view (zoom / pan)

func _view_center() -> Vector2:
	return Vector2(640.0, TOP_BAR + (720.0 - TOP_BAR - BOTTOM_BAR) * 0.5)


## Canvas translation paired with a uniform _zoom scale, applied via draw_set_transform.
func _view_off() -> Vector2:
	return _view_center() - _focus * _zoom


func _world_to_screen(p: Vector2) -> Vector2:
	return (p - _focus) * _zoom + _view_center()


func _screen_to_world(p: Vector2) -> Vector2:
	return (p - _view_center()) / _zoom + _focus


func _reset_view() -> void:
	_zoom = 1.0
	_focus = _map_rect.get_center() if _map_rect.size.x > 0.0 else _view_center()


## Keep the focus point within the map so panning can't lose the islands off-screen.
func _clamp_focus() -> void:
	if _map_rect.size.x <= 0.0:
		return
	_focus.x = clampf(_focus.x, _map_rect.position.x, _map_rect.position.x + _map_rect.size.x)
	_focus.y = clampf(_focus.y, _map_rect.position.y, _map_rect.position.y + _map_rect.size.y)


## Zoom by [param factor] about a screen point, keeping the land under that point fixed.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var w := _screen_to_world(screen_pos)
	_zoom = clampf(_zoom * factor, 1.0, 5.0)
	_focus = w - (screen_pos - _view_center()) / _zoom
	_clamp_focus()


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
	# Fixed per-clan personality so rivals are recognizable game to game (orthogonal to difficulty).
	var personas := {"B": "aggressive", "C": "economic", "D": "defensive", "E": "opportunist"}
	for cid in data.get("clans", {}).keys():
		var c: Dictionary = data["clans"][cid]
		var col: Array = c["color"]
		var tnt: Array = c["tint"]
		_clans[cid] = {
			"name": c["name"],
			"color": Color(col[0], col[1], col[2]),
			"tint": Color(tnt[0], tnt[1], tnt[2]),
			"ai": ai_levels.get(cid, "medium"),
			"persona": personas.get(cid, "opportunist"),
		}
	var provs: Dictionary = data.get("provinces", {})
	# First pass: bounding box of all raw points, so the transform can fit any map.
	var pmin := Vector2(INF, INF)
	var pmax := Vector2(-INF, -INF)
	for pid in provs.keys():
		for pt in provs[pid]["points"]:
			pmin.x = minf(pmin.x, pt[0]); pmin.y = minf(pmin.y, pt[1])
			pmax.x = maxf(pmax.x, pt[0]); pmax.y = maxf(pmax.y, pt[1])
	_map_min = pmin
	_map_max = pmax
	_compute_transform()
	_provinces = {}
	for pid in provs.keys():
		var p: Dictionary = provs[pid]
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
			"region": p.get("region", ""),
		}
	# Region label anchors = mean of each region's province centroids.
	_region_cen = {}
	var racc := {}
	for pid in _provinces:
		var rg := String(_provinces[pid].get("region", ""))
		if rg == "":
			continue
		if not racc.has(rg):
			racc[rg] = [Vector2.ZERO, 0]
		racc[rg][0] += _provinces[pid]["centroid"]
		racc[rg][1] = int(racc[rg][1]) + 1
	for rg in racc:
		_region_cen[rg] = (racc[rg][0] as Vector2) / float(racc[rg][1])
	# Terrain: scatter mountain marks inside each province (stable per load). Japan is
	# mountainous, so this carries the geography-map look; plains regions get fewer.
	var trng := RandomNumberGenerator.new()
	trng.seed = 92017
	var mtn_bonus := {"Chūbu": 4, "Tōhoku": 3, "Hokuriku": 3, "Ezo": 3, "Chūgoku": 2, "Shikoku": 2, "Kyūshū": 2, "Tōkai": 1, "Kinai": 1, "Kantō": 0}
	for pid in _provinces:
		var pr: Dictionary = _provinces[pid]
		var poly: PackedVector2Array = pr["poly"]
		var bmin := poly[0]
		var bmax := poly[0]
		var ar := 0.0
		for vi in poly.size():
			bmin.x = minf(bmin.x, poly[vi].x); bmin.y = minf(bmin.y, poly[vi].y)
			bmax.x = maxf(bmax.x, poly[vi].x); bmax.y = maxf(bmax.y, poly[vi].y)
			var vj := poly[(vi + 1) % poly.size()]
			ar += poly[vi].x * vj.y - vj.x * poly[vi].y
		ar = absf(ar) * 0.5
		var cnt := clampi(int(ar / 2600.0) + int(mtn_bonus.get(pr["region"], 1)), 1, 11)
		var mtns: Array = []
		var tries := 0
		while mtns.size() < cnt and tries < cnt * 14:
			tries += 1
			var pt := Vector2(trng.randf_range(bmin.x, bmax.x), trng.randf_range(bmin.y, bmax.y))
			if Geometry2D.is_point_in_polygon(pt, poly) and pt.distance_to(pr["centroid"]) > 13.0:
				mtns.append(pt)
		mtns.sort_custom(func(a, b): return a.y < b.y)
		pr["mtns"] = mtns


## ---------------------------------------------------------------- save / load

func _has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Writes the full dynamic game state to user:// as JSON. Static structure (province
## polygons, adjacency, clan colours) is NOT saved — it is rebuilt from provinces.json on
## load and the saved owners/units/castles/daimyō are overlaid on top.
func _save_game() -> void:
	var prov := {}
	for pid in _provinces:
		var p: Dictionary = _provinces[pid]
		prov[pid] = {"owner": p["owner"], "units": (p["units"] as Dictionary).duplicate(), "castle": int(p["castle"]), "daimyo": int(p["daimyo"])}
	var ai := {}
	for cid in _clans:
		ai[cid] = {"ai": _clans[cid].get("ai", "medium"), "persona": _clans[cid].get("persona", "opportunist")}
	var data := {
		"v": 1, "round": _round, "player": _player, "stage": _stage, "war_idx": _war_idx,
		"war_sub": _war_sub, "deploy_koku": _deploy_koku, "deploy_type": _deploy_type,
		"ninja_holder": _ninja_holder, "ninja_used": _ninja_used, "difficulty": _difficulty,
		"game_over": _game_over, "result": _result, "order": _order, "koku": _koku,
		"alloc": _alloc, "scouted": _scouted, "events": _events, "moved": _moved,
		"selected": _selected, "provinces": prov, "clans_ai": ai,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_log("Could not write the save file.")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	_log("Campaign saved — choose Continue from the title to resume.")


func _load_game() -> void:
	if not _has_save():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	_load_data()  # rebuild polys/centroids/clans + default units
	var ai: Dictionary = d.get("clans_ai", {})
	for cid in ai:
		if _clans.has(cid):
			_clans[cid]["ai"] = String(ai[cid].get("ai", "medium"))
			_clans[cid]["persona"] = String(ai[cid].get("persona", "opportunist"))
	var prov: Dictionary = d.get("provinces", {})
	for pid in prov:
		if not _provinces.has(pid):
			continue
		var sp: Dictionary = prov[pid]
		_provinces[pid]["owner"] = sp.get("owner")
		var u: Dictionary = sp.get("units", {})
		for k in UNIT_KEYS:
			_provinces[pid]["units"][k] = int(u.get(k, 0))
		_provinces[pid]["castle"] = int(sp.get("castle", 0))
		_provinces[pid]["daimyo"] = int(sp.get("daimyo", 0))
		_sync(_provinces[pid])
	_round = int(d.get("round", 1))
	_player = String(d.get("player", "A"))
	_stage = int(d.get("stage", Stage.WAR))
	_war_idx = int(d.get("war_idx", 0))
	_war_sub = int(d.get("war_sub", War.DEPLOY))
	_deploy_koku = int(d.get("deploy_koku", 0))
	_deploy_type = String(d.get("deploy_type", "ash"))
	_ninja_holder = String(d.get("ninja_holder", ""))
	_ninja_used = bool(d.get("ninja_used", false))
	_difficulty = String(d.get("difficulty", "normal"))
	_game_over = bool(d.get("game_over", false))
	_result = String(d.get("result", ""))
	_order = d.get("order", [])
	_koku = d.get("koku", {})
	_alloc = d.get("alloc", {})
	_scouted = d.get("scouted", {})
	_events = d.get("events", [])
	_moved = d.get("moved", {})
	_selected = String(d.get("selected", ""))
	_ninja_arm = false
	_ninja_spy_arm = false
	_modal = null
	_dirty_odds()
	_log("Campaign resumed.")
	queue_redraw()


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
