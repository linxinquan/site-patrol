/// 客户端本地 ID 生成（ULID，Universally Unique Lexicographically Sortable Identifier）。
///
/// 为什么不用毫秒时间戳：多台设备同时写会**撞 ID**（工地常见的两台手机 + 网页
/// 同时录入）。ULID = 48bit 时间戳 + 80bit 随机，**时间有序**且几乎不可能重复，
/// 既满足「按写入顺序排序」，又能作为服务端幂等键（唯一索引）。
///
/// 形态：26 个 Crockford Base32 字符（`0123456789ABCDEFGHJKMNPQRSTVWXYZ`），
/// 前 10 位时间戳（毫秒）、后 16 位随机。**不含小写与 I/L/O/U**，避免人工抄录歧义。
///
/// 单调性：同一毫秒内连续调用时，随机段按字典序自增（ULID 规范的可选单调模式），
/// 保证同毫秒生成的 ID 仍然有序且不重复。
///
/// 使用场景：所有**客户端新建**的业务记录 `id`（缺陷 / 验收记录 / 量具会话 /
/// 量房 / 巡场 / 报告归档 / 施工进度）；后台录入的档案类 id 由服务端下发。
library;

import 'dart:math' as math;

const String _kCrockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 同一毫秒内的随机段自增基准（每个元素 0~31，对应一个 Base32 字符）。
final List<int> _lastRandom = List<int>.filled(16, 0);
int _lastMs = 0;

/// 生成一个新的 ULID。
///
/// [nowMs] 仅用于测试注入固定时间；业务代码不要传。
String newId({int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final int ms;
  if (now > _lastMs) {
    // 正常前进：换新时间戳 + 新随机段。
    ms = now;
    _lastMs = now;
    _fillRandom();
  } else {
    // 同一毫秒 / 时钟回拨：**沿用最近时间戳**并把随机段 +1（溢出向高位进位），
    // 保证 ID 在字典序上仍单调递增、且不重复。
    ms = _lastMs;
    var i = 15;
    while (i >= 0) {
      if (_lastRandom[i] < 31) {
        _lastRandom[i]++;
        break;
      }
      _lastRandom[i] = 0;
      i--;
    }
    if (i < 0) {
      // 极端情况：同毫秒内 2^80 次调用，退化为重新随机（实际不会发生）。
      _fillRandom();
    }
  }

  final chars = List<String>.filled(26, '0');
  // 前 10 字符：48bit 时间戳，高位对齐。
  var t = ms;
  for (var i = 9; i >= 0; i--) {
    chars[i] = _kCrockford[t & 0x1f];
    t >>= 5;
  }
  // 后 16 字符：80bit 随机。
  for (var i = 0; i < 16; i++) {
    chars[10 + i] = _kCrockford[_lastRandom[i]];
  }
  return chars.join();
}

/// 判断是否为合法 ULID（26 位、仅 Crockford Base32 大写字符）。
///
/// 用于区分「客户端新建的 ULID」与「后台下发的历史/业务 id」，
/// 不要用它做业务校验（历史数据里存在 `d1` / `dy7_1` 这类可读 id）。
bool isUlid(String? s) {
  if (s == null || s.length != 26) return false;
  for (final r in s.runes) {
    if (!_kCrockford.codeUnits.contains(r)) return false;
  }
  return true;
}

void _fillRandom() {
  final rnd = math.Random.secure();
  for (var i = 0; i < 16; i++) {
    _lastRandom[i] = rnd.nextInt(32);
  }
}
