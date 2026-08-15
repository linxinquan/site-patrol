import '../models.dart';

/// 由原型 app.js 常量移植。src 统一用 PNG（避开 16MB SVG 卡顿）。

/// 项目参与方定义（腾讯大铲湾 DY04 · 7栋）。
const List<Party> tencentDachanwanParties = [
  Party(
    role: '甲方（业主方）',
    org: '腾讯科技（深圳）有限公司',
    contact: '林心荃',
    title: '业主代表',
  ),
  Party(
    role: '设计院（LDI）',
    org: '深圳市建筑设计研究总院（深总院）',
    contact: '朱伟',
    title: '设计管理',
  ),
  Party(
    role: '第三方监理 / 全过程咨询',
    org: '深圳华西建设工程管理有限公司',
    contact: '杨玉婷',
    title: '施工监理',
  ),
  Party(
    role: 'Arcadis（凯迪思）全过程咨询 / PMO',
    org: 'Arcadis（凯迪思）',
    contact: '欧阳嘉',
    title: '全过程咨询 / PMO',
  ),
];

const Project project = Project(
  id: 'nkf',
  name: '南方科技大学附属医院（校本部）',
  client: '深圳市建筑工务署',
  location: '深圳市南山区西丽大学城南方科技大学校内东侧',
  status: '已封顶 · 预计 2027 年竣工',
  siteArea: '5.68万㎡',
  floorArea: '16.76万㎡',
  beds: 800,
  concept: '山水动脉',
  milestones: [
    Milestone(name: '基坑支护与土方开挖', date: '2024-03-31', done: true),
    Milestone(name: '地下室结构施工', date: '2024-12-31', done: true),
    Milestone(name: '主体结构封顶', date: '2026-01-31', done: true),
    Milestone(name: '幕墙与机电安装', date: '2026-08-31', current: true),
    Milestone(name: '精装修施工', date: '2026-12-31'),
    Milestone(name: '竣工验收', date: '2027-06-30'),
  ],
);

/// 腾讯大铲湾 DY04 · 7栋（多项目切换目标项目）。
/// 数据来源：深圳市前海管理局官方规划公示 / project_info.html（2026-08-14 联网核实）
const Project tencentProject = Project(
  id: 'tencent-dy04-7',
  name: '腾讯大铲湾 DY04 · 7栋',
  client: '腾讯科技（深圳）有限公司',
  location: '深圳市宝安区大铲湾',
  status: '在建 · 施工中（2026年内计划整体完工）',
  siteArea: '12.62万㎡',
  floorArea: '64057㎡',
  beds: 0,
  concept: '云楼 · 产业研发及配套',
  parties: tencentDachanwanParties,
  milestones: [
    // —— 立项 / 基坑 ——
    Milestone(name: '地块土石方/基坑/桩基奠基', date: '2021-06-09', done: true),
    Milestone(name: '基坑支护施工许可发证', date: '2021-06-23', done: true),
    // —— 行政许可 ——
    Milestone(name: '取得工规证 BA-2022-0049', date: '2022-06-16', done: true),
    Milestone(name: '合同开工（7/8栋）', date: '2022-07-31', done: true),
    // —— 主体施工 ——
    Milestone(name: '云楼幕墙中标开工', date: '2022-12-01', done: true),
    Milestone(name: '主体结构全面封顶', date: '2024-09-30', done: true),
    // —— 规划变更 / 备案 ——
    Milestone(name: '规划许可变更（地下扩容）', date: '2025-09-23', done: true),
    Milestone(name: '餐厅装修验收备案', date: '2025-11-26', done: true),
    Milestone(name: '一期（04/05街区）整体竣工', date: '2025-12-31', done: true),
    // —— 当前与未来 ——
    Milestone(name: '园区整体收尾推进', date: '2026-08-31', current: true),
    Milestone(name: '产业入驻与运维移交', date: '2026-12-31'),
  ],
);

/// 所有项目列表（多项目切换用）。默认第一个为当前选中项目。
const List<Project> allProjects = [tencentProject, project];

/// 系统用户列表（参与方代表，头像切换用）。默认第一个为当前登录用户。
const List<User> users = [
  User(
    id: 'ouyang',
    name: '欧阳嘉',
    org: 'Arcadis（凯迪思）',
    role: '全过程咨询 / PMO',
    avatar: 'assets/avatars/ouyang-zong.jpg',
  ),
  User(
    id: 'lin',
    name: '林心荃',
    org: '腾讯科技（深圳）有限公司',
    role: '业主代表',
    avatar: 'assets/avatars/lin-zong.jpg',
  ),
  User(
    id: 'zhu',
    name: '朱伟',
    org: '深圳市建筑设计研究总院（深总院）',
    role: '设计管理',
    avatar: 'assets/avatars/zhu-gong.jpg',
  ),
  User(
    id: 'yang',
    name: '杨玉婷',
    org: '深圳华西建设工程管理有限公司',
    role: '施工监理',
    avatar: 'assets/avatars/yang-gong.jpg',
  ),
];

const List<Floor> floors = [
  Floor(key: 'nkf_total', name: '总平面图', index: 2, cached: true, progress: 100, building: '总图', floor: '总图'),
  Floor(key: 'nkf_total_v', name: '首层竖向总平面图', index: 0, cached: false, progress: 0, building: '总图', floor: '1F'),
  Floor(key: 'nkf_west_b2', name: '西楼·地下二层平面图', index: 0, cached: true, progress: 100, building: '西楼', floor: 'B2'),
  Floor(key: 'nkf_west_b1', name: '西楼·地下一层平面图', index: 0, cached: false, progress: 0, building: '西楼', floor: 'B1'),
  Floor(key: 'nkf_west_1f', name: '西楼·一层平面图', index: 7, cached: true, progress: 100, building: '西楼', floor: '1F'),
  Floor(key: 'nkf_west_2f', name: '西楼·二层平面图', index: 0, cached: true, progress: 100, building: '西楼', floor: '2F'),
  Floor(key: 'nkf_west_4f', name: '西楼·四层平面图(标准层)', index: 0, cached: true, progress: 100, building: '西楼', floor: '4F'),
  Floor(key: 'nkf_east_1f', name: '东楼·一层平面图', index: 3, cached: true, progress: 100, building: '东楼', floor: '1F'),
  Floor(key: 'nkf_east_4f', name: '东楼·四层平面图(标准层)', index: 0, cached: true, progress: 100, building: '东楼', floor: '4F'),
  Floor(key: 'nkf_inf_1f', name: '感染楼·一层平面图', index: 0, cached: false, progress: 0, building: '感染楼', floor: '1F'),
  Floor(key: 'nkf_cor_1f', name: '连廊·一层平面图', index: 0, cached: true, progress: 100, building: '连廊', floor: '1F'),
];

const Map<String, Drawing> drawings = {
  'nkf_total': Drawing(
    key: 'nkf_total', title: '总平面图', crumb: '总平面图', variant: 'plan',
    src: 'assets/drawings/nkf_total.png', w: 1500, h: 944,
    hotspots: [
      Hotspot(num: 1, label: '西楼主入口 → 西楼1F', target: 'nkf_west_1f', x: 0.38, y: 0.58),
      Hotspot(num: 2, label: '东楼门诊 → 东楼1F', target: 'nkf_east_1f', x: 0.68, y: 0.26),
    ],
  ),
  'nkf_total_v': Drawing(key: 'nkf_total_v', title: '首层竖向总平面图', crumb: '竖向总平面', variant: 'plan', src: 'assets/drawings/nkf_total_v.png', w: 1500, h: 944, hotspots: []),
  'nkf_west_b2': Drawing(key: 'nkf_west_b2', title: '西楼·地下二层平面图', crumb: '西楼 B2', variant: 'plan', src: 'assets/drawings/nkf_west_b2.png', w: 1500, h: 944, hotspots: []),
  'nkf_west_b1': Drawing(key: 'nkf_west_b1', title: '西楼·地下一层平面图', crumb: '西楼 B1', variant: 'plan', src: 'assets/drawings/nkf_west_b1.png', w: 1500, h: 944, hotspots: []),
  'nkf_west_1f': Drawing(
    key: 'nkf_west_1f', title: '西楼·一层平面图', crumb: '西楼 1F', variant: 'plan',
    src: 'assets/drawings/nkf_west_1f.png', w: 1500, h: 944,
    hotspots: [
      Hotspot(num: 3, label: '左病房翼 → 2F', target: 'nkf_west_2f', x: 0.18, y: 0.38),
      Hotspot(num: 4, label: '门诊大厅/医疗街 → 2F', target: 'nkf_west_2f', x: 0.50, y: 0.32),
      Hotspot(num: 5, label: '右病房翼 → 4F', target: 'nkf_west_4f', x: 0.82, y: 0.38),
      Hotspot(num: 6, label: '中央医街/电梯厅 → 2F', target: 'nkf_west_2f', x: 0.50, y: 0.55),
      Hotspot(num: 7, label: '消防/设备间 → B1', target: 'nkf_west_b1', x: 0.50, y: 0.72),
      Hotspot(num: 8, label: '地下车库入口 → B2', target: 'nkf_west_b2', x: 0.50, y: 0.85),
    ],
  ),
  'nkf_west_2f': Drawing(key: 'nkf_west_2f', title: '西楼·二层平面图', crumb: '西楼 2F', variant: 'plan', src: 'assets/drawings/nkf_west_2f.png', w: 1500, h: 944, hotspots: []),
  'nkf_west_4f': Drawing(key: 'nkf_west_4f', title: '西楼·四层平面图(标准层)', crumb: '西楼 4F', variant: 'plan', src: 'assets/drawings/nkf_west_4f.png', w: 1500, h: 944, hotspots: []),
  'nkf_east_1f': Drawing(
    key: 'nkf_east_1f', title: '东楼·一层平面图', crumb: '东楼 1F', variant: 'plan',
    src: 'assets/drawings/nkf_east_1f.png', w: 1500, h: 1062,
    hotspots: [
      Hotspot(num: 9, label: '门诊大厅 → 4F标准层', target: 'nkf_east_4f', x: 0.50, y: 0.35),
      Hotspot(num: 10, label: '住院部 → 4F标准层', target: 'nkf_east_4f', x: 0.25, y: 0.55),
      Hotspot(num: 11, label: '医辅区 → 4F标准层', target: 'nkf_east_4f', x: 0.75, y: 0.55),
    ],
  ),
  'nkf_east_4f': Drawing(key: 'nkf_east_4f', title: '东楼·四层平面图(标准层)', crumb: '东楼 4F', variant: 'plan', src: 'assets/drawings/nkf_east_4f.png', w: 1500, h: 1062, hotspots: []),
  'nkf_inf_1f': Drawing(key: 'nkf_inf_1f', title: '感染楼·一层平面图', crumb: '感染楼 1F', variant: 'plan', src: 'assets/drawings/nkf_inf_1f.png', w: 1500, h: 1062, hotspots: []),
  'nkf_cor_1f': Drawing(key: 'nkf_cor_1f', title: '连廊·一层平面图', crumb: '连廊 1F', variant: 'plan', src: 'assets/drawings/nkf_cor_1f.png', w: 1500, h: 1062, hotspots: []),
};

const Map<String, List<PhotoAnchor>> photoAnchors = {
  '西楼1F': [
    PhotoAnchor(id: 'w1-nuclear', x: 0.174, y: 0.397, label: '核医学科房翼', labelPos: 'top', photos: [
      AnchorPhoto(file: 'photo_nuclear_rebar.jpg', date: '2026-06-10', caption: '核医学科房翼钢筋绑扎间距均匀'),
    ]),
    PhotoAnchor(id: 'w1-corridor', x: 0.249, y: 0.422, label: '架空通廊', labelPos: 'bottom', photos: [
      AnchorPhoto(file: 'photo_corridor_beam.jpg', date: '2026-06-20', caption: '架空通廊下挂梁柱一次成型'),
    ]),
    PhotoAnchor(id: 'w1-street', x: 0.451, y: 0.428, label: '中央医街', labelPos: 'top', photos: [
      AnchorPhoto(file: 'photo_street_structure.jpg', date: '2026-07-02', caption: '中央医街二次结构加固规范'),
    ]),
    PhotoAnchor(id: 'w1-hall', x: 0.437, y: 0.479, label: '门诊大厅', labelPos: 'bottom', photos: [
      AnchorPhoto(file: 'photo_hall_formwork.jpg', date: '2026-06-15', caption: '模板安装、弹线画点'),
      AnchorPhoto(file: 'photo_hall_arc_form.jpg', date: '2026-06-22', caption: '门诊大厅定制弧形模板'),
      AnchorPhoto(file: 'photo_hall_arc_done.jpg', date: '2026-07-05', caption: '弧形结构成型效果'),
    ]),
    PhotoAnchor(id: 'w1-gyn', x: 0.725, y: 0.390, label: '妇科门诊房翼', labelPos: 'right', photos: [
      AnchorPhoto(file: 'photo_gyn_masonry.jpg', date: '2026-06-28', caption: '妇科门诊房翼砌体施工灰缝顺直饱满'),
    ]),
  ],
  '东楼1F': [
    PhotoAnchor(id: 'e1-out', x: 0.50, y: 0.35, label: '门诊大厅', photos: [
      AnchorPhoto(file: 'photo_e1_column.jpg', date: '2026-06-12', caption: '东楼门诊大厅墙柱梯柱筋防偏位'),
    ]),
    PhotoAnchor(id: 'e1-ward', x: 0.25, y: 0.55, label: '住院部', photos: [
      AnchorPhoto(file: 'photo_e1_top.jpg', date: '2026-07-20', caption: '东楼住院部封顶航拍记录'),
    ]),
  ],
  '总平面图': [
    PhotoAnchor(id: 'site-aero', x: 0.50, y: 0.50, label: '项目全景', photos: [
      AnchorPhoto(file: 'photo_site_aero.jpg', date: '2026-05-30', caption: '未封顶航拍：可利用的场所合理布置'),
      AnchorPhoto(file: 'photo_e1_top.jpg', date: '2026-07-20', caption: '项目封顶航拍图'),
    ]),
    PhotoAnchor(id: 'site-energy', x: 0.38, y: 0.58, label: '光储直柔', photos: [
      AnchorPhoto(file: 'photo_site_energy.png', date: '2026-07-10', caption: '项目“光储直柔”应用实施图'),
    ]),
  ],
};

const List<Defect> defects = [
  Defect(id: 'd1', part: '西楼1F门诊大厅墙面空鼓', type: '空鼓', category: DefectCategory.decoration, severity: DefectSeverity.orange, status: DefectStatus.draft, anchor: '西楼1F-左病房翼', floor: '西楼1F', ts: '2026-08-08 14:32', gps: '22.5936°N 113.9798°E', alt: '海拔 18.2m', resp: '深圳市建工集团 王工', respUnit: '深圳市建工集团', reporter: '现场监理 陈工', tags: ['精装修', '注浆处理'], note: '空鼓面积约 0.4㎡，需注浆处理', seed: 'a'),
  Defect(id: 'd2', part: '东楼4F标准层病房渗漏', type: '渗漏', category: DefectCategory.water, severity: DefectSeverity.yellow, status: DefectStatus.done, anchor: '东楼4F-住院部', floor: '东楼4F', ts: '2026-08-06 09:15', gps: '22.5938°N 113.9801°E', alt: '海拔 32.5m', resp: '深圳市建工集团 李工', respUnit: '深圳市建工集团', reporter: '现场监理 王工', tags: ['渗漏', '已闭环'], note: '已注浆封堵，复查无渗水', seed: 'b'),
  Defect(id: 'd3', part: '感染楼1F 防火墙洞口偏差', type: '洞口偏差', category: DefectCategory.architecture, severity: DefectSeverity.orange, status: DefectStatus.reject, anchor: '感染楼1F-医辅区', floor: '感染楼1F', ts: '2026-08-05 16:40', gps: '22.5934°N 113.9803°E', alt: '海拔 16.8m', resp: '中海监理 张工', respUnit: '中海监理', reporter: 'Arcadis PMO 李工', tags: ['消防', '复核'], note: '经复核偏差在允许范围内，驳回', seed: 'c'),
  Defect(id: 'd4', part: '西楼B1地下车库顶棚裂缝', type: '裂缝', category: DefectCategory.structure, severity: DefectSeverity.red, status: DefectStatus.doing, anchor: '西楼B1-车库', floor: '西楼B1', ts: '2026-08-07 11:08', gps: '22.5936°N 113.9799°E', alt: '海拔 -4.2m', resp: '深圳市建工集团 王工', respUnit: '深圳市建工集团', reporter: 'Arcadis PMO 李工', tags: ['结构安全', '挂网处理'], note: '已挂网处理，待复检', seed: 'd'),
  Defect(id: 'd5', part: '连廊1F屋面女儿墙泛水开裂', type: '开裂', category: DefectCategory.architecture, severity: DefectSeverity.orange, status: DefectStatus.draft, anchor: '连廊1F-屋面', floor: '连廊1F', ts: '2026-08-08 10:22', gps: '22.5937°N 113.9800°E', alt: '海拔 19.5m', resp: '防水班组 赵工', respUnit: '防水班组', reporter: '现场监理 王工', tags: ['防水', '屋面'], note: '需重新做泛水节点', seed: 'e'),
  Defect(id: 'd6', part: '东楼1F门诊大厅地砖空鼓', type: '空鼓', category: DefectCategory.decoration, severity: DefectSeverity.green, status: DefectStatus.done, anchor: '东楼1F-门诊大厅', floor: '东楼1F', ts: '2026-08-04 15:30', gps: '22.5938°N 113.9801°E', alt: '海拔 18.5m', resp: '深圳市建安（集团）股份 周工', respUnit: '深圳市建安集团', reporter: '现场监理 陈工', tags: ['精装修', '观感'], note: '已更换并重铺', seed: 'f'),
];

const Map<String, List<TimelinePhoto>> timeline = {
  '西楼1F-左病房翼': [
    TimelinePhoto(date: '2026-07-12', state: 'before', caption: '墙面空鼓初现，敲击有空响', verified: true),
    TimelinePhoto(date: '2026-07-28', state: 'mid', caption: '注浆施工中', verified: true),
    TimelinePhoto(date: '2026-08-08', state: 'after', caption: '注浆后复查无空鼓', verified: true),
  ],
};

/// 「上次真实模型返回」的还原数据（钢筋锈蚀 / 斜置散置钢筋）。
/// 供 mock 模式拍照后展示，用于还原真实接口效果。
const List<VlDefect> realSteelDefects = [
  VlDefect(
    name: '钢筋锈蚀',
    severity: DefectSeverity.red,
    conf: 1.0,
    desc: '柱筋上部箍筋及部分竖向钢筋表面锈蚀明显，呈黄褐色，超出正常浮锈范围，绑扎前未进行除锈处理，需除锈并复验后方可浇筑。',
  ),
  VlDefect(
    name: '斜置散置钢筋（支撑固定不规范）',
    severity: DefectSeverity.orange,
    conf: 1.0,
    desc: '一根钢筋斜搭于柱钢筋笼上，仅中部一处用扎丝简单绑扎，两端均未与柱笼或板面钢筋网有效锚固固定，不能起到定尺撑稳固作用，属散置乱摆钢筋，应清除或按防倾倒措施要求重新固定。',
  ),
];

/// VL 模拟识别：按锚点关键词返回缺陷列表（对齐原型 app.js vlPreset）。
/// [replayReal] 为 true 时固定返回「上次真实模型返回」还原数据（拍照后 mock 展示）。
List<VlDefect> vlPreset(String anchor, {bool replayReal = false}) {
  if (replayReal) return realSteelDefects;
  final kw = anchor.toLowerCase();
  if (kw.contains('渗漏') || kw.contains('b1') || kw.contains('b2')) {
    return const [
      VlDefect(name: '墙面渗漏', severity: DefectSeverity.red, conf: 0.96),
      VlDefect(name: '湿渍返潮', severity: DefectSeverity.orange, conf: 0.88),
    ];
  }
  if (kw.contains('裂缝') || kw.contains('顶棚')) {
    return const [
      VlDefect(name: '结构性裂缝', severity: DefectSeverity.orange, conf: 0.93),
      VlDefect(name: '表面裂缝', severity: DefectSeverity.green, conf: 0.81),
    ];
  }
  return const [
    VlDefect(name: '墙面空鼓', severity: DefectSeverity.orange, conf: 0.91),
    VlDefect(name: '表面裂缝', severity: DefectSeverity.green, conf: 0.79),
  ];
}

/// 楼层名称 → 图纸 key（对齐原型 app.js floorToDrawingKey）。
String floorToDrawingKey(String floor) {
  switch (floor) {
    case '东楼1F':
      return 'nkf_east_1f';
    case '总平面图':
      return 'nkf_total';
    default:
      return 'nkf_west_1f';
  }
}

/// 蓝图原稿清单（P4 蓝图预览页图纸切换用）。
const List<Map<String, String>> blueprintDrawings = [
  {'key': 'nkf_west_1f', 'label': '西楼1F', 'title': '西楼·一层平面图', 'src': 'assets/drawings/nkf_west_1f.png'},
  {'key': 'nkf_east_1f', 'label': '东楼1F', 'title': '东楼·一层平面图', 'src': 'assets/drawings/nkf_east_1f.png'},
  {'key': 'nkf_total', 'label': '总平面图', 'title': '总平面图', 'src': 'assets/drawings/nkf_total.png'},
];

// ==================== 7栋 · 第一轮测试 CAD 图纸 ====================
// 10 张 7栋真实 DWG 已转成 OCF，缓存于 server/ocf_cache/。
// Drawing.cadOcfKey 关联 OCF key，图纸查看页据此走 CAD 渲染/占位。
// src 为空（无 PNG），由 CAD 服务提供。

const List<Floor> dy7Floors = [
  Floor(key: 'dy04_7_B05', name: '地下室夹层组合平面图', index: 0, cached: true, progress: 100, building: '7栋', floor: 'B1'),
  Floor(key: 'dy04_7_B02', name: '地下一层顶板分区平面图(一)', index: 1, cached: true, progress: 100, building: '7栋', floor: 'B1'),
  Floor(key: 'dy04_7_D01', name: 'A座 1-1 剖面图', index: 2, cached: true, progress: 100, building: '7栋', floor: '剖面'),
  Floor(key: 'dy04_7_D03', name: 'B座 剖面图绑定版', index: 3, cached: true, progress: 100, building: '7栋', floor: '剖面'),
  Floor(key: 'dy04_7_K01', name: '墙身详图（一）', index: 4, cached: true, progress: 100, building: '7栋', floor: '详图'),
  Floor(key: 'dy04_7_K02', name: '墙身详图（二）', index: 5, cached: true, progress: 100, building: '7栋', floor: '详图'),
  Floor(key: 'dy04_7_E01', name: 'A座 楼梯详图（一）', index: 6, cached: true, progress: 100, building: '7栋', floor: '详图'),
  Floor(key: 'dy04_7_F01', name: 'B座 楼梯剖面图绑定版', index: 7, cached: true, progress: 100, building: '7栋', floor: '详图'),
  Floor(key: 'dy04_7_J01', name: 'A座 门窗详图（一）', index: 8, cached: true, progress: 100, building: '7栋', floor: '详图'),
  Floor(key: 'dy04_7_J04', name: '门窗详图绑定版', index: 9, cached: true, progress: 100, building: '7栋', floor: '详图'),
];

const Map<String, Drawing> dy7Drawings = {
  'dy04_7_B05': Drawing(
      key: 'dy04_7_B05', title: '地下室夹层组合平面图', crumb: '7栋 B1', variant: 'plan',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_B05'),
  'dy04_7_B02': Drawing(
      key: 'dy04_7_B02', title: '地下一层顶板分区平面图(一)', crumb: '7栋 B1', variant: 'plan',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_B02'),
  'dy04_7_D01': Drawing(
      key: 'dy04_7_D01', title: 'A座 1-1 剖面图', crumb: '7栋 剖面', variant: 'section',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_D01'),
  'dy04_7_D03': Drawing(
      key: 'dy04_7_D03', title: 'B座 剖面图绑定版', crumb: '7栋 剖面', variant: 'section',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_D03'),
  'dy04_7_K01': Drawing(
      key: 'dy04_7_K01', title: '墙身详图（一）', crumb: '7栋 详图', variant: 'detail',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_K01'),
  'dy04_7_K02': Drawing(
      key: 'dy04_7_K02', title: '墙身详图（二）', crumb: '7栋 详图', variant: 'detail',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_K02'),
  'dy04_7_E01': Drawing(
      key: 'dy04_7_E01', title: 'A座 楼梯详图（一）', crumb: '7栋 详图', variant: 'detail',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_E01'),
  'dy04_7_F01': Drawing(
      key: 'dy04_7_F01', title: 'B座 楼梯剖面图绑定版', crumb: '7栋 详图', variant: 'detail',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_F01'),
  'dy04_7_J01': Drawing(
      key: 'dy04_7_J01', title: 'A座 门窗详图（一）', crumb: '7栋 详图', variant: 'detail',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_J01'),
  'dy04_7_J04': Drawing(
      key: 'dy04_7_J04', title: '门窗详图绑定版', crumb: '7栋 详图', variant: 'detail',
      src: '', w: 2400, h: 1200, hotspots: [], cadOcfKey: 'dy04_7_J04'),
};

// ==================== 7栋 · 巡检缺陷 mock ====================
// 7栋第一轮测试 CAD 关联的真实巡检缺陷（与图纸楼层对应）。
// 7栋项目切换时展示；南科大项目继续用原有 defects。

const List<Defect> dy7Defects = [
  Defect(
      id: 'dy7_1', part: 'B1-轴交A-F/4-7 顶板裂缝',
      type: '裂缝',
      category: DefectCategory.structure,
      severity: DefectSeverity.red,
      status: DefectStatus.draft,
      anchor: 'B1-顶板-A-F/4-7',
      floor: 'B1',
      ts: '2026-08-15 09:42',
      gps: '22.5936°N 113.9799°E',
      alt: '海拔 -4.5m',
      resp: '中建四局 张工',
      respUnit: '中建四局',
      reporter: 'Arcadis PMO 李工',
      tags: ['结构安全', '深基坑区域'],
      note: '顶板出现多条贯穿裂缝，需加固处理',
      seed: 'dy7a'),
  Defect(
      id: 'dy7_2', part: 'B1-电梯井 渗漏',
      type: '渗漏',
      category: DefectCategory.water,
      severity: DefectSeverity.orange,
      status: DefectStatus.doing,
      anchor: 'B1-电梯井',
      floor: 'B1',
      ts: '2026-08-14 14:15',
      gps: '22.5936°N 113.9799°E',
      alt: '海拔 -4.8m',
      resp: '防水班组 赵工',
      respUnit: '防水班组',
      reporter: '现场监理 王工',
      tags: ['渗漏', '注浆处理'],
      note: '已注浆封堵，复查中',
      seed: 'dy7b'),
  Defect(
      id: 'dy7_3', part: '1-1剖面 楼板钢筋外露',
      type: '钢筋外露',
      category: DefectCategory.structure,
      severity: DefectSeverity.red,
      status: DefectStatus.draft,
      anchor: '1-1剖面-A区',
      floor: '剖面',
      ts: '2026-08-15 11:08',
      gps: '22.5936°N 113.9799°E',
      alt: '海拔 -3.2m',
      resp: '中建四局 张工',
      respUnit: '中建四局',
      reporter: 'Arcadis PMO 李工',
      tags: ['结构安全', '钢筋工程'],
      note: '楼板底部钢筋外露 50cm 长度，需补强',
      seed: 'dy7c'),
  Defect(
      id: 'dy7_4', part: '墙身详图 防水层破损',
      type: '防水破损',
      category: DefectCategory.architecture,
      severity: DefectSeverity.yellow,
      status: DefectStatus.done,
      anchor: '墙身-A',
      floor: '详图',
      ts: '2026-08-12 16:20',
      gps: '22.5936°N 113.9799°E',
      alt: '海拔 -4.0m',
      resp: '防水班组 赵工',
      respUnit: '防水班组',
      reporter: '现场监理 王工',
      tags: ['防水', '已闭环'],
      note: '已修复并验收通过',
      seed: 'dy7d'),
  Defect(
      id: 'dy7_5', part: '楼梯详图 踏步高度偏差',
      type: '尺寸偏差',
      category: DefectCategory.decoration,
      severity: DefectSeverity.green,
      status: DefectStatus.doing,
      anchor: '楼梯-LT01',
      floor: '详图',
      ts: '2026-08-13 10:05',
      gps: '22.5936°N 113.9799°E',
      alt: '海拔 -2.5m',
      resp: '精装单位 周工',
      respUnit: '精装单位',
      reporter: '现场监理 陈工',
      tags: ['精装修', '观感'],
      note: '踏步高度偏差 5mm，调整中',
      seed: 'dy7e'),
  Defect(
      id: 'dy7_6', part: '门窗详图 框体安装偏位',
      type: '安装偏位',
      category: DefectCategory.decoration,
      severity: DefectSeverity.yellow,
      status: DefectStatus.reject,
      anchor: '门窗-J01',
      floor: '详图',
      ts: '2026-08-11 15:30',
      gps: '22.5936°N 113.9799°E',
      alt: '海拔 -1.8m',
      resp: '方大建科 吴工',
      respUnit: '方大建科',
      reporter: '现场监理 陈工',
      tags: ['幕墙', '安装精度'],
      note: '复测在允许范围内，驳回',
      seed: 'dy7f'),
];
