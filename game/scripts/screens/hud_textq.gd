extends RefCounted
## HUD 字按字体 / 字号成组（docs/50 §13）：每个字号（以及每种描边宽度）在字体缓存里是单独一张贴图，
## 不同字号交替画时每换一次就断一次批。合批段里的字先按「描边 / 本体 + 字体 + 字号 + 描边宽度」归组，
## 段末先画全部描边、再画全部本体，同组按原顺序。只用在段内各行字互不重叠的地方（HUD 面板、标签），重叠处的前后关系才不变

static var _fid := {}   # Font -> 小整数（组键用）

var _ok: Array = []     # 描边组键（首次出现的顺序）
var _fk: Array = []     # 本体组键
var _og := {}
var _fg := {}


static func key(font: Font, size: int, outline := 0) -> int:
	var id = _fid.get(font)
	if id == null:
		id = _fid.size() + 1
		_fid[font] = id
	return (int(id) << 16) | (size << 6) | mini(outline, 63)


func add(outline: bool, k: int, f: Callable) -> void:
	if outline:
		var a = _og.get(k)
		if a == null:
			a = []
			_og[k] = a
			_ok.append(k)
		a.append(f)
	else:
		var b = _fg.get(k)
		if b == null:
			b = []
			_fg[k] = b
			_fk.append(k)
		b.append(f)


func is_empty() -> bool:
	return _ok.is_empty() and _fk.is_empty()


func flush() -> void:
	for k in _ok:
		for f in _og[k]:
			f.call()
	for k in _fk:
		for f in _fg[k]:
			f.call()
	_ok.clear()
	_fk.clear()
	_og.clear()
	_fg.clear()
