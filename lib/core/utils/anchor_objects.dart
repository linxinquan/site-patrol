/// 已知尺寸标准件（自动标定锚物）尺寸库。
///
/// 目标：**用户零输入**完成量尺标定——拍照后由视觉模型自动识别画面里的
/// 标准尺寸物件（开关面板 / 瓷砖 / 标准砖 / A4 纸…），用它的真实尺寸
/// 反算比例尺（mm/px），取代"手填参考物尺寸 + 手点两端"的旧流程。
///
/// 精度定位：工地巡查**快测/筛查**用。图像几何定标在近距离垂直拍摄下
/// 约 ±0.5%~1%，优于 VIO 累积漂移；但仍不足以做 ±5mm 级验收判定，
/// 判定请用卷尺/激光测距。UI 需始终保留手动标定作为兜底。
library;

/// 一个可用于自动标定的标准件。
class AnchorObject {
  /// 稳定标识（与模型约定的 id）。
  final String id;

  /// 展示名。
  final String label;

  /// 常见叫法（拼进提示词，帮助模型识别）。
  final String aliases;

  /// 名义尺寸（mm）。模型实际会按**画面中该物体的朝向**返回
  /// 框横/纵各自对应的真实长度，这里仅作提示词示例与文档。
  final double wmm;
  final double hmm;

  /// 给用户的拍摄提示。
  final String tip;

  const AnchorObject({
    required this.id,
    required this.label,
    required this.aliases,
    required this.wmm,
    required this.hmm,
    required this.tip,
  });
}

/// 内置标准件清单（工地常见、尺寸固定、可扩展）。
const List<AnchorObject> kAnchorObjects = [
  AnchorObject(
    id: 'switch86',
    label: '86型开关/插座面板',
    aliases: '开关面板、插座面板、86面板、86型底盒面板',
    wmm: 86,
    hmm: 86,
    tip: '精装修房间几乎必有，正对一个完整面板拍摄',
  ),
  AnchorObject(
    id: 'a4',
    label: 'A4纸',
    aliases: 'A4纸、打印纸、复印纸',
    wmm: 210,
    hmm: 297,
    tip: '平铺贴墙/贴地拍摄，整张纸入画',
  ),
  AnchorObject(
    id: 'card',
    label: '身份证/银行卡',
    aliases: '身份证、银行卡、卡片',
    wmm: 85.6,
    hmm: 54,
    tip: '平放拍摄，整卡入画（尺寸最标准）',
  ),
  AnchorObject(
    id: 'brick',
    label: '标准砖（烧结普通砖）',
    aliases: '标准砖、红砖、烧结砖、实心砖',
    wmm: 240,
    hmm: 115,
    tip: '拍单块砖的完整顶面或侧面',
  ),
  AnchorObject(
    id: 'tile300',
    label: '300×300瓷砖',
    aliases: '小方砖、300砖、厨卫墙砖',
    wmm: 300,
    hmm: 300,
    tip: '厨卫常见，正对一块完整砖面',
  ),
  AnchorObject(
    id: 'tile600',
    label: '600×600瓷砖',
    aliases: '地砖、600砖、广场砖',
    wmm: 600,
    hmm: 600,
    tip: '正对一块完整砖面',
  ),
  AnchorObject(
    id: 'tile800',
    label: '800×800瓷砖',
    aliases: '大板砖、800砖、客厅地砖',
    wmm: 800,
    hmm: 800,
    tip: '正对一块完整砖面',
  ),
  AnchorObject(
    id: 'gypsum',
    label: '纸面石膏板',
    aliases: '石膏板、纸面石膏板、吊顶板',
    wmm: 1200,
    hmm: 2400,
    tip: '吊顶/隔墙阶段常见，拍板材短边或整板',
  ),
];

/// 自动标定的用户引导文案（列出支持的锚物）。
String get anchorHintText =>
    kAnchorObjects.map((a) => a.label).join(' / ');
