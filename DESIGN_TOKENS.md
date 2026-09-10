# site-patrol 设计规范（Design Tokens & UI 约定）

> 本项目是 Flutter 工地巡检 / 验收 App。本文件是**全 App UI 的唯一权威规范**——设计令牌、字号阶梯、组件形态、图标体系、常见陷阱都在这里。
>
> **最后校对：2026-09-10**（与 `lib/core/theme/design_tokens.dart`、`lib/core/theme/app_theme.dart` 逐值核对，token 值以代码为准；两者若不一致，改代码后必须回来同步本文）。
>
> ⚠️ **本文不是程序读取的配置文件**，只是编辑清单。改这里的值不会生效——必须同步改 `design_tokens.dart` / `app_theme.dart` 的常量，然后跑 `flutter analyze` + 重新构建。

---

## 一、文件位置

| 内容 | 文件 | 说明 |
|---|---|---|
| 设计令牌（颜色 / 间距 / 圆角 / 阴影 / 尺寸 / 按钮档） | `lib/core/theme/design_tokens.dart` | `AppTokens` 类，全部 `static const` |
| 主题（字体 / 字号阶梯 / 组件默认样式） | `lib/core/theme/app_theme.dart` | `lightTheme`（唯一主题，巡场页已统一为浅色） |
| 通用组件 | `lib/shared/widgets/` | `AppCard` / `AppButton` / `AppBottomSheet` / `NavIconButton` / `StatusBadge` / `SectionTitle` / `AppBottomNav` |

改 UI 前**先查这里**有没有现成组件/令牌；没有再考虑新建，并在本文补登记。

---

## 二、调色板总览

```
主色     accent = brand = #0395FF（品牌蓝，全局主操作色）  accentSoft = #E6F5FF
语义色   success #34C759   warning #FF9500   danger #FF3B30   （各带 Soft 块面底 + Tint 标签底）
标签浅底 brandTint / successTint / warningTint / dangerTint / yellowTint（= 原色 5% 透明度）
背景     bg #F4F6F7   surface #FFFFFF   surface2 #F4F6F7   surface3 #E9EAEB
文字     fg #202224   fg2 #60656B   muted #919499   note #B5B9BF
边框     border #E9EAEB
```

> ⚠️ **历史遗留已废弃**：早期版本用过浅金 `#FAE286` 作 accent、iOS 蓝 `#007AFF` 作 brand、黑色 `#222222` 作 fg、圆角统一 5。这些**全部已下线**，代码中不应再有残留；看到旧值一律按本表纠正。

---

## 三、完整令牌清单

### 1. 主色

| Token | 值 | 用途 |
|---|---|---|
| `accent` | `#0395FF` | **全局主操作色**（实色按钮底、描边按钮边框、文字按钮字色、选中态图标） |
| `accentHover` | `#0284E6` | 悬停加深 |
| `accentActive` | `#0273CC` | 按下 / 激活 |
| `accentSoft` | `#E6F5FF` | 图标容器底、选中 chip 底（块面级浅底） |
| `brand` | `#0395FF` | 与 `accent` 同值，语义上用于「品牌 / 图纸 / 链接」，两者可互换 |
| `brandHover` | `#0273CC` | |
| `brandSoft` | `#E6F5FF` | |

> 主色只有**一个蓝家族**，不再区分 accent（金）与 brand（蓝）。

### 2. 语义色

| Token | 值 | Soft（块面底，图标容器用） | Tint（标签底，= 原色 5%） |
|---|---|---|---|
| `success` 成功 / 已整改 | `#34C759` | `successSoft #E6F8ED` | `successTint` |
| `warning` 警告 / 待整改 / 较重 | `#FF9500` | `warningSoft #FFF3E0` | `warningTint` |
| `danger` 危险 / 严重缺陷 | `#FF3B30` | `dangerSoft #FFEBEA` | `dangerTint` |
| — 一般（黄） | 用 `warningSoft` 系的黄 | — | `yellowTint #0DFADC19` |

**Soft vs Tint 的区别**（容易用错）：
- `Soft` = 实色浅底，用于**块面**（30–40px 图标容器、整块提示背景）。
- `Tint` = 标签原色的 **5% 透明度**（`0x0D` 前缀），用于**小标签胶囊底**（`StatusBadge`）。
- **例外**：灰标签（类型 / `#自定义标签` / 楼栋楼层）不用 tint，仍用 `surface2 #F4F6F7` 实色底——因为灰 tint 会透出背景差异。

### 3. 背景与表面

| Token | 值 | 用途 |
|---|---|---|
| `bg` | `#F4F6F7` | 页面全局背景 |
| `surface` | `#FFFFFF` | 卡片 / 弹层表面 |
| `surface2` | `#F4F6F7` | 次级填充：图标底、小标签底、内嵌子容器（与 `bg` 同值，靠 Hank 卡片白底区分） |
| `surface3` | `#E9EAEB` | 输入框 / 禁用态灰底 / 未激活圆点 |

### 4. 文字

| Token | 值 | 用途 | 用量参考 |
|---|---|---|---|
| `fg` | `#202224` | 主文字 | — |
| `fg2` | `#60656B` | 次级文字（副标题、说明、未选中态） | — |
| `muted` | `#919499` | 辅助弱化（时间戳、计数、单位） | — |
| `note` | `#B5B9BF` | 最弱一档：脚注 / 补充说明（当前 4 处引用） | 少用 |

### 5. 边框 / 阴影 / 固定字色

| Token | 值 | 用途 |
|---|---|---|
| `border` | `#E9EAEB` | 分割线、卡片细边框 |
| `onAccent` / `onBrand` | `#FFFFFF` | 蓝底上的白字 |
| `elevationRaised` / `elevationOverlay` / `elevationNone` | 全部返回空列表 `[]` | **全 App 扁平化：卡片无投影**。令牌保留仅为兼容旧引用 |

> **不要在卡片上加 `boxShadow`**。唯一允许投影的场景：`boxShadow` 浮动工具条（如悬浮缩放控件），其余一律扁平。
> **不要给纯展示型白卡加灰色描边**（白底置于 `#F4F6F7` 上已足够分离）。例外：输入框外壳（靠描边界定唯一边界）、分段胶囊每一片、带阴影的浮动条。

### 6. 巡场主题令牌（已统一为浅色）

`patrolBg`=`bg`、`patrolSurface`=`surface`、`patrolSurface2`=`surface3`、`patrolFg`=`fg`、`patrolMuted`=`muted`、`patrolBorder`=`border`。深色沉浸主题**已下线**，巡场页与其他页面视觉一致。

### 7. 间距（4px 网格，7 档）

| Token | 4 · 8 · 12 · 16 · 24 · 32 · 48 |
|---|---|
| 对应 | `space1` `space2` `space3` `space4` `space5` `space6` `space7` |

只有这 7 档，**不再有 20 / 40**（写 20 就近取 24 或 16，写 40 取 48 或 32）。

### 8. 圆角

| Token | 值 | 用途 |
|---|---|---|
| `radiusLg` | **12** | 外层卡片（`AppCard` 默认）、Card 主题、ListTile 外层 |
| `radiusSm` / `radiusMd` / `radiusXl` | **8** | 内层卡、小图标容器、输入框、小标签、SnackBar |
| `radiusButton` | **12** | 主操作按钮（实色 / 描边 / 文字三形态统一） |
| `radiusPill` | 999 | 胶囊：状态徽章、筛选 toggle、FAB、section 副标题胶囊 |

> **外层 12 / 内层 8** 是核心规律：白卡套嵌时，外圆角必须比内圆角大。

### 9. 结构尺寸

| Token | 值 | 用途 |
|---|---|---|
| `tabbarH` | 49 | 底部 Tab 栏（iOS 标准 49pt，不含底部安全区） |
| `statusbarH` | 28 | 状态栏参考高度 |
| **导航栏 `toolbarHeight`** | **48** | **全局统一**，见 §五 |

> 导航栏高度写死在 `appBarTheme.toolbarHeight: 48`，`home / capture / projects / drawing_viewer / defects(×2)` 亦显式写 48。**状态栏不写死**，交给 `AppBar` + `SafeArea` 自适应。

---

## 四、Typography

### 字体

**内置小米 MiSans**（家族名 `MiSans`，免费商用），常量 `AppTokens.fontFamily`。四档字重：

| 权重槽 | 使用的官方文件 | pubspec weight | 实测笔画指数（Regular=1.00） |
|---|---|---|---|
| `w400` | MiSans-Regular | 400 | 1.00 |
| `w500` | MiSans-Medium | 500 | 1.32 |
| `w600` | MiSans-Demibold | 600 | 1.54 |
| `w700` | MiSans-Semibold | 700 | 1.77 |

> ⚠️ **Semibold 文件的 OS/2 `usWeightClass` 也写成 600**（小米源字体元数据瑕疵）。Flutter 不读 TTF 元数据、只认 pubspec 声明，所以 App 内正常；但导出 PDF / Web CSS / Office 时工具会读 TTF，Semibold 会与 Demibold 撞成同一档导致加粗层级塌陷。**导出场景若需真 700，应换 `MiSans-Bold`**。
> 字体文件是子集（`tools/build_ui_font.py --all` 生成，约 5.3 MB/档），**保留 GSUB/GPOS**（kerning / 连字），只丢竖排表。UI 子集一定不能丢排版表。
> `fontFamilyFallback`：PingFang SC → Microsoft YaHei → Noto Sans CJK SC（仅兜底生僻字）。
> PDF 报告 / 服务端仍用 `assets/fonts/NotoSansSC-Regular.ttf`，与 UI 字体互相独立，**不要删**。

### 字号阶梯（六档，只用偶数）

`32 / 22 / 16 / 14 / 12 / 10`；字距统一 **0**；**行高 = 字号 + 8**（代码写成 `(字号+8)/字号` 的分数形式）。

| 样式名 | 字号 | 行高 | 字重 | 用途 |
|---|---|---|---|---|
| `displaySmall` | 32 | 40 | w700 | 大标题（项目名） |
| `headlineMedium` | 22 | 30 | w700 | 页面大标题 |
| `titleLarge` | 16 | 24 | w700 | 卡名 / 强调标题 |
| `titleMedium` | 16 | 24 | **w500** | 卡内次级标题 |
| `bodyLarge` | 16 | 24 | w400 | 正文 |
| `bodyMedium` | 14 | 22 | w400 | 正文次级 |
| `bodySmall` | 12 | 20 | w400 | 辅助文字（`muted` 色） |
| `labelLarge` | 16 | 跟随字体 | w700 | 按钮 / 强调 |
| `labelMedium` | 12 | 跟随字体 | w700 | 次级按钮 |
| `labelSmall` | 10 | 跟随字体 | w700 | 小标签 / 徽章 |

### 字重使用原则

代码实测用量：**w600（102 处）> w400（66）> w700（42）> w500（39）**。

- **w400** 正文 / 次要说明。
- **w500** 次级标题、选中态文字、弹窗说明文本的值。
- **w600 是主力强调档**——页面标题、区块标题、卡片标题、按钮外的关键数据。
- **w700** 仅留给页面大标题（20–22px）与弹窗标题，避免满屏加粗。
- 规则：**层级越高字越重**；一屏内重档 ≤ 2 个；能用字号 / 颜色解决的不要靠加粗。
- `NumText` 数字组件固定 `height: 1`（单行大数字）并启用 tabular-nums。

---

## 五、组件规范

### 1. 导航栏（AppBar）

- 高度 **48dp**；标题样式写在 `appBarTheme.titleTextStyle`（16 / w700 / `#202224`）。
- 各页面标题 `centerTitle`、次行信息等见下方页面约定表。
- **返回箭头踩坑（已两次踩）**：
  1. `IconButton` 默认 `padding: EdgeInsets.all(8)`，图标会比按钮边缘再缩进 8px。`NavIconButton` 已改为**水平完全贴边**（`padding: symmetric(vertical: 10)` + `minWidth: 24 / minHeight: 44`），**横向边距完全由调用处 Padding 控制**，全局统一 `Padding(left/right: 12)`。
  2. `AppBar` 对 `leading` 会强制 `ConstrainedBox(tightFor(width: leadingWidth))`（默认 56），内层 Padding 会把剩余宽度紧约束给子组件 → 图标被居中、视觉偏移。**正解：显式设 `leadingWidth = 边距(12) + 图标宽`**（24 图标 → **36**，18 图标 → **30**），再配 `Padding(left: 12) + NavIconButton`。
- 路由返回统一用 `context.pop()`（go_router）。

**各页面导航栏约定**：

| 页面 | 路由 | 标题 / 内容 | leadingWidth |
|---|---|---|---|
| 首页 | `/home` | `ProjectSwitcher`（项目名 16/w600/#202224 + `down_small_fill` 24）+ 次行**仅施工状态** 12/w400/#60656B；右侧 `UserSwitcher`(`menu_line`) | — |
| 图纸 | `/projects` | 标题「图纸」20/w600/#202224（行高 28）+ `UserSwitcher`，gap 12，padding 8 12 | — |
| 验收 | `/capture` | 同上结构 | — |
| 巡场 | `/patrol` | — | — |
| 工单 | `/defects` | 标题「工单」20/w600/#202224 + `UserSwitcher`，padding 8 12 | — |
| 二级页（record_detail / patrol_editor / ar_measure×2 / measure_page / blueprint_viewer / timeline_compare） | — | 返回键 + 标题 | **36** |
| defects 页「处置与回复」、capture_records 页「验收记录」（18 图标） | — | 返回键 + 标题 | **30** |

> 单标题页：48 = 28 标题行 + 10 上下内边距；双行页：48 = 24 + 20 紧贴。

### 2. 底部导航（`AppBottomNav`）

纯白底 `#FFFFFF`（**无顶部描边**），高 `tabbarH` 49，文字 **16 / w600**，选中 `AppTokens.brand`、未选中 `AppTokens.muted`。映射：

`项目`→`/home` · `图纸`→`/projects` · `验收`→`/capture` · `巡场`→`/patrol` · `工单`→`/defects`

### 3. 卡片（`AppCard`）

`surface` 白底 + `radiusLg` 12 + **无阴影** + `elevationRaised`（空） + 内边距默认 `space4` 16。支持 `onTap`（自带 InkWell）。内层子容器用 `radiusSm` 8 + `surface2` 底做信息分组。

### 4. 按钮（`AppButton`）

三档 × 三形态。**高度为严格值**（`min==max` + `tapTargetSize.shrinkWrap`，否则 Material 默认会把 md/sm 撑到 48、lg 撑到 56）。

| 档 | 高度 | 横向 padding 下限 | 字号 | 圆角 | 字重 | 行高 |
|---|---|---|---|---|---|---|
| `AppButtonSize.lg` | 48 | 24 | 16 | 12 | w700 | 24 |
| `AppButtonSize.md`（默认） | 36 | 12 | 14 | 12 | w700 | 22 |
| `AppButtonSize.sm` | 32 | 12 | 12 | 12 | w700 | 20 |

- 形态：`filled`（实色 `accent` 底 + 白字）/ `outlined`（透明底 + `accent` 描边 + 蓝字）/ `text`（纯文字蓝）。
- **纯文字、不带图标**；`AppButton` 已移除 icon 参数，大按钮禁止「图标 + 文字」组合。
- 宽度自适应；满宽传 `width: double.infinity`。
- 直接用 `OutlinedButton` / `FilledButton` 时，`AppTheme` 已把圆角设为 `radiusButton` 12 ——**不要再显式覆盖成 `radiusMd`(8)**（历史上 capture 页「添加量尺项」踩过）。

### 5. 底部弹窗（`AppBottomSheet`）

统一壳（设计稿 Frame 2147228008）：

- 遮罩 `#000` 50%；sheet 背景 **`bg #F4F6F7`**；顶部圆角 **24**。
- 头部 **高 48**：标题居中 16 / w600 / `#202224`，右上 **`closeMediumLine`** 24×24、`#09244B`。
- 内容区 `EdgeInsets.fromLTRB(12, 0, 12, 24)`，头部与内容间距 12。
- 选图 / 详细信息 / 修改名称等**一律走它**，不要自写 `showModalBottomSheet`。

### 6. 小组件

| 组件 | 规范 |
|---|---|
| `SectionTitle` | 主标题 16 / w600 / `fg`；副标题徽标 `surface2` 实色底灰字；右侧「查看全部」12 / w400 / `muted` + 16px 箭头 |
| `StatusBadge` | 胶囊 999，`horizontal 10 / vertical 4`，12 号字；**底色默认 = 文字色 5% 透明**（灰标签显式传 `bg: surface2`）；字重默认兼容 w700，新代码按标签规范传 **w400** |
| `NavIconButton` | 见 §五.1；默认 24 尺寸，无 hover / splash / focus 背景（web 桌面端不显示圆形高亮） |

---

## 六、图标体系

- **全项目统一 MingCute**（`flutter_mingcute` 包），写法 `MingCuteIcons.xxx`，风格优先取 `xxxLine`（描边风，与整体扁平一致）。
- 已无 Material `Icons.xxx` 与 lucide 引用。统计残留时要用词边界 `\bIcons\.`，否则会被 `MingCuteIcons.` 的子串严重误报。
- 仅保留 3 张自定义 PNG：`assets/icons/capture.png`、`drawings.png`、`patrol.png`。
- **图标 + 文字对齐**（用户反复强调）：`Text` 默认行高 ~1.4 会让字形顶偏。
  - 横排：`Row(crossAxisAlignment: center, children: [Icon, SizedBox(width: gap), Expanded(child: Text(t, style: TextStyle(**height: 1**, ...)))])` —— **文字 style 必须带 `height: 1`**（怕裁切可用 1.1）。
  - 竖排：`Column(crossAxisAlignment: center, mainAxisSize: min, ...)`。

---

## 七、布局 / 自适应硬规则

1. **标签 / 胶囊流一律用 `Wrap`**（`spacing: 4`、`runSpacing: 4`），不用 `Row` 排一排。已整改点：首页待办卡标签、工单筛选文本组、图纸页楼层卡。
2. `Row` 内可变长文本必须 `Expanded` / `Flexible` + `maxLines: 1` + `overflow: ellipsis`；两个并列名字各包一层 `Flexible`。
3. **不写死设计稿宽度**；需要按稿缩放时用 `LayoutBuilder` 按可用宽度等比计算。
4. 多行标题 / 状态文字加 `StrutStyle(forceStrutHeight: true)` 锁行高，防撑破固定高容器。
5. 排查脚本（用于自查漏网）：扫「`Row(` 内无 `Expanded/Flexible/Spacer` + `width:>=280` + Row 内 Text 无截断」，跳过 `report_pdf/docx/report_builder`（那是生成文档的代码，非屏幕 UI）。
6. **黄黑溢出条纹只在 Debug 出现**，Release 不显示但错位照样存在——看见了必须真修，不能当作 Debug 专属现象忽略。

---

## 八、修改后如何生效

```bash
# 1. 同步改 design_tokens.dart / app_theme.dart 的常量
# 2. 基线校验：flutter analyze 必须保持 <= 199 条且零新增
flutter analyze

# 3. 构建 Web 预览（长命令放后台）
flutter build web --release --no-source-maps --pwa-strategy=none
python3 tools/post_build_web.py     # 必跑：删 sw + 注入自清理脚本

# 4. 起预览服务（先清端口，否则绑不上、会一直服务过期副本）
pkill -f "http.server 8080"; pkill -f serve_web.py
python3 tools/serve_web.py          # http://127.0.0.1:8080
```

> **Flutter Web 的 service worker 会缓存旧资源**，不做第 3 步刷新永远是旧界面；用户用内置浏览器没有 DevTools，只能靠 `post_build_web.py` 根治。
> 排查「预览没变化」：先 `ls -la build/web/main.dart.js build/web/index.html` 核对时间戳，再判断是不是缓存。

### iOS / 安卓真机

- **本环境无法命令行构建 iOS**（`xcodebuild` / `flutter build ios` 内嵌 `sandbox-exec` 被宿主沙箱禁），只能走 **Xcode GUI** 用 `Runner.xcworkspace`，构建前 `pod install`。
- 签名 Team `9G3493XTT5`（Automatic）；真机 **Yang**（UDID `00008120-0012284936B8201E`）。相机 / AR / 语音仅真机可用。
- 免费账号 7 天有效期。**拔线使用**：Edit Scheme → Run → Info → Build Configuration 改 **Release** → ⌘R 重装（Debug 包拔线必触发 Flutter iOS 14+ JIT 限制）。调试时切回 Debug。

---

## 九、版本基线

- `flutter analyze`：**199 条**（改动后须持平、零新增）。这 199 条是历史存量，非本次改动引入。
- `tools/gen_b05_walls.dart` 内含 1 条预存 info，属预期。
- 新增代码若导致 199→200，先定位到具体文件（`flutter analyze | grep <file>`）修掉，不要整体放宽基线。
