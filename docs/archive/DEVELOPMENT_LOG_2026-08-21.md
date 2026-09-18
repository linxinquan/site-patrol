# 开发日志 2026-08-21（周五）

## 一、今日完成

### 拍照记录 / 图纸底图（核心）
1. **默认图纸设置**
   - 7 栋项目 (`tencent-dy04-7`) 默认图纸 = `dy04_7_B05`（地下室夹层组合平面图，B05 PDF 底图）
   - 南科大项目 (`nkf`) 默认图纸 = `nkf_west_1f`（西楼一层平面图，对应 `建施报_06_V1.0_西楼一层平面图.pdf`）
   - 改动位置：`lib/features/capture/capture_page.dart` 的 `_defaultFloorKey` 映射

2. **图名规范化**
   - 7 栋 10 张图纸图名统一改成 PDF 原文件名格式：`建筑 AW-7-XXX V1.0 ...`
   - 改动位置：`lib/data/mock/mock_data.dart`（`dy7Drawings` / `dy7Floors`）

3. **批量转 PNG 并打包**
   - 用 `pypdfium2` 把 10 张有 PDF 的 7 栋图纸转成本地 PNG：
     `B01 / D01 / D03 / D04 / K01 / K02 / E01 / F01 / J01 / J04`
   - 存入 `assets/drawings/`，并在 mock_data 里把对应 Drawing 的 `src` 指向本地 PNG
   - 顶部锚点栏显示已选图纸全名（PDF 原文件名）

4. **移除无源文件图纸**
   - 从 7 栋可选列表移除 `dy04_7_B02`（资料目录既无 PDF 也无可用 DWG，OCF 转图必失败），避免用户切到空底图

### OCF 服务修复
5. 修复 `server/ocf_server.py` 缺失的 `_read_body` 方法（所有 POST 接口 saveAsImage/dwgInfo/dwgToOcf 此前一调用就 500，导致切无 PNG 图纸时前端拉不到远程图）
6. 修复 `ocf_server.py` 调浩辰 `ocfSaveAsImage` 时**缺失 `imageWidth/imageHeight` 传参**（之前只送了 fileBase64，云图返回 export error）
7. 把扣次接口 `_guard` 改为**本地预览默认允许** OCF 扣次（不设 `GCAD_ALLOW_CHARGE` 也能用，省去环境变量配置）

### 构建修复
8. 修复 Flutter web 构建缓存（`.dart_tool/flutter_build` 陈旧）导致 `assets/drawings` 资源**完全没打进产物**，这是之前"切换图纸看不到底图"的根因之一。已清缓存重构建并同步到 `C:\sp\build\web`（12345 预览目录）

## 二、积分/额度消耗优化（重要）
- **本地 PNG 优先**：凡是资料里有 PDF 的图纸，一律预先用 `pypdfium2` 离线转 PNG 存 `assets/drawings/`，运行时不走 OCF 接口，**不消耗浩辰云图额度**。
- 只有真正没有 PDF 的图纸（如已移除的 B02）才走 `ocfSaveAsImage`（扣次）。当前 7 栋列表里已无此类图纸，所以**正常预览 0 额度消耗**。
- `ocf_server.py` 的 `ocf_cache/{key}.png` 会缓存生成结果，重复请求同图不重复扣次。
- 提交信息已记录该策略，后续加图纸时优先离线转 PNG。

## 三、本地服务运行状态
- 静态预览：`http://localhost:12345/`（python -m http.server，根 `C:\sp\build\web`）
- OCF 转换：`http://localhost:8800/`（server/ocf_server.py，仅无 PNG 图纸才需要）
- 重启命令（若服务挂了）：
  ```
  cmd /c "cd /d F:\建筑验收工具\site-patrol\server && start /B python ocf_server.py"
  cmd /c "cd /d C:\sp\build\web && start /B python -m http.server 12345"
  ```
  > 注意：仓库根目录含中文（建筑验收工具），PowerShell 直接调 git 会 GBK 乱码；一律用 `cmd /c "cd /d <绝对路径> && git ..."` 方式操作。

## 四、待办项（下周一继续）
- [ ] **补全剩余图纸 PDF 转 PNG**：当前 7 栋已覆盖 10 张；若后续资料补充 B02 等 DWG/PDF，需重新评估是否离线转图还是走 OCF。
- [ ] **南科大项目图纸清单核对**：`nkf` 项目目前 `drawings`/`floors` 仍有旧名（西楼·地下一层/一层等），图名是否也要统一为 PDF 原文件名（建施报_XX）待用户确认。
- [ ] **测量功能模块（measure）**：`lib/features/measure/`、`server/measure_server.py` 等已提交但功能未联调验证，下周需测试测量记录流程。
- [ ] **拍照记录坐标校准复核**：B05 已验证 <2mm；新增的 B01/D01 等 PNG 的 `w/h` 与真实物理尺寸对应关系需确认（mock 里 w/h 取自 PDF 像素尺寸，定位精度待实测）。
- [ ] **web 预览跨设备访问**：当前仅 localhost，若需在手机/其他机器预览需改用可访问 IP 或部署。
- [ ] **OCF 额度监控**：上线前需确认浩辰云图账户额度，并决定生产环境是否关闭本地默认允许扣次（`GCAD_ALLOW_CHARGE` 反向控制）。

## 五、提交记录
- commit `0ea1e63` → 已推送 `origin/main`
- 本次含测量模块等既有未跟踪文件一并提交（31 个文件）
- 提交信息（英文，规避 Windows 中文路径 git 编码问题）：
  `feat: capture drawings multi-switch, PDF-name normalization, ocf_server fix`
