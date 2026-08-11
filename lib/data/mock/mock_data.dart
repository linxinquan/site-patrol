import '../models.dart';

/// 由原型 app.js 常量移植。src 统一用 PNG（避开 16MB SVG 卡顿）。

const Project project = Project(
  name: '南方科技大学附属医院（校本部）',
  client: '深圳市建筑工务署',
  location: '深圳市南山区西丽大学城南方科技大学校内东侧',
  status: '已封顶 · 预计 2027 年竣工',
  siteArea: '5.68万㎡',
  floorArea: '16.76万㎡',
  beds: 800,
  concept: '山水动脉',
);

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
  Defect(id: 'd1', part: '西楼1F门诊大厅墙面空鼓', type: '空鼓', severity: DefectSeverity.mid, status: DefectStatus.draft, anchor: '西楼1F-门诊大厅', floor: '西楼1F', ts: '2026-08-08 14:32', gps: '22.5936°N 113.9798°E', alt: '海拔 18.2m', resp: '深圳市建工集团 王工', note: '空鼓面积约 0.4㎡，需注浆处理', seed: 'a'),
  Defect(id: 'd2', part: '东楼4F标准层病房渗漏', type: '渗漏', severity: DefectSeverity.mid, status: DefectStatus.done, anchor: '东楼4F-住院部', floor: '东楼4F', ts: '2026-08-06 09:15', gps: '22.5938°N 113.9801°E', alt: '海拔 32.5m', resp: '深圳市建工集团 李工', note: '已注浆封堵，复查无渗水', seed: 'b'),
  Defect(id: 'd3', part: '感染楼1F 防火墙洞口偏差', type: '洞口偏差', severity: DefectSeverity.high, status: DefectStatus.reject, anchor: '感染楼1F-医辅区', floor: '感染楼1F', ts: '2026-08-05 16:40', gps: '22.5934°N 113.9803°E', alt: '海拔 16.8m', resp: '中海监理 张工', note: '经复核偏差在允许范围内，驳回', seed: 'c'),
  Defect(id: 'd4', part: '西楼B1地下车库顶棚裂缝', type: '裂缝', severity: DefectSeverity.low, status: DefectStatus.doing, anchor: '西楼B1-车库', floor: '西楼B1', ts: '2026-08-07 11:08', gps: '22.5936°N 113.9799°E', alt: '海拔 -4.2m', resp: '深圳市建工集团 王工', note: '已挂网处理，待复检', seed: 'd'),
  Defect(id: 'd5', part: '连廊1F屋面女儿墙泛水开裂', type: '开裂', severity: DefectSeverity.mid, status: DefectStatus.draft, anchor: '连廊1F-屋面', floor: '连廊1F', ts: '2026-08-08 10:22', gps: '22.5937°N 113.9800°E', alt: '海拔 19.5m', resp: '防水班组 赵工', note: '需重新做泛水节点', seed: 'e'),
  Defect(id: 'd6', part: '东楼1F门诊大厅地砖空鼓', type: '空鼓', severity: DefectSeverity.low, status: DefectStatus.done, anchor: '东楼1F-门诊大厅', floor: '东楼1F', ts: '2026-08-04 15:30', gps: '22.5938°N 113.9801°E', alt: '海拔 18.5m', resp: '精装单位 周工', note: '已更换并重铺', seed: 'f'),
];

const Map<String, List<TimelinePhoto>> timeline = {
  '西楼1F-左病房翼': [
    TimelinePhoto(date: '2026-07-12', state: 'before', caption: '墙面空鼓初现，敲击有空响', verified: true),
    TimelinePhoto(date: '2026-07-28', state: 'mid', caption: '注浆施工中', verified: true),
    TimelinePhoto(date: '2026-08-08', state: 'after', caption: '注浆后复查无空鼓', verified: true),
  ],
};
