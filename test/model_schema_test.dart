import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/core/utils/ids.dart';
import 'package:gongdi_app/data/models.dart';

/// A/B/C 三类（后台录入 → 客户端承接）新增/改造模型的结构与序列化约定。
///
/// 这组测试是**给后端看的契约**：字段名、类型、缺省值、兼容旧数据的容错行为。
void main() {
  group('ULID（客户端本地 ID）', () {
    test('newId 为 26 位 Crockford Base32，且通过 isUlid', () {
      final id = newId();
      expect(id.length, 26);
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(id), isTrue,
          reason: '非法 ULID: $id');
      expect(isUlid(id), isTrue);
      // 不含易混淆字符 I / L / O / U。
      expect(RegExp(r'[ILOU]').hasMatch(id), isFalse);
    });

    test('时间戳前缀单调：同毫秒连续生成也唯一且有序', () {
      const ms = 1700000000000;
      final ids = [for (var i = 0; i < 50; i++) newId(nowMs: ms)];
      expect(ids.toSet().length, 50, reason: '同毫秒生成出现重复 ID');
      final sorted = [...ids]..sort();
      expect(sorted, ids, reason: '同毫秒生成的 ID 应按字典序递增');
      // 前 10 位编码时间戳，同一毫秒内完全一致。
      expect(ids.every((e) => e.substring(0, 10) == ids.first.substring(0, 10)),
          isTrue);
    });

    test('时钟回拨不产生重复或倒退', () {
      final a = newId(nowMs: 1700000005000);
      final b = newId(nowMs: 1700000000000); // 回拨 5s
      expect(a == b, isFalse);
      expect(b.compareTo(a) > 0, isTrue, reason: '回拨后 ID 仍应大于已生成的最大值');
    });

    test('isUlid 拒绝历史可读 id 与非法长度', () {
      expect(isUlid('d1'), isFalse);
      expect(isUlid('dy7_1'), isFalse);
      expect(isUlid(''), isFalse);
      expect(isUlid(null), isFalse);
      expect(isUlid('0' * 25), isFalse);
    });
  });

  group('A1 Org / A2 User / B3 Party', () {
    test('Org 往返，type 默认 other（字符串可扩展，不用 enum）', () {
      const org = Org(
        id: 'o1',
        name: '深圳市建筑设计研究总院',
        shortName: '深总院',
        type: Org.typeDesign,
        sort: 2,
      );
      final back = Org.fromJson(org.toJson());
      expect(back.id, 'o1');
      expect(back.shortName, '深总院');
      expect(back.type, Org.typeDesign);
      expect(back.sort, 2);
      expect(Org.fromJson(const {}).type, Org.typeOther);
      expect(Org.fromJson(const {}).sort, 0);
    });

    test('User 往返：补 orgId/phone/email/status，缺省 active', () {
      const u = User(
        id: 'u1',
        name: '杨玉婷',
        orgId: 'o3',
        org: '深圳华西建设工程管理有限公司',
        role: '施工监理',
        avatar: 'assets/avatars/yang-gong.jpg',
        phone: '13800000000',
        email: 'yang@example.com',
      );
      final back = User.fromJson(u.toJson());
      expect(back.orgId, 'o3');
      expect(back.phone, '13800000000');
      expect(back.status, User.statusActive);
      expect(User.fromJson(const {'id': 'x'}).status, User.statusActive);
      expect(User.fromJson(const {'id': 'x'}).email, '');
    });

    test('Party 往返：新增 id/orgId/contactUserId，保留展示冗余字段', () {
      const p = Party(
        id: 'p1',
        role: '甲方（业主方）',
        orgId: 'o1',
        org: '腾讯科技（深圳）有限公司',
        contact: '林心荃',
        contactUserId: 'u2',
        title: '业主代表',
      );
      final back = Party.fromJson(p.toJson());
      expect(back.id, 'p1');
      expect(back.orgId, 'o1');
      expect(back.contactUserId, 'u2');
      expect(back.org, '腾讯科技（深圳）有限公司');
      expect(Party.fromJson(const {}).contactUserId, '');
    });

    test('Discipline 往返：code + 展示名 + 排序 + 系统预置标记', () {
      const d = Discipline(
        code: Discipline.hvac,
        name: '暖通',
        sort: 4,
        isSystem: true,
      );
      final back = Discipline.fromJson(d.toJson());
      expect(back.code, 'hvac');
      expect(back.name, '暖通');
      expect(back.sort, 4);
      expect(back.isSystem, isTrue);
      // 容错：缺字段不抛错，isSystem 默认 false。
      final empty = Discipline.fromJson(const {});
      expect(empty.code, '');
      expect(empty.isSystem, isFalse);
      expect(empty.sort, 0);
    });

    test('DefectCategory.fromCode：未知专业回落 other（不抛错）', () {
      expect(DefectCategory.fromCode('hvac'), DefectCategory.hvac);
      expect(DefectCategory.fromCode('architecture'), DefectCategory.architecture);
      // 后台新增但客户端未发版的专业 → 回落 other（功能不崩，过滤会失真）
      expect(DefectCategory.fromCode('landscape'), DefectCategory.other);
      expect(DefectCategory.fromCode(null), DefectCategory.other);
      expect(DefectCategory.fromCode(''), DefectCategory.other);
    });
  });

  group('B4 Milestone', () {
    test('往返含 actualDate；done 缺省时由 actualDate 推导', () {
      const m = Milestone(
        id: 'ms1',
        name: '主体结构封顶',
        date: '2026-01-31',
        actualDate: '2026-01-28',
      );
      final back = Milestone.fromJson(m.toJson());
      expect(back.id, 'ms1');
      expect(back.date, '2026-01-31');
      expect(back.actualDate, '2026-01-28');
      expect(back.done, isFalse); // 显式 false 优先
      expect(back.isDone, isTrue, reason: 'isDone 应合并 actualDate');

      // 后台只给计划 + 实际日期：done 自动推导为 true。
      final derived = Milestone.fromJson(const {
        'id': 'ms2',
        'name': '竣工验收',
        'date': '2027-06-30',
        'actualDate': '2027-06-20',
      });
      expect(derived.done, isTrue);

      // 两者都缺：未完成。
      final pending = Milestone.fromJson(const {'name': '精装修', 'date': '2026-12-31'});
      expect(pending.done, isFalse);
      expect(pending.isDone, isFalse);
      expect(pending.actualDate, '');
    });
  });

  group('B1/B2 Project', () {
    test('往返含 lat/lng、parties、milestones', () {
      const p = Project(
        id: 'nkf',
        name: '南方科技大学附属医院（校本部）',
        client: '深圳市建筑工务署',
        location: '深圳市南山区西丽大学城',
        status: '已封顶',
        siteArea: '5.68万㎡',
        floorArea: '16.76万㎡',
        beds: 800,
        concept: '山水动脉',
        lat: 22.5906,
        lng: 113.9699,
        parties: [Party(role: '监理', org: '华西', contact: '杨工', title: '总监')],
        milestones: [Milestone(id: 'm1', name: '封顶', date: '2026-01-31')],
      );
      final back = Project.fromJson(p.toJson());
      expect(back.lat, 22.5906);
      expect(back.lng, 113.9699);
      expect(back.parties.single.org, '华西');
      expect(back.milestones.single.name, '封顶');
      expect(back.beds, 800);
    });

    test('容错：缺 parties/milestones/lat 不抛错', () {
      final p = Project.fromJson(const {'id': 'x', 'name': 'y'});
      expect(p.parties, isEmpty);
      expect(p.milestones, isEmpty);
      expect(p.lat, isNull);
    });
  });

  group('B5 Floor', () {
    test('toJson 有意排除本地缓存态 cached/progress', () {
      const f = Floor(
        key: 'B05',
        projectId: 'p1',
        name: 'B05',
        index: 3,
        cached: true,
        progress: 100,
        building: '7栋',
        floor: 'B1',
      );
      final j = f.toJson();
      expect(j.containsKey('cached'), isFalse);
      expect(j.containsKey('progress'), isFalse);
      expect(j['projectId'], 'p1');

      final back = Floor.fromJson(j);
      expect(back.cached, isFalse);
      expect(back.progress, 0);
      expect(back.building, '7栋');
    });
  });

  group('C1 Drawing / DrawingVersion + Hotspot', () {
    test('Drawing 往返：projectId/discipline/publishedVersionId + 冗余快照', () {
      const d = Drawing(
        key: 'dy04_7_B05',
        projectId: 'tencent-dy04-7',
        title: 'B05 平面图',
        crumb: '7栋 平面',
        variant: 'plan',
        discipline: '建筑',
        src: 'assets/drawings/dy04_7_B05.png',
        w: 2400,
        h: 1698,
        hotspots: [Hotspot(num: 1, label: '入口', target: 'A', x: 0.1, y: 0.2)],
        publishedVersionId: 'v1',
        sort: 5,
      );
      final back = Drawing.fromJson(d.toJson());
      expect(back.projectId, 'tencent-dy04-7');
      expect(back.discipline, '建筑');
      expect(back.publishedVersionId, 'v1');
      expect(back.sort, 5);
      // 冗余快照：渲染端可直接用，无需等版本表。
      expect(back.w, 2400);
      expect(back.hotspots.single.label, '入口');
      expect(back.hotspots.single.num, 1);
      expect(back.hotspots.single.x, 0.1);
    });

    test('DrawingVersion 往返：state/尺寸/热点/发布信息', () {
      const v = DrawingVersion(
        id: 'dv1',
        drawingKey: 'dy04_7_B05',
        version: 'V1.0',
        versionDate: '2026-08-01',
        state: DrawingVersion.statePublished,
        baseImagePath: 'drawings/p1/dy04_7_B05/v1/preview.png',
        width: 2400,
        height: 1698,
        bounds: '0,0,72000,48000',
        hotspots: [Hotspot(num: 1, label: '入口', target: 'A', x: 0.1, y: 0.2)],
        publishedAtMs: 1700000000000,
        publishedBy: 'u1',
      );
      final back = DrawingVersion.fromJson(v.toJson());
      expect(back.version, 'V1.0');
      expect(back.state, DrawingVersion.statePublished);
      expect(back.isPublished, isTrue);
      expect(back.width, 2400);
      expect(back.bounds, '0,0,72000,48000');
      expect(back.hotspots.single.num, 1);
      expect(back.publishedBy, 'u1');
      // 缺省 state = draft（上传未发布）。
      expect(DrawingVersion.fromJson(const {'id': 'x'}).state,
          DrawingVersion.stateDraft);
      expect(DrawingVersion.fromJson(const {'id': 'x'}).hotspots, isEmpty);
    });
  });

  group('C2 Calibration（坐标绑版本）', () {
    test('往返保留 drawingVersionId 与仿射系数', () {
      const c = Calibration(
        drawingKey: 'dy04_7_B05',
        drawingVersionId: 'dv1',
        raw: '{"a":1}',
        map: {'viewWidth': 2400, 'viewHeight': 1698, 'a': 1.0},
        updatedAtMs: 1700000000000,
      );
      final back = Calibration.fromJson(c.toJson());
      expect(back.drawingVersionId, 'dv1');
      expect(back.raw, '{"a":1}');
      expect(back.map['a'], 1.0);
      expect(Calibration.fromJson(const {}).drawingVersionId, '');
      expect(Calibration.fromJson(const {}).map, isEmpty);
    });
  });

  group('C4 ProgressEntry（填报身份：admin 后台录入 / contractor 施工方自报）', () {
    test('往返：默认 admin（v1 后台录入），photos/declaredBy 保留', () {
      const e = ProgressEntry(
        id: 'pe1',
        projectId: 'p1',
        milestoneId: 'ms1',
        status: ProgressEntry.statusInProgress,
        date: '2026-09-20',
        note: '已完成 3 层风管',
        photos: ['photos/a.jpg'],
        declaredBy: '项目负责人 李工',
      );
      final back = ProgressEntry.fromJson(e.toJson());
      expect(back.source, ProgressEntry.sourceAdmin);
      expect(back.status, ProgressEntry.statusInProgress);
      expect(back.photos, ['photos/a.jpg']);
      expect(back.declaredBy, '项目负责人 李工');
    });

    test('显式 contractor（v1.2 施工方自报）原样往返', () {
      const c = ProgressEntry(
        id: 'pe2',
        projectId: 'p1',
        milestoneId: 'ms1',
        declaredBy: '施工方 张三',
        source: ProgressEntry.sourceContractor,
      );
      expect(ProgressEntry.fromJson(c.toJson()).source,
          ProgressEntry.sourceContractor);
    });

    test('旧数据缺 source → 回落 contractor（历史语义，与构造默认值不同）', () {
      expect(ProgressEntry.fromJson(const {'id': 'x'}).source,
          ProgressEntry.sourceContractor);
    });
  });

  group('B6 Membership（成员 + 权限点）', () {
    test('往返：权限点是数据，判定走 PermissionScope 不认角色', () {
      const m = Membership(
        id: 'mb1',
        userId: 'u1',
        projectId: 'p1',
        roleCode: Membership.roleSiteEngineer,
        roleName: '驻场工程师',
        permissions: [Membership.permDefectCreate, Membership.permPatrolRun],
      );
      final back = Membership.fromJson(m.toJson());
      expect(back.roleCode, Membership.roleSiteEngineer);
      expect(back.permissions, contains(Membership.permDefectCreate));
      expect(back.permissions, isNot(contains(Membership.permMemberManage)));
      expect(back.status, Membership.statusActive);
      expect(back.sync.isNew, isTrue); // 未指定则为未纳管
      // 判定入口唯一：Membership 不提供 can()，统一由 PermissionScope 给。
      expect(
        PermissionScope.forProject(memberships: [back], projectId: 'p1')
            .can(Membership.permDefectCreate),
        isTrue,
      );
    });
  });

  group('可写实体补 drawingVersionId（坐标绑版本）', () {
    test('Defect 序列化包含 projectId / drawingVersionId / 取证字段', () {
      const d = Defect(
        id: 'd1',
        projectId: 'p1',
        part: 'p',
        type: 't',
        category: DefectCategory.other,
        severity: DefectSeverity.orange,
        status: DefectStatus.draft,
        anchor: 'a',
        floor: 'f',
        ts: '2026-09-20 10:00',
        gps: '',
        alt: '',
        resp: '',
        note: '',
        seed: 's',
        drawingKey: 'B05',
        drawingVersionId: 'dv1',
        photoHash: 'abc',
        watermarkSerial: 'SN-1',
      );
      final j = d.toJson();
      expect(j['projectId'], 'p1');
      expect(j['drawingVersionId'], 'dv1');
      expect(j['photoHash'], 'abc');
      expect(j['watermarkSerial'], 'SN-1');
      expect(j['lat'], isNull);
      // ts 是展示文本，规范时间戳由 tsMs 派生。
      expect(d.tsMs, isNot(0));
      expect(Defect.fromJson(j).drawingVersionId, 'dv1');
      // 旧数据（无新字段）不抛错。
      expect(Defect.fromJson(const {'id': 'x'}).drawingVersionId, '');
      expect(Defect.fromJson(const {'id': 'x'}).projectId, '');
    });

    test('MeasureSession / PatrolPlan / PatrolRecord / RoomScanRecord 均带字段', () {
      expect(
        const MeasureSession(id: 'm', projectKey: 'p', drawingKey: 'd',
                floor: 'f', drawingVersionId: 'dv1')
            .toJson()['drawingVersionId'],
        'dv1',
      );
      expect(
        const PatrolPlan(id: 'p', projectId: 'pj', drawingKey: 'd', name: 'n',
                floor: 'f', points: [], drawingVersionId: 'dv1')
            .toJson()['drawingVersionId'],
        'dv1',
      );
      expect(
        const PatrolRecord(id: 'r', planId: 'p', projectId: 'pj', drawingKey: 'd',
                name: 'n', startedAt: 0, finishedAt: 0, distKm: 0,
                pointCount: 0, issueCount: 0, drawingVersionId: 'dv1')
            .toJson()['drawingVersionId'],
        'dv1',
      );
      expect(
        const RoomScanRecord(id: 's', projectKey: 'p', name: 'n',
                scannedAtMs: 0, drawingVersionId: 'dv1')
            .toJson()['drawingVersionId'],
        'dv1',
      );
      // 缺省 = 未版本化，不抛错。
      expect(PatrolPlan.fromJson(const {'id': 'x'}).drawingVersionId, '');
      expect(RoomScanRecord.fromJson(const {'id': 'x'}).drawingVersionId, '');
    });
  });
}
