extends RefCounted
## fx_pxplane 与各干员分文件（fx_pxplane_<id>.gd）共用的小工具（docs/282 §2：原来每个文件各抄一份）。
## 纯函数，不读写对局状态。


## 取 opts 里离 v 最近的一档（相同距离取靠前的）：按半径 / 长度挑预烘焙帧条的档位
static func nearest(opts: Array, v: float) -> int:
	var best: int = int(opts[0])
	for x in opts:
		if absf(float(x) - v) < absf(float(best) - v):
			best = int(x)
	return best


## 这一拍（1/15 秒）内 key 已经出过几个（返回出这个之前的个数，并计数 +1）；cnt 是调用方自己的计数表
static func beat_n(cnt: Dictionary, t: float, key: String) -> int:
	var bt: int = int(floor(t * 15.0))
	var c: Array = cnt.get(key, [bt, 0])
	if int(c[0]) != bt:
		c = [bt, 0]
	c[1] = int(c[1]) + 1
	cnt[key] = c
	return int(c[1]) - 1
