import 'package:flutter/material.dart';

/// 数据模型（mock 阶段用纯 Dart 类；接真实 API 时再补 freezed / json_serializable）。

enum DefectStatus { draft, doing, done, reject }

extension DefectStatusX on DefectStatus {
  String get label {
    switch (this) {
      case DefectStatus.draft:
        return '待整改';
      case DefectStatus.doing:
        return '整改中';
      case DefectStatus.done:
        return '已销项';
      case DefectStatus.reject:
        return '已拒绝';
    }
  }

  Color get color {
    switch (this) {
      case DefectStatus.draft:
        return const Color(0xFFDC2626);
      case DefectStatus.doing:
        return const Color(0xFFEA580C);
      case DefectStatus.done:
        return const Color(0xFF16A34A);
      case DefectStatus.reject:
        return const Color(0xFF64748B);
    }
  }

  Color get soft {
    switch (this) {
      case DefectStatus.draft:
        return const Color(0xFFFEE2E2);
      case DefectStatus.doing:
        return const Color(0xFFFFEDD5);
      case DefectStatus.done:
        return const Color(0xFFDCFCE7);
      case DefectStatus.reject:
        return const Color(0xFFF1F5F9);
    }
  }
}

enum DefectSeverity { low, mid, high }

extension DefectSeverityX on DefectSeverity {
  String get label {
    switch (this) {
      case DefectSeverity.low:
        return '轻微';
      case DefectSeverity.mid:
        return '中等';
      case DefectSeverity.high:
        return '高';
    }
  }

  Color get color {
    switch (this) {
      case DefectSeverity.low:
        return const Color(0xFFCA8A04);
      case DefectSeverity.mid:
        return const Color(0xFFEA580C);
      case DefectSeverity.high:
        return const Color(0xFFDC2626);
    }
  }

  /// 软底色（用于徽标/卡片背景）。
  Color get soft {
    switch (this) {
      case DefectSeverity.low:
        return const Color(0xFFFEF3C7);
      case DefectSeverity.mid:
        return const Color(0xFFFFEDD5);
      case DefectSeverity.high:
        return const Color(0xFFFEE2E2);
    }
  }
}

/// 项目参与方（甲方 / 设计院 / 监理 / 咨询 / PMO 等）。
class Party {
  final String role; // 角色，如 "甲方（业主方）"、"设计院（LDI）" 等
  final String org; // 单位全称，如 "腾讯科技（深圳）有限公司"
  final String contact; // 代表/对接人，如 "林心荃"
  final String title; // 代表职务，如 "业主代表"
  const Party({
    required this.role,
    required this.org,
    required this.contact,
    required this.title,
  });
}

/// 系统用户（参与方代表）。头像点击可切换当前用户。
class User {
  final String id;
  final String name; // 姓名，如 "欧阳嘉"
  final String org; // 单位，如 "Arcadis（凯迪思）"
  final String role; // 角色，如 "全过程咨询 / PMO"
  final String avatar; // assets 头像路径
  const User({
    required this.id,
    required this.name,
    required this.org,
    required this.role,
    required this.avatar,
  });
}

class Project {
  final String id; // 项目唯一标识（多项目切换用）
  final String name;
  final String client;
  final String location;
  final String status;
  final String siteArea;
  final String floorArea;
  final int beds;
  final String concept;
  /// 参与方列表（甲方 / 设计院 / 监理 / 咨询 / PMO）。
  final List<Party> parties;
  const Project({
    required this.id,
    required this.name,
    required this.client,
    required this.location,
    required this.status,
    required this.siteArea,
    required this.floorArea,
    required this.beds,
    required this.concept,
    this.parties = const [],
  });
}

class Floor {
  final String key;
  final String name;
  final int index;
  final bool cached;
  final int progress;
  final String building;
  final String floor;
  const Floor({
    required this.key,
    required this.name,
    required this.index,
    required this.cached,
    required this.progress,
    required this.building,
    required this.floor,
  });
}

class Hotspot {
  final int num;
  final String label;
  final String target;
  final double x; // 0~1 相对坐标
  final double y; // 0~1 相对坐标
  const Hotspot({
    required this.num,
    required this.label,
    required this.target,
    required this.x,
    required this.y,
  });
}

class Drawing {
  final String key;
  final String title;
  final String crumb;
  final String variant;
  final String src; // assets 路径
  final double w;
  final double h;
  final List<Hotspot> hotspots;
  const Drawing({
    required this.key,
    required this.title,
    required this.crumb,
    required this.variant,
    required this.src,
    required this.w,
    required this.h,
    required this.hotspots,
  });
}

class AnchorPhoto {
  final String file;
  final String date;
  final String caption;
  const AnchorPhoto({
    required this.file,
    required this.date,
    required this.caption,
  });
}

class PhotoAnchor {
  final String id;
  final double x;
  final double y;
  final String label;
  final String? labelPos;
  final List<AnchorPhoto> photos;
  const PhotoAnchor({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    this.labelPos,
    required this.photos,
  });
}

class Defect {
  final String id;
  final String part;
  final String type;
  final DefectSeverity severity;
  final DefectStatus status;
  final String anchor;
  final String floor;
  final String ts;
  final String gps;
  final String alt;
  final String resp;
  final String note;
  final String seed;
  const Defect({
    required this.id,
    required this.part,
    required this.type,
    required this.severity,
    required this.status,
    required this.anchor,
    required this.floor,
    required this.ts,
    required this.gps,
    required this.alt,
    required this.resp,
    required this.note,
    required this.seed,
  });
}

class TimelinePhoto {
  final String date;
  final String state; // before / mid / after
  final String caption;
  final bool verified;
  const TimelinePhoto({
    required this.date,
    required this.state,
    required this.caption,
    required this.verified,
  });
}

/// 拍照验收路由参数：楼层 + 预锚定部位 + 相对坐标（0~1）。
class CaptureArgs {
  final String floor;
  final String anchorLabel;
  final double x;
  final double y;
  const CaptureArgs({
    this.floor = '西楼1F',
    this.anchorLabel = '待选点',
    this.x = 0.5,
    this.y = 0.5,
  });
}

/// VL 识别的缺陷结果。
class VlDefect {
  final String name;
  final DefectSeverity severity;
  final double conf;
  /// 缺陷描述（真实模型返回；mock 阶段为空）。
  final String? desc;
  const VlDefect({
    required this.name,
    required this.severity,
    required this.conf,
    this.desc,
  });
}
