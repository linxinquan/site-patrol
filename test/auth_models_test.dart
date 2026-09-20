import 'package:flutter_test/flutter_test.dart';

import 'package:gongdi_app/data/models.dart';

/// 认证授权域模型（登录 / 令牌 / 会话 / 权限点）的契约测试。
///
/// 后端未接入，但接口返回结构先在这里定死，避免接线时再改模型。
void main() {
  User user({
    String id = 'u1',
    String name = '杨玉婷',
    String username = 'yang',
  }) =>
      User(
        id: id,
        name: name,
        username: username,
        org: '深圳华西建设工程管理有限公司',
        role: '施工监理',
        avatar: 'assets/avatars/yang-gong.jpg',
      );

  group('User 账号档案', () {
    test('新增 username（登录名）可往返，缺省为空串', () {
      final back = User.fromJson(user().toJson());
      expect(back.username, 'yang');
      expect(back.name, '杨玉婷');
      expect(User.fromJson(const {'id': 'x'}).username, '');
      // 旧数据（无 username / status）不抛错。
      expect(User.fromJson(const {'id': 'x'}).status, User.statusActive);
    });
  });

  group('UserSession 会话态', () {
    test('往返保持既有字段形态（兼容老版本本地会话）', () {
      final s = UserSession(
        userId: 'u1',
        username: 'yang',
        displayName: '杨工',
        token: 'a.b.c',
        refreshToken: 'r.1',
        loginAt: DateTime(2026, 9, 20, 9, 30),
        expiresAt: DateTime(2026, 9, 20, 9, 45),
      );
      final j = s.toJson();
      // 键名必须保持 token / refreshToken / expiresAt（老数据兼容）。
      expect(j.keys, containsAll(['token', 'refreshToken', 'expiresAt']));
      final back = UserSession.fromJson(j);
      expect(back.userId, 'u1');
      expect(back.displayName, '杨工');
      expect(back.token, 'a.b.c');
      expect(back.expiresAt, DateTime(2026, 9, 20, 9, 45));
      expect(back.hasToken, isTrue);
    });

    test('老数据只含 4 个必需字段也能读回', () {
      final back = UserSession.fromJson(const {
        'userId': 'demo',
        'username': 'demo',
        'displayName': '演示用户',
      });
      expect(back.userId, 'demo');
      expect(back.token, isNull);
      expect(back.hasToken, isFalse);
      expect(back.expiresAt, isNull);
      expect(back.isExpired, isFalse, reason: '无过期时间 = 长期有效');
    });

    test('过期判断', () {
      final expired = UserSession(
        userId: 'u',
        username: 'u',
        displayName: 'u',
        loginAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 2),
      );
      expect(expired.isExpired, isTrue);
    });

    test('fromLogin：由登录响应构造会话（令牌 → token，过期 ms → DateTime）', () {
      final result = LoginResult(
        tokens: const AuthTokens(
          accessToken: 'A',
          refreshToken: 'R',
          accessExpiresAtMs: 1790000000000,
        ),
        user: user(),
        memberships: const [],
      );
      final s = UserSession.fromLogin(result, now: DateTime(2026, 9, 20));
      expect(s.userId, 'u1');
      expect(s.username, 'yang');
      expect(s.displayName, '杨玉婷');
      expect(s.token, 'A');
      expect(s.refreshToken, 'R');
      expect(s.loginAt, DateTime(2026, 9, 20));
      expect(s.expiresAt, DateTime.fromMillisecondsSinceEpoch(1790000000000));

      // 空令牌 → null（测试期占位会话）。
      final plain = UserSession.fromLogin(
        LoginResult(tokens: const AuthTokens(), user: user()),
      );
      expect(plain.token, isNull);
      expect(plain.refreshToken, isNull);
      expect(plain.expiresAt, isNull);
    });
  });

  group('AuthTokens 令牌', () {
    test('往返', () {
      const t = AuthTokens(
        accessToken: 'A',
        refreshToken: 'R',
        accessExpiresAtMs: 1000,
        refreshExpiresAtMs: 2000,
      );
      final back = AuthTokens.fromJson(t.toJson());
      expect(back.accessToken, 'A');
      expect(back.refreshExpiresAtMs, 2000);
      expect(back.isAccessExpired, isTrue, reason: '1000ms 早已过期');
    });

    test('兼容后端简写 access / refresh 与 ISO 文本过期时间', () {
      final t = AuthTokens.fromJson(const {
        'access': 'A',
        'refresh': 'R',
        'expiresAt': '2026-09-20T09:45:00',
      });
      expect(t.accessToken, 'A');
      expect(t.refreshToken, 'R');
      expect(t.accessExpiresAtMs,
          DateTime.parse('2026-09-20T09:45:00').millisecondsSinceEpoch);
      // 同时兼容 `yyyy-MM-dd HH:mm:ss` 与 epoch 毫秒。
      expect(AuthTokens.fromJson(const {'expiresAt': '2026-09-20 09:45:00'})
          .accessExpiresAtMs,
          DateTime.parse('2026-09-20T09:45:00').millisecondsSinceEpoch);
      expect(AuthTokens.fromJson(const {'expiresAt': 1700000000000})
          .accessExpiresAtMs, 1700000000000);
      // 缺字段 / 脏数据不抛错。
      final empty = AuthTokens.fromJson(const {'expiresAt': 'not-a-time'});
      expect(empty.accessToken, '');
      expect(empty.accessExpiresAtMs, 0);
      expect(empty.isAccessExpired, isFalse, reason: '0 = 未提供，视为不过期');
    });
  });

  group('LoginResult / AuthProfile', () {
    test('推荐形态：memberships 逐项目权限', () {
      final r = LoginResult.fromJson({
        'tokens': {'accessToken': 'A', 'refreshToken': 'R'},
        'user': {'id': 'u1', 'name': '杨工', 'username': 'yang'},
        'memberships': [
          {
            'id': 'm1',
            'userId': 'u1',
            'projectId': 'nkf',
            'roleCode': 'site_engineer',
            'permissions': ['defect.create', 'patrol.run'],
          },
        ],
      });
      expect(r.user.username, 'yang');
      expect(r.tokens.accessToken, 'A');
      expect(r.memberships.single.projectId, 'nkf');
      expect(r.canSeeProject('nkf'), isTrue);
      expect(r.canSeeProject('other'), isFalse);
    });

    test('兜底形态：只返回扁平 permissions', () {
      final r = LoginResult.fromJson(const {
        'access': 'A',
        'refresh': 'R',
        'user': {'id': 'u1', 'name': '杨工'},
        'permissions': ['defect.reply'],
      });
      expect(r.memberships, hasLength(1));
      expect(r.memberships.single.projectId, '');
      expect(r.memberships.single.permissions, ['defect.reply']);
    });

    test('AuthProfile.scopeOf：按项目取权限视图', () {
      final p = AuthProfile.fromJson({
        'user': {'id': 'u1', 'name': '杨工'},
        'memberships': [
          {
            'id': 'm1',
            'userId': 'u1',
            'projectId': 'nkf',
            'permissions': ['defect.create', 'defect.close'],
          },
          {
            'id': 'm2',
            'userId': 'u1',
            'projectId': 'tencent-dy04-7',
            'permissions': ['measure.write'],
          },
        ],
      });
      final nkf = p.scopeOf('nkf');
      expect(nkf.can(Membership.permDefectClose), isTrue);
      expect(nkf.can(Membership.permMeasureWrite), isFalse);
      expect(p.scopeOf('tencent-dy04-7').can(Membership.permMeasureWrite), isTrue);
      // 非成员项目 → 空权限。
      expect(p.scopeOf('unknown').isEmpty, isTrue);
    });

    test('往返', () {
      final r = LoginResult(
        tokens: const AuthTokens(accessToken: 'A'),
        user: user(),
        memberships: const [
          Membership(
            id: 'm1',
            userId: 'u1',
            projectId: 'nkf',
            permissions: ['defect.create'],
          ),
        ],
      );
      final back = LoginResult.fromJson(r.toJson());
      expect(back.tokens.accessToken, 'A');
      expect(back.user.id, 'u1');
      expect(back.memberships.single.permissions,
          contains(Membership.permDefectCreate));

      final p = AuthProfile(user: user(), memberships: r.memberships);
      expect(AuthProfile.fromJson(p.toJson()).scopeOf('nkf').permissions,
          {'defect.create'});
    });
  });

  group('PermissionScope 权限点集合', () {
    test('none 为空权限', () {
      expect(PermissionScope.none.isEmpty, isTrue);
      expect(PermissionScope.none.can(Membership.permDefectCreate), isFalse);
    });

    test('forProject：只取该项目的权限并集，跳过停用成员', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(
            id: 'm1',
            userId: 'u1',
            projectId: 'nkf',
            permissions: ['a', 'b'],
          ),
          Membership(
            id: 'm2',
            userId: 'u2',
            projectId: 'nkf',
            permissions: ['c'],
          ),
          Membership(
            id: 'm3',
            userId: 'u3',
            projectId: 'nkf',
            permissions: ['d'],
            status: Membership.statusDisabled,
          ),
          Membership(
            id: 'm4',
            userId: 'u1',
            projectId: 'other',
            permissions: ['e'],
          ),
        ],
        projectId: 'nkf',
      );
      expect(scope.permissions, {'a', 'b', 'c'});
      expect(scope.can('a'), isTrue);
      expect(scope.can('e'), isFalse);
      expect(scope.projectId, 'nkf');
    });

    test('扁平 permissions（projectId 为空）不按项目过滤', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(id: 'm', userId: '', projectId: '', permissions: ['x']),
        ],
        projectId: 'nkf',
      );
      expect(scope.can('x'), isTrue);
    });

    test('按 userId 过滤', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(id: 'm1', userId: 'u1', projectId: 'nkf', permissions: ['a']),
          Membership(id: 'm2', userId: 'u2', projectId: 'nkf', permissions: ['b']),
        ],
        projectId: 'nkf',
        userId: 'u2',
      );
      expect(scope.permissions, {'b'});
    });
  });

  group('B6 Membership：职责 × 专业 × 单位（三个正交维度）', () {
    test('三维字段可往返', () {
      const m = Membership(
        id: 'mb1',
        userId: 'u1',
        projectId: 'p1',
        orgId: 'org-cscec4',
        roleCode: Membership.roleDisciplineLead,
        roleName: '暖通专业负责人',
        disciplines: [Discipline.hvac],
        permissions: [Membership.permDefectClose, Membership.permReportExport],
      );
      final back = Membership.fromJson(m.toJson());
      expect(back.orgId, 'org-cscec4');
      expect(back.roleCode, Membership.roleDisciplineLead);
      expect(back.roleName, '暖通专业负责人');
      expect(back.disciplines, [Discipline.hvac]);
      // Membership 只承载数据，不提供判定方法（判定统一走 PermissionScope）。
      expect(back.permissions, contains(Membership.permDefectClose));
    });

    test('disciplines 空 = 数据上未限定专业（第一版默认情况）', () {
      const pm = Membership(
        id: 'm',
        userId: 'u',
        projectId: 'p',
        roleCode: Membership.roleProjectManager,
        roleName: '项目负责人',
      );
      expect(pm.isAllDisciplines, isTrue);
      expect(pm.disciplines, isEmpty);
    });

    test('「只做结构专业」时：disciplines 填单元素', () {
      const lead = Membership(
        id: 'm',
        userId: 'u',
        projectId: 'p',
        roleCode: Membership.roleDisciplineLead,
        disciplines: [Discipline.structure],
      );
      expect(lead.isAllDisciplines, isFalse);
      expect(lead.disciplines, [Discipline.structure]);
    });

    test('旧数据无 orgId / disciplines 不抛错', () {
      final legacy = Membership.fromJson(const {
        'id': 'm',
        'userId': 'u',
        'projectId': 'p',
        'roleCode': 'viewer',
      });
      expect(legacy.orgId, '');
      expect(legacy.disciplines, isEmpty);
      expect(legacy.isAllDisciplines, isTrue);
      expect(legacy.status, Membership.statusActive);
    });
  });

  group('PermissionScope 的专业合并与双轴判定', () {
    test('全部成员记录都限定专业 → 取并集', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(
            id: 'm1',
            userId: 'u1',
            projectId: 'p',
            disciplines: [Discipline.hvac],
            permissions: ['a'],
          ),
          Membership(
            id: 'm2',
            userId: 'u1',
            projectId: 'p',
            disciplines: [Discipline.water],
            permissions: ['b'],
          ),
        ],
        projectId: 'p',
      );
      expect(scope.permissions, {'a', 'b'});
      expect(scope.disciplines.toSet(), {Discipline.hvac, Discipline.water});
      expect(scope.coversDiscipline(Discipline.hvac), isTrue);
      expect(scope.coversDiscipline(Discipline.structure), isFalse);
    });

    test('任一成员记录「不限专业」→ 整体不限（返回空列表）', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(
            id: 'm1',
            userId: 'u1',
            projectId: 'p',
            roleCode: Membership.roleProjectManager,
            permissions: [Membership.permMemberManage],
          ),
          Membership(
            id: 'm2',
            userId: 'u1',
            projectId: 'p',
            disciplines: [Discipline.hvac],
            permissions: ['b'],
          ),
        ],
        projectId: 'p',
      );
      expect(scope.isAllDisciplines, isTrue);
      expect(scope.coversDiscipline(Discipline.structure), isTrue);
      expect(scope.permissions, {Membership.permMemberManage, 'b'});
    });

    test('canOn：动作 + 专业双满足才放行', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(
            id: 'm1',
            userId: 'u1',
            projectId: 'p',
            disciplines: [Discipline.hvac],
            permissions: [Membership.permDefectReply],
          ),
        ],
        projectId: 'p',
      );
      expect(scope.canOn(Membership.permDefectReply, Discipline.hvac), isTrue);
      expect(
          scope.canOn(Membership.permDefectReply, Discipline.structure), isFalse);
      expect(scope.canOn(Membership.permDefectClose, Discipline.hvac), isFalse);
    });

    test('往返保留 disciplines', () {
      const scope = PermissionScope(
        {'a'},
        disciplines: [Discipline.hvac],
        projectId: 'p',
      );
      final back = PermissionScope.fromJson(scope.toJson());
      expect(back.projectId, 'p');
      expect(back.permissions, {'a'});
      expect(back.disciplines, [Discipline.hvac]);
    });

    test('none（未登录 / 非成员）不得被判为「可见」', () {
      expect(PermissionScope.none.isEmpty, isTrue);
      expect(PermissionScope.none.isAllDisciplines, isTrue,
          reason: '数据上确实没限定专业');
      // 但没有权限就没有数据范围 —— 防止「空范围」被误当「不限」。
      expect(PermissionScope.none.coversDiscipline(Discipline.hvac), isFalse);
      expect(PermissionScope.none.canOn(Membership.permDefectReply, 'x'), isFalse);
    });

    test('有权限但未限定专业 → 覆盖全部专业（项目负责人）', () {
      final scope = PermissionScope.forProject(
        memberships: const [
          Membership(
            id: 'm',
            userId: 'u1',
            projectId: 'p',
            roleCode: Membership.roleProjectManager,
            permissions: [Membership.permDefectClose],
          ),
        ],
        projectId: 'p',
      );
      expect(scope.isAllDisciplines, isTrue);
      expect(scope.coversDiscipline(Discipline.structure), isTrue);
      expect(scope.canOn(Membership.permDefectClose, 'landscape'), isTrue,
          reason: '不限专业应覆盖后台新增的未知专业');
    });
  });
}
