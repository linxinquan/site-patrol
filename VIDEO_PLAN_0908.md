# 建筑漫游视频制作手册（A/B 两版）2026-09-08

> 方法论来源：skill「建筑漫游AI视频生成」（SkillHub）+ 联网核实的项目真实造型。
> **核心原则：全部用图生视频（Image-to-Video），真实照片/效果图锁造型，Prompt 只写运动。**
> 参考 `DEVELOPMENT_LOG_2026-09-07.md`。

---

## 〇、素材清单（12 张，全部就位）

目录：`F:\建筑验收工具\参考照片\`

### A 版 · 南方科技大学附属医院（校本部）
| 文件 | 内容 | 用于镜头 |
|---|---|---|
| hospital-01-fengding-aerial.jpg | 封顶实景航拍（2025.7） | A1 / A6 |
| hospital-02-niaokan-render.jpg | 鸟瞰效果图 | A1 / A6 |
| hospital-03-yugu-tower.jpg | 鱼骨式塔楼 U 形平面 | A2 |
| hospital-04-menzhen.jpg | 从景观生态面看门诊区域 | A4 |
| hospital-05-north-south.jpg | 附院与医学院自北向南连续 | A5 |
| hospital-06-arc-green.jpg | 弧形造型 + 绿色基台 | A3 |

来源：澎湃·蛇口消息报 2025.7.8（蛇口消息报融媒体记者刘野 / 深圳市建筑工务署）
https://m.thepaper.cn/newsDetail_forward_31131175

### B 版 · 腾云中心（腾讯大铲湾 DY04）
| 文件 | 内容 | 用于镜头 |
|---|---|---|
| tengyun-01-overview.jpg | 项目总览（三座圆形云楼） | B1 |
| tengyun-02-aerial.jpg | 建筑鸟瞰 | B6 |
| tengyun-03-floating.jpg | 被托离地面（8.6 米架空） | B2 |
| tengyun-04-bridge.jpg | 钢桁架空中连桥 | B3 |
| tengyun-05-facade.jpg | 弯弧无框玻璃 + 横向遮阳板 | B4 |
| tengyun-06-skylight.jpg | 贝壳状天窗（ETFE 膜） | B5 |

来源：谷德 gooood（摄影 © 奥观AOGVISION / 张超 / 朱雨蒙）
https://www.gooood.cn/tencent-dachanwan-by-mad.htm

> ⚠️ 素材仅供内部汇报参考，对外发布注意版权。

---

## 一、A 版 · 南科大附属医院「山水动脉」

**规格**：45s / 1920×1080 / 25fps / MP4 8-12Mbps
**真实造型锚点**：U 形平面 + 鱼骨式塔楼 ｜ 弧形造型 + 绿色基台 ｜ 视觉健康通廊 ｜ 南北向通廊引大沙河入建筑
**项目事实**：深圳市建筑工务署 / 盖博建筑（德）+ 深圳华森 / 用地 5.68 万㎡ / 建面 16.76 万㎡ / 800 床 / 2025.6 封顶 / 2027 竣工

| # | 时间 | 参考图 | 画面 | 运镜 |
|---|---|---|---|---|
| A1 | 0-6s | hospital-01 / 02 | 大沙河上空鸟瞰，U 形平面 + 鱼骨状塔楼，绿色基台 | 无人机前推+微下俯 |
| A2 | 6-13s | hospital-03 | 鱼骨状病房翼层层展开，每间病房有景观面 | 缓慢横移 |
| A3 | 13-20s | hospital-06 | 弧形立面 + 绿色基台，建筑从绿意升起 | 低角度上摇 |
| A4 | 20-27s | hospital-04 | 视觉健康通廊（东西座 1-2 层），光影通透 | 室内推轨前推 |
| A5 | 27-34s | hospital-05 | 南北向通廊把大沙河景观引入，框景河景 | 缓慢前推穿廊 |
| A6 | 34-45s | hospital-01 / 02 | 黄昏鸟瞰，与医学院自北向南如动脉连续 + Slogan | 环绕拉升 |

### 图生视频 Prompt（只写运动，造型由参考图锁定）

**A1 鸟瞰**
```
无人机缓慢向前推进，镜头轻微下俯，
云影在屋面缓慢流动，大沙河水面波光轻微闪烁，
天光柔和变化，画面平稳无抖动
```
`EN: drone slowly pushes forward, slight tilt down, cloud shadows drifting across roofs, river shimmering, soft light transition, smooth stable motion`

**A2 鱼骨塔楼**
```
镜头缓慢向右横移，建筑立面光影缓慢移动，
玻璃幕墙反射天光渐变，近处树影轻微摇曳，
画面平稳，无变形
```
`EN: slow lateral camera pan to the right, light and shadow moving gradually across facade, sky reflection shifting on glass, nearby trees swaying slightly`

**A3 弧形造型 + 绿色基台**
```
镜头从绿色基台缓慢上摇至弧形立面，
前景草叶轻微摆动，光影沿弧面柔和流动，
建筑体量保持稳定不变形
```
`EN: camera slowly tilts up from green podium to curved facade, foreground grass swaying gently, soft light flowing along the curved surface, architecture stays stable`

**A4 视觉健康通廊**
```
镜头沿通廊缓慢向前推进，
自然光影在地面缓慢移动，远处人影缓慢走动，
室内空气通透，无闪烁
```
`EN: camera slowly pushes forward along the corridor, daylight shadows moving slowly on the floor, distant figures walking slowly, bright airy interior`

**A5 南北通廊引景**
```
镜头沿通廊缓慢前推，尽头大沙河景致逐渐放大，
河面波光流动，绿植轻微摇曳，画面平稳
```
`EN: camera slowly moves forward through the corridor, river view at the end gradually enlarging, water shimmering, plants swaying gently`

**A6 黄昏收尾**
```
镜头缓慢拉升并环绕，天色由金转蓝，
建筑窗户逐一点亮暖光，河面倒影流动
```
`EN: camera slowly rises and orbits, sky shifts from golden to blue, windows lighting up one by one, river reflection flowing`

**Slogan**：`山水动脉 · 临河而治，望水而愈`

---

## 二、B 版 · 腾云中心「漂浮的云」

**规格**：45s / 1920×1080 / 25fps / MP4 8-12Mbps
**真实造型锚点**：三座圆形云楼 ｜ 10 组落地筒体托起 8.6 米 ｜ 钢桁架空中连桥 ｜ 6 米弯弧无框玻璃 + 横向遮阳板 ｜ 绿毯草坡 ｜ 保留红树林
**项目事实**：MAD（马岩松/党群/早野洋介）/ 用地 7.2 万㎡ / 建面 41.2 万㎡ / 1.4 万员工 / 80% 工位面海 / 2026.5 建成开放

| # | 时间 | 参考图 | 画面 | 运镜 |
|---|---|---|---|---|
| B1 | 0-7s | tengyun-01 | 三座圆形云楼从大铲湾晨雾中浮现，绿毯草坡与红树林岸线 | 无人机前推+微下俯 |
| B2 | 7-14s | tengyun-03 | 10 组筒体托起建筑，8.6 米架空，超高无肋玻璃，市民穿行 | 缓慢前推 |
| B3 | 14-21s | tengyun-04 | 钢桁架空中连桥连接三座云楼，观海动线 | 沿连桥横移 |
| B4 | 21-28s | tengyun-05 | 6 米弯弧无框玻璃反射海天，横向遮阳板顺曲线延伸 | 缓慢横移+微推 |
| B5 | 28-35s | tengyun-06 | 中庭贝壳状天窗，白色 ETFE 叶片膜，柔和自然采光 | 中庭垂直上摇 |
| B6 | 35-45s | tengyun-02 | 蓝调时刻，云楼亮灯，前海湾 + Slogan | 环绕拉升 |

### 图生视频 Prompt

**B1 云楼浮现**
```
无人机缓慢向前推进，镜头轻微下俯，海面晨雾缓缓流动，
云影在建筑立面缓慢移动，水面波光轻微闪烁
```
`EN: drone slowly pushes forward with slight tilt down, morning sea mist drifting, cloud shadows moving slowly across facades, water shimmering`

**B2 8.6 米架空**
```
镜头缓慢向前推进，行人从建筑下方穿行，
玻璃幕墙反射光影缓慢变化，前景草叶轻微摆动，建筑体量保持稳定不变形
```
`EN: camera slowly pushes forward, pedestrians walking beneath the building, light reflections shifting slowly on glass, foreground grass swaying, architecture stays stable`

**B3 钢桁架连桥**
```
镜头沿连桥缓慢横移，海面波光流动，
钢结构阴影随光线缓慢移动，远处云层轻微飘动
```
`EN: camera slowly pans along the bridge, sea shimmering, steel shadows shifting gradually, distant clouds drifting slightly`

**B4 弯弧玻璃立面**
```
镜头缓慢横移并轻微推进，海天光影在弯弧玻璃上流动，
遮阳板阴影缓慢变化，建筑曲线保持稳定不变形
```
`EN: slow lateral pan with slight push-in, sea and sky light flowing across curved glass, sunshade shadows shifting slowly, curved geometry stays stable`

**B5 贝壳状天窗**
```
镜头从中庭缓慢上摇至天窗，
ETFE 膜透光柔和变化，光斑在地面缓慢移动，空间保持稳定
```
`EN: camera slowly tilts up from atrium to skylight, soft light filtering through ETFE membrane, light patches moving slowly on floor, geometry stable`

**B6 蓝调收尾**
```
镜头缓慢拉升并环绕，天色由金转蓝，
建筑窗户逐一点亮暖光，海面倒影流动
```
`EN: camera slowly rises and orbits, sky shifting from golden to blue, windows lighting up one by one, sea reflection flowing`

**Slogan**：`漂浮的云 · 把地面还给城市`

---

## 三、生成工具参数

| 工具 | 设置 |
|---|---|
| **Kling 图生视频**（推荐，中文 Prompt 友好） | 上传参考图 → 运动幅度 **30-40%**（低！防变形）→ 高品质模式 |
| **Runway Gen-3**（一致性最好） | Image-to-Video → Camera control 手动设运动方向 → Motion **3-4**（低） |
| 备选 | 即梦 / Seedance 图生视频，运动幅度同样调低 |

**执行纪律**：
1. 每镜生成 **3 个候选**，挑造型最稳的（建筑不飘、不变形、不闪烁）
2. 全部镜头**同一工具同一参数**，保证质感统一
3. 造型失真的候选直接弃用，不要靠后期救

## 四、后期合成

| 环节 | A 版 | B 版 |
|---|---|---|
| 调色 | 暖白 + 大沙河绿 + 天光灰蓝；A6 加重金橙 | 冷银蓝 LUT，海天青蓝 + 建筑银白；B6 蓝橙对比 |
| 音频 | 极简钢琴 + 环境白噪音（鸟鸣/水声）+ 空间混响 | 氛围电子 + 环境白噪音（海浪/风声）+ 空间混响 |
| 旁白 | 男声沉稳，语速偏慢（ElevenLabs） | 同左 |
| 转场 | A1→A2 溶解；A3→A4 弧面推入室内匹配转场 | B1→B2 鸟瞰"下沉"到架空层匹配转场；其余溶解 |
| 字幕 | A6 淡入 Slogan | B6 淡入 Slogan |

## 五、质量检查清单

- [ ] 前 3 秒有识别 Hook（A：大沙河鸟瞰 / B：云楼浮出晨雾）
- [ ] 建筑造型与参考照片**逐帧比对无变形**（最重要）
- [ ] 全片光照方向一致、色调统一
- [ ] 运镜全部缓速，无跳帧闪烁
- [ ] 音频氛围匹配情绪基调
- [ ] 1080P 起，码率 8-12Mbps
- [ ] 特效克制，不加粒子/光污染

## 六、执行步骤（操作顺序）

1. 打开 Kling（klingai.com）或 Runway → 选 **Image-to-Video** 模式
2. 按分镜表逐镜上传参考图 → 粘贴对应 Prompt → 生成 3 个候选
3. 每镜选定最佳候选，下载保存（命名如 `A1_take2.mp4`）
4. 6 镜全部完成后 → 剪映/CapCut 按时间轴拼接 → 转场 → 调色
5. 加音频（Suno AI 生成 BGM / Artlist 选曲）→ 旁白 → Slogan 字幕
6. 导出 1920×1080 / 25fps → 按质量清单检查 → 成片
