# site-patrol 设计令牌体系（Design Tokens）

> 本项目是 Flutter 工地巡检 App。设计令牌是**全 App 样式的唯一数据源**——所有页面都从这些值取色、取间距、取圆角，不在页面里写死样式。

> ✅ **落地状态（2026-08-17）**：本文档定义的设计系统已全部代码落地——颜色 / 间距 / 圆角 / 字体 / 行高 / 按钮三档均写入 `design_tokens.dart` 与 `app_theme.dart`；按钮三档已封装为 `lib/shared/widgets/app_button.dart`。`mutedA11y` 已合并进 `muted`、`borderStrong` 已删除、登录/引导/保存等主按钮已替换为 `AppButton`。**「金色只用于按钮」已全局执行**：卡片/列表/导航的选中态（边框+图标+底色）、分段控件、Slider、Switch、进度条、状态点、Section 副标题胶囊、「查看全部」操作等所有非按钮金色，已统一改为 `fg`(#222222) / `surface2`(中性灰底) / `brand`(蓝，仅链接类)；保留金色的仅剩 `AppButton`、Filled/Outlined/TextButton 主题、首页/巡场/采集页的 FAB、采集快门大按钮（均为按钮）。后续改值请保持「文档 ↔ 代码」双向同步。

## 一、文件位置与生效方式

| 内容 | 文件 | 说明 |
|---|---|---|
| 设计令牌（颜色/间距/圆角/阴影/尺寸） | `lib/core/theme/design_tokens.dart` | `AppTokens` 类，60+ 个 `static const` 常量 |
| 主题（字体/字号/组件默认样式） | `lib/core/theme/app_theme.dart` | `lightTheme`（浅色主主题）、`patrolDarkTheme`（巡场深色主题） |

**⚠️ 编辑流程（重要）**：本文档是**编辑清单**，不是程序读取的配置。你在这里改好值后，必须**同步修改 `design_tokens.dart` / `app_theme.dart` 中对应的常量**，然后运行 `flutter analyze` 检查、重新构建或热重载，改动才会在 App 中生效。

---

## 二、调色板总览

```
主色     accent(#FAE286 浅金)   brand(#007AFF 蓝)
系统色   green(#34C759)  red(#FF3B30)  orange(#FF9500)  yellow(#FFCC00)  teal(#5AC8FA)
语义色   success(绿)  warning(橙)  danger(红)   + 各自的 Soft 浅底
背景     bg(#F8F8F8)   surface(#FFFFFF 卡片)   surface2(#F8F8F8 次级填充/图标底/小标签底)   surface3(#DDDDDD 输入框/嵌入底)
文字     fg(#222222 主文字)  fg2(#666666 次级文字)  muted(#999999 辅助弱化)
边框     border(#DDDDDD)
```

---

## 三、完整令牌清单

### 1. 主色（accent 以 #FAE286 浅金为基准；brand 独立为蓝色 #007AFF 仅用于图纸/链接）

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `accent` | `#FAE286`（浅金，主操作色） | **只用于按钮**（Filled 主按钮底色、Outlined 描边、文字色）。**不用于卡片/列表的选中态大面积铺色** |
| `accentHover` | `#F0D674` | accent 悬停/按下加深（约 -8% 明度） |
| `accentActive` | `#E6C758` | accent 激活态（约 -16% 明度） |
| `accentSoft` | `#FBF4DA` | accent 浅底（图标容器背景、选中 chip 底） |
| `brand` | `#007AFF`（iOS 蓝，品牌识别/链接） | 次要品牌色：图纸、链接（保持传统"链接=蓝"示意，与 accent 浅金独立） |
| `brandHover` | `#0066CC` | brand 悬停加深 |
| `brandSoft` | `#E5F1FF` | brand 浅底 |

> 说明：以 `accent = #FAE286` 为基准推导主色家族——accent 家族取同色相的明度梯度（hover/active 渐深、soft 为极浅底）。**使用约束：浅金 `#FAE286` 不适合大面积使用，只用于按钮**（主按钮底色、描边、文字按钮字色）。卡片/列表的「选中态」**不使用金色**：选中边框、选中图标（含项目选择图标）统一用 `fg`(#222222)，选中底色用中性灰 `surface2`(#F8F8F8)，避免金色铺开。`brand` 独立保持 iOS 蓝 `#007AFF`，仅用于图纸、链接，保留传统"链接=蓝"示意，与浅金 accent 互不影响。
> ⚠️ **必改附带项**：`accent` 现在是浅色（明度 ~75%），原 `onAccent = #FFFFFF`（白字）在其上将**不可读**。已将 `onAccent` 改为 `#222222`（深字），见 §7。

### 2. iOS 系统色

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `iosGreen` | `#34C759` | iOS 系统绿 |
| `iosRed` | `#FF3B30` | iOS 系统红 |
| `iosOrange` | `#FF9500` | iOS 系统橙 |
| `iosYellow` | `#FFCC00` | iOS 系统黄 |
| `iosTeal` | `#5AC8FA` | iOS 系统青 |

### 3. 语义色（映射 iOS，用于状态表达）

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `success` | `#34C759` | 成功 / 已整改 / 已缓存 |
| `successSoft` | `#E6F8ED` | success 浅底 |
| `warning` | `#FF9500` | 警告 / 待整改 |
| `warningSoft` | `#FFF3E0` | warning 浅底 |
| `danger` | `#FF3B30` | 危险 / 严重缺陷 |
| `dangerSoft` | `#FFEBEA` | danger 浅底 |

### 4. 背景与表面（iOS 分组样式）

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `bg` | `#F8F8F8` | 页面全局背景（原 iOS 分组灰 #F2F2F7，已调浅为客户指定浅灰） |
| `surface` | `#FFFFFF` | 卡片 / 弹层表面 |
| `surface2` | `#F8F8F8` | 次级填充（图标底、小标签底）—— 与 `bg` 同值，现图标/标签底与页面背景同色（见下方说明） |
| `surface3` | `#DDDDDD` | 输入框 / 嵌入底（禁用态灰底、未来节点灰圆点等"未激活/嵌入"灰）—— 比页面背景 `bg`(#F8F8F8) 略深，输入框可清晰浮出 |

> 待确认点：
> - **`bg` 与 `surface2` 仍为同值 `#F8F8F8`**：图标容器底、小标签底与页面背景同色，图标底方块将不再有"描边感"，只剩彩色图标本身。若希望图标容器/小标签仍能浮出背景，可把 `surface2` 设为比 `bg` 略深或略浅的值（如改白底 `#FFFFFF`）；当前按你给的值记为 `#F8F8F8`。
> - **`surface3`（输入框/嵌入底）已确认为 `#DDDDDD`**：比页面背景 `bg`(#F8F8F8) 略深，输入框/禁用按钮/未来节点灰圆点现在能清晰浮出背景（顺带解决了上面 `surface2==bg` 导致的"无浮出"问题）。

### 5. 文字

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `fg` | `#222222` | 主文字（原纯黑 #000000，改为深灰更柔和） |
| `fg2` | `#666666` | 次级文字（原 #3C3C43） |
| `muted` | `#999999` | 辅助弱化文字（原 #8E8E93 iOS 系统灰，已调浅）；**已合并 `mutedA11y`** |

> **`mutedA11y` 已合并进 `muted`**：原可访问灰 `#6C6C70`（底部导航未选中图标、空状态、mini 标签等约 13 处弱状态引用）统一改用 `muted`(#999999)。代价是这些弱状态更浅、对比度更低；本 App 不做无障碍合规则无碍。代码阶段需把 13 处 `mutedA11y` 引用改为 `muted` 后删除该常量。

### 6. 分割线 / 边框

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `border` | `#DDDDDD` | 分割线、卡片细边框 |

> **`borderStrong`（强调边框）已移除**：经代码核查，`borderStrong`(#C7C7CC) 在全项目 `lib/` 中**无任何引用**（仅 `design_tokens.dart` 自身定义）。即它是死 token，删除零 UI 影响。统一用 `border`(#DDDDDD) 即可，无需强调边框色。

### 7. 固定字色（accent/brand 上的反白/反深字）

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `onAccent` | `#222222` | accent(#FAE286 浅金) 上的文字——**由白改深**（浅金底白字不可读） |
| `onBrand` | `#FFFFFF` | brand(#007AFF 蓝) 上的文字（当前代码未引用，留作备用；蓝底白字可读，保持） |

### 8. 巡场深色沉浸主题（占位）

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `patrolBg` | `#0B1220` | 巡场页深色背景 |
| `patrolSurface` | `#111A2E` | 巡场深色卡片 |
| `patrolSurface2` | `#1A2540` | 巡场次级填充 |
| `patrolFg` | `#E8EEF6` | 巡场主文字 |
| `patrolMuted` | `#94A3B8` | 巡场弱化文字 |
| `patrolBorder` | `#1E293B` | 巡场边框 |

### 9. 间距（4px 网格，7 档）

| Token 名 | 值 | Token 名 | 值 |
|---|---|---|---|
| `space1` | 4 | `space5` | 24 |
| `space2` | 8 | `space6` | 32 |
| `space3` | 12 | `space7` | 48 |
| `space4` | 16 | — | — |

> 新刻度：**4 / 8 / 12 / 16 / 24 / 32 / 48**（去掉原 20、40 两档，新增 48 顶档）。原 `space5`(20)、`space8`(40) 在代码中仍有引用，改为新刻度后需将这两处引用迁移：20→就近 24（space5）或 16（space4），40→48（space7）或 32（space6）。`space8` 已废弃（待代码阶段删除）。

### 10. 圆角（统一 5；胶囊 999）

| Token 名 | 值 | 用途 |
|---|---|---|
| `radiusSm` | 5 | 列表项、小图标容器（装前置图标的 28–32px 彩色方块）、小容器 |
| `radiusMd` | 5 | 输入框、按钮、中卡片、SnackBar |
| `radiusLg` | 5 | 卡片、大卡片、弹层（底部 sheet 顶部） |
| `radiusXl` | 5 | 弹层顶部（与 radiusLg 同值，保持引用兼容） |
| `radiusPill` | 999 | 全圆角胶囊（悬浮按钮 FAB、筛选/切换胶囊 toggle、状态徽章、section 标题胶囊） |

> 说明：**圆角统一为 5**——列表项、输入框、按钮、卡片、大卡片、弹层全部 5；仅胶囊型保留 999。
> - 标准矩形按钮（FilledButton / OutlinedButton / TextButton）形状 = `radiusMd`(5)，**不再是胶囊**。
> - 胶囊型（999）仅限：悬浮按钮(FAB)、筛选/切换胶囊 toggle、状态徽章、section 标题胶囊（登录/引导页主按钮是 FilledButton，属矩形 5，不在此列）。
> - 小图标容器 = 列表行里装前置图标的彩色方块，跟随 `radiusSm`(5)。
> - 小标签：当前代码无独立组件，本轮未改动（首页缺陷列表左侧细色条 `radius:2` 暂保留，留待后续明确）。
> - 头像(CircleAvatar)、底部 sheet 抓手(2)、预览手机外框(device_frame 44/40/999) 不属于上述范畴，保持原样。

### 11. 阴影（iOS 极轻扁平，几乎无投影）

| Token 名 | 当前值 | 用途 |
|---|---|---|
| `elevationRaised` | 1 层：8% 黑，blur 8，偏移 (0, 1) | 普通卡片抬升 |
| `elevationOverlay` | 1 层：12% 黑，blur 32，偏移 (0, 10) | 弹层 / 浮层 |
| `elevationNone` | 无阴影 | 无 |

### 12. 结构尺寸

| Token 名 | 值 | 用途 |
|---|---|---|
| `tabbarH` | 64 | 底部 Tab 栏高度 |
| `statusbarH` | 28 | 状态栏高度 |

---

## 四、Typography（字号阶梯，定义于 app_theme.dart）

字体栈：各平台系统默认字体——**不打包自定义字体**。iOS 用 苹方（PingFang SC）/ SF Pro；Android 用 Roboto + 思源黑体（Noto Sans CJK SC）；Web 用 HTML 渲染器 + 系统字体栈（Windows 微软雅黑 / macOS 苹方）。数字（NumText）跟随系统字体并启用等宽数字（tabular-nums）。
字号规则：**六档 32/22/16/14/12/10（只用偶数）**，字重仅 **w400/w700** 两档，字间距统一 **0**。**行高统一规则：`行高 = 字号 + 8`**（精确整数，无小数点）。

| 样式名 | 字号 | 行高系数（代码写法） | 实际行高 | 字重 | 字间距 | 用途 |
|---|---|---|---|---|---|---|
| `displaySmall` | 32 | 40 / 32 (1.25) | 40 | w700 | 0 | 大标题（项目名） |
| `headlineMedium` | 22 | 30 / 22 (≈1.364) | 30 | w700 | 0 | 页面标题 / section |
| `titleLarge` | 16 | 24 / 16 (1.5) | 24 | w700 | 0 | 卡名 |
| `titleMedium` | 16 | 24 / 16 (1.5) | 24 | w700 | 0 | 卡内标题 |
| `bodyLarge` | 16 | 24 / 16 (1.5) | 24 | w400 | 0 | 正文 |
| `bodyMedium` | 14 | 22 / 14 (≈1.571) | 22 | w400 | 0 | 正文次级 |
| `bodySmall` | 12 | 20 / 12 (≈1.667) | 20 | w400 | 0 | 辅助文字 |
| `labelLarge` | 16 | —（未设） | 跟随字体默认 | w700 | 0 | 按钮 / 强调 |
| `labelMedium` | 12 | —（未设） | 跟随字体默认 | w700 | 0 | 次级按钮 |
| `labelSmall` | 10 | —（未设） | 跟随字体默认 | w700 | 0 | 小标签 / 徽章 |

> 说明：**行高 = 字号 + 8**（六档全部成立：32→40、22→30、16→24、14→22、12→20、10→18），是"分级刻度（平滑递减 0.1）"进一位后的整数化结果——既保留"字号越大行高越紧"的视觉层次，又消除所有小数点。代码里写成 `(字号+8)/字号` 的分数形式（如 `height: 30 / 22`），精确且自解释。页面硬编码样式按同字号套用同一规则。按钮/徽章等 UI 短文本（label*）不单独设行高，跟随字体默认；NumText 数字组件固定 `height: 1`（单行大数字，紧凑显示）。

---

## 五、常用组件默认样式（定义于 app_theme.dart）

| 组件 | 当前默认 |
|---|---|
| AppBar | 背景 `bg`，无阴影，标题 22/w700 |
| Card | 表面 `surface`，无阴影，圆角 `radiusLg`(5) |
| 列表项 ListTile | 表面 `surface`，圆角 `radiusMd`(5) |
| 底部导航 | 选中 `accent`，未选中 `muted` |
| 主按钮 FilledButton | 背景 `accent`，文字 `#222222`，圆角 5（矩形，非胶囊） |
| 描边按钮 OutlinedButton | 圆角 5（矩形，非胶囊） |
| 分割线 Divider | `border` 色，0.5 粗 |
| SnackBar | 浮层样式，深底 `#2C2C2E`，圆角 `radiusMd`(5) |

### 按钮规范（三档矩形按钮）

> 主操作按钮 `FilledButton` 的三档尺寸规格。**字重统一 w700**；行高 = 字号 + 8；圆角统一 5（非胶囊）；按钮宽度**不写死**，由"内容 + 左右 padding"自适应，仅规定左右 padding 下限。

| 档 | 高度 | 纵向 padding | 横向 padding（下限） | 圆角 | 字号 | 字重 | 行高 | 背景 / 字色 |
|---|---|---|---|---|---|---|---|---|
| 大 | 48 | 16 | ≥24 | 5 | 16 | w700 | 24 | accent `#FAE286` / `#222222` |
| 中 | 36 | 8 | ≥12 | 5 | 14 | w700 | 22 | accent `#FAE286` / `#222222` |
| 小 | 32 | 8 | ≥12 | 5 | 12 | w700 | 20 | accent `#FAE286` / `#222222` |

> - 描边按钮 `OutlinedButton`、文字按钮 `TextButton` 复用同字号 / 字重 / 行高 / 圆角，仅底色与边框不同（描边：透明底 + accent 边框；文字：纯文字无底）。
> - 带图标按钮的图标与文字间距 `gap: 10`（在间距刻度内）。
> - 字重说明：Flutter 代码统一 `FontWeight.w700`（PingFang SC 等系统字体支持 Bold）；若设计软件字体下拉缺 700 档，稿内可用 w600 近似，但**代码实现以 w700 为准**。
> - 横向 padding 为下限值，长文案 / 多语言时按钮按内容自动加宽，不固定 width。

---

## 六、修改后如何生效

```bash
# 1. 在 design_tokens.dart / app_theme.dart 中同步修改对应常量
# 2. 检查是否有引用错误
flutter analyze

# 3. 本地预览（Web 版）
flutter build web --release
cd build/web && python3 -m http.server 8765
# 浏览器打开 http://localhost:8765
```

> 修改建议：优先改 `design_tokens.dart` 中的值（一处改动全局生效）；尽量不要在页面文件里写死颜色/间距，否则会破坏令牌体系。
