# 豆图 · 拼豆图纸转化器

把照片变成可上手的拼豆图纸：上传任意图片，一键转换为色号准确、带用量清单的拼豆图纸，附跟做引导。

- **平台**：Flutter（iOS + Android 双端单代码库，当前在 Windows 上开发验证）
- **风格**：仿苹果官网 UI（白底极简 / 苹果蓝 #0071E3 / 大标题 / 胶囊按钮 / 磨砂玻璃）
- **原则**：本地优先 —— 无后端、无账号、图片不上传、无广告无内购
- **规划文档**：[docs/plan/dev-plan.md](docs/plan/dev-plan.md)
- **开源地址**：<https://github.com/15209896293/doutu>
- **许可证**：[LICENSE](LICENSE) · 源代码开放、免费非商用、禁止商用
- **作者联系**：[AUTHORS.md](AUTHORS.md) · QQ 3053676729 · 3053676729@qq.com

## 功能

| 模块 | 说明 |
|------|------|
| 图片导入 | 相册选图 / 拍照（image_picker）；**大图预检**（尺寸/体积超限提醒 + 引导裁剪） |
| 裁剪 | 固定框 + 图片缩放平移，比例 1:1 / 4:3 / 自由（自实现，无原生插件）；**✨ 自动提取主体**一键框选；裁剪失败自动弹「换图」提示 |
| 画布设置 | 板型 29×29 / 29 圆形 / 52×52 / **81×81（默认）** / **128×128** / 自定义 16–256；色卡 MARD 221（默认）/ MARD 291 / Perler / Hama；**偏好自动记忆** |
| 一键生成 | 分析图降采样 → **像素级双阈值背景检测（映射前，多锚点 + 置信度把关）** → dominant-bucket 众数采样（覆盖度 + 轮廓检测）→ **贪心最大覆盖选色 / 聚类吸附** → OKLab / CIEDE2000 色卡映射（**红色主导防御**）→ 可选抖动（跳过背景/轮廓）→ 空间正则化 → 多数表决 + 孤立单格清理，Isolate 后台执行不卡 UI |
| 图纸预览 | 网格图纸 / 原图对比 / 圆形豆子成品模拟，双指缩放；**默认显示色号数字 + 图例式用量清单**，可返回上一步 |
| 用量清单 | **图例式**（色块图标下方标颗数），可复制为文本 |
| 库存/套盒匹配 | 录入已有豆子颗数，预览时**缺豆提醒**（缺哪几色、缺几颗）；生成时可**只用手头有的豆子**过滤色卡 |
| 导出 | 高清 PNG（≥1080px 含色号）、PDF（A4 图纸+BOM）、系统分享、返回首页 |
| 编辑器 | 画笔 / 橡皮 / 取色 / 填充 / 色号替换，10 步撤销重做 |
| 跟做模式 | **数字填色**：每格标编号 + 图例进度 + 点格打勾 + 高亮找格；**进度持久化，拼一半可续**；图例每色迷你进度条 + 完成态标记 |
| 历史记录 | 本地保存最近 20 个作品，可回看再编辑（**保存后可正常打开**） |
| 新手引导 | **点对点 coach marks**（高亮具体按钮 + 指向卡片），首次启动自动播放，设置可重看 |

## 核心算法（纯 Dart，`lib/core/`）

```
图片 → ①分析图降采样（每格约 4 个分析像素，单边 ≤1024）
     → ②背景检测（像素级：边界主色聚类锚点 + 置信度门槛 + 双阈值 flood-fill，映射前）
     → ③每格 dominant-bucket 众数采样（覆盖度 + 轮廓检测，轮廓格取暗像素均值）
     → ④选色：贪心最大覆盖（fixed-palette-greedy，色数受控时色准最优）
            或聚类吸附（cluster-then-snap，平滑档）
     → ⑤色卡映射（OKLab 默认 / CIEDE2000 细腻档；红色主导防御防红色漂移）
     → ⑥可选抖动（RGB 蛇形 Floyd–Steinberg，跳过背景/轮廓格）
     → ⑦空间正则化（边缘保护平滑）
     → ⑧多数表决清理 + 孤立单格区域移除
     → ⑨板型掩码（圆形板圆外格子透明） → 色号网格 + BOM + 诊断数据
```

- `ciede2000.dart` 通过 Sharma 2005 论文 34 对官方测试数据验证（容差 5e-4）
- `oklab.dart` OKLab 感知色差（默认档，快速且对人眼更均匀）
- 色卡映射器与暴力 ΔE00 扫描在随机查询上逐一对照
- 背景检测 / 贪心选色 / 空间正则化 / 多数表决均有单测覆盖
- 性能：128×128 网格转换在 Isolate 中执行（标准档实测 ≤300ms），UI 无阻塞

### 图案细节预设（v0.8）

| 预设 | 采样 | 色差 | 选色 | 色数上限 | 抖动 | 清理 |
|------|------|------|------|----------|------|------|
| ⚡ 精简 | dominant-bucket(4bit) | OKLab | 贪心最大覆盖 | 8 | 关 | 4 |
| ✨ 标准（默认） | dominant-bucket(4bit) | OKLab | 贪心最大覆盖 | 不限 | 关 | 4 |
| 🔬 细腻 | dominant-bucket(5bit) | CIEDE2000 | 贪心最大覆盖 | 16 | Floyd–Steinberg | 7 |
| 🌊 平滑自然 | average | OKLab | 聚类吸附 | 不限 | 关 | 关 |

> 高级参数（色数上限/抖动/去背景/色差档位）可逐项覆盖预设默认值，偏好自动记忆。

## 与 dev-plan 的差异（开发决策记录）

1. **色数上限矛盾已解决**：plan 说"跳过量化直接映射"但又要求"色数上限 8–64"。实现 `color_reducer.dart` 贪心削减：按用量保留 top-K，其余按 ΔE00 重映射。
2. **裁剪方案补齐**：plan 技术栈缺裁剪库选型，自实现（image 包 + InteractiveViewer），省一个原生插件约 2MB。
3. **新增圆形板**：plan 板型仅方形，补充 29×29 圆形板（拼豆最常用板型）。
4. **存储方案简化**：plan 用 Hive + sqflite 双存储，实际改为 `path_provider` + JSON 文件（作品 <20 个、无查询需求），零额外原生依赖、可纯 Dart 测试。
5. **权限最小化**：不引入 permission_handler；相册走系统 Photo Picker（免权限），仅相机需 CAMERA 权限声明。
6. **52×52 性能目标统一为 ≤ 300ms**（plan 中 0.5s / 300ms 两处不一致）。

## v0.3 迭代（相对 dev-plan 的补充）

1. **转换精细度**：映射源由「众数投票」改为「区域平均色」；抖动由 Bayer 改为 **Floyd–Steinberg Lab 误差扩散**并默认开启；新增 128 板型、默认板型 81。
2. **大图保护**：选图轻量预检（尺寸/体积）+ 生成失败友好提示 + 转换器防御降采样。
3. **流程闭环**：裁剪→设置→预览改 `push`（可返回上一步）；导出加返回首页；修复「保存的作品无法查看」（`openProject` + 按作品色卡解析）。
4. **预览清单**：色号数字与用量清单默认开启；BOM 改为图纸下方图例式（色块下方标颗数）。
5. **跟做重构**：由逐色高亮改为「数字填色」（编号格 + 图例 + 点格打勾 + 高亮找格）。
6. **新手引导**：磨砂玻璃 product tour，首启自动 + 设置可重看。

> 详见 [docs/plan/v0.3-iteration.md](docs/plan/v0.3-iteration.md)

## v0.4 迭代（相对 v0.3 的补充）

1. **跟做进度持久化**：按图纸内容指纹存"已拼格"，拼一半退出/重开可续拼。
2. **参数记忆接线**：板型/色数上限/抖动/去背景按上次选择记忆（settings 真正接入转换流程，默认抖动开、色数不限）。
3. **库存/套盒匹配（MVP）**：录入已有豆子颗数，预览时给出"缺哪几色、缺几颗"提醒。
4. **实物校色管线**：`tools/calibrate_palette.py` 用实测色批量更新色卡 rgb/hex。

> 详见 [docs/plan/v0.4-iteration.md](docs/plan/v0.4-iteration.md)

## v0.5 迭代（相对 v0.4 的补充）

1. **新手引导改为点对点 coach marks**：高亮真实 UI 元素 + 磨砂玻璃指向卡片 + 箭头（不再是一张固定卡片）。
2. **裁剪容错**：修复裁剪"下一步"无反应——安全 clamp 边界 + 异常兜底，失败时弹「换一张图片」提示。
3. **设置页卡顿优化**：板型缩略图降采样（最多 32×32 格），解决 128 板画 1.6 万格导致的卡顿。
4. **自动提取图片主体**：纯 Dart 边界背景色聚类 + 容差 flood-fill，裁剪页「✨ 自动提取主体」一键框选主体，缓解背景杂物导致的转换不准。

## v0.6 迭代（相对 v0.5 的补充）

> 详见 [docs/plan/v0.6-ai-cutout.md](docs/plan/v0.6-ai-cutout.md)

## v0.7/v0.8 迭代（色差与背景误识别专项）

1. **调研定稿**：[docs/plan/v0.7-color-and-background.md](docs/plan/v0.7-color-and-background.md)
   拆解 pixel-beads.com（源码级还原）+ 主流拼豆工具共识；
   [docs/plan/v0.8-best-solution.md](docs/plan/v0.8-best-solution.md) 定稿最优解方案。
2. **采样源修复**：映射源由「区域均值」改为 **dominant-bucket 众数采样**（治灰色毛边，
   与 BeadPattern / perler-beads-ai 三方共识一致）。
3. **背景移除前置重写**：像素级**双阈值 flood-fill**（种子 ΔE8 / 填充 ΔE14，多锚点聚类支持
   渐变与双色背景）+ 置信度门槛 + 前景覆盖度把关，映射前标记背景，另加背景蒙层预览。
4. **贪心最大覆盖选色**：色数受控时按「覆盖最多图像权重」挑选色卡色再映射（比 top-K 色准更高），
   提供聚类吸附（cluster-then-snap）平滑档。
5. **色差增强**：OKLab（默认）与 CIEDE2000 可选；红色主导防御；平均映射色差（ΔE）进诊断。
6. **清理增强**：空间正则化（边缘保护）+ 多数表决 + 孤立单格区域移除，输出无 <2 格孤立杂色。
7. **UX 集成**：图案细节四档预设；预览页诊断横幅（背景置信度/ΔE/杂色提示）、色号排除/恢复、
   编辑器镜像翻转；色卡 source/version 标注。

## 构建

```bash
flutter pub get
flutter analyze          # 静态检查
flutter test             # 单元测试（算法 + 模型 + 存储）
flutter build apk --release --split-per-abi --obfuscate \
  --split-debug-info=./build/symbols --tree-shake-icons
```

> Android 需要 JDK 17+ 与 Android SDK（`flutter doctor` 检查）。

> **Windows 中文路径打包限制**：项目路径 `F:\拼豆图转化器` 含中文，Android AOT
> 阶段在 Windows 上会读不到 `.dart_tool` 下的产物（编码乱码），请用
> `powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1`
> （自动同步到 ASCII 路径 `F:\doutu_build` 构建并拷回 APK，见脚本头注释）。

## iOS 打包（需 macOS + Xcode）

APK 为安卓格式；iOS 安装包（IPA）只能在 macOS 上用 Xcode 构建（苹果强制）。
项目 iOS 侧已就绪：权限声明（相机/相册/保存）、Bundle ID `com.doutu.doutu`、
部署目标 iOS 15.0、自动签名、全套 App 图标。在 Mac 上执行：

```bash
# 1. 安装 Xcode（App Store）并同意许可；安装 CocoaPods（如需）
sudo xcodebuild -license accept
# 2. 安装 Flutter 到 Mac 后：
cd <项目目录>          # 拷贝本项目到 Mac（可用 git clone）
flutter pub get
# 3. 真机调试（需在 Xcode 里登录 Apple ID 并信任设备）
flutter run            # 或 flutter build ios --debug
# 4. 出 Release 包
flutter build ios --release
# 产物：build/ios/iphoneos/Runner.app（.app 需签名后转 .ipa）
```

**分发方式**（iOS 无"直接安装 apk"式路径，必须签名）：

| 方式 | 需要 | 用途 |
|------|------|------|
| App Store / TestFlight | Apple Developer 账号（$99/年） | 正式上架 / 邀请测试 |
| 个人证书 + 描述文件 | 免费 Apple ID（7 天有效期） | 本机真机调试 |
| 企业签名 | 企业开发者账号（$299/年） | 内部不限量分发 |

> TestFlight 是最常用的内测渠道：Xcode → Product → Archive → 上传 → TestFlight 添加测试员。
> 若用免费 Apple ID，真机调试需每 7 天重新签名一次。

## 色卡数据来源

| 色卡 | 来源 | 许可 |
|------|------|------|
| MARD 221 / 291 | Jett-Wu/Perler_Beads_Generator（MIT）+ Zippland/perler-beads 事实型色号数据（clean-room） | MIT |
| Perler 103 色 | maxcleme/beadcolors 社区实测数据 | MIT |
| Hama 92 色 | maxcleme/beadcolors 社区实测数据 | MIT |

> 屏幕色与实物豆存在色差，批量采购前请以实物色卡为准。生成脚本：`tools/build_palettes.py`、`tools/build_perler_hama.py`。

## 字体

EricaOne / WorkSans / JetBrainsMono / PixelifySans（Google Fonts，OFL 许可），随附于 `assets/fonts/`；中文走系统字体（iOS PingFang SC / Android Noto Sans CJK SC）以控制包体。
