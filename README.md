# 豆图 · 拼豆图纸转化器

把照片变成可上手的拼豆图纸：上传任意图片，一键转换为色号准确、带用量清单的拼豆图纸，附跟做引导。

- **平台**：Flutter（iOS + Android 双端单代码库，当前在 Windows 上开发验证）
- **风格**：可爱系 UI（糖果色 / 大圆角 / 贴纸点缀）
- **原则**：本地优先 —— 无后端、无账号、图片不上传、无广告无内购
- **规划文档**：[docs/plan/dev-plan.md](docs/plan/dev-plan.md)
- **开源地址**：<https://github.com/15209896293/doutu>
- **许可证**：[LICENSE](LICENSE) · 源代码开放、免费非商用、禁止商用
- **作者联系**：[AUTHORS.md](AUTHORS.md) · QQ 3053676729 · 3053676729@qq.com

## 功能

| 模块 | 说明 |
|------|------|
| 图片导入 | 相册选图 / 拍照（image_picker）；**大图预检**（尺寸/体积超限提醒 + 引导裁剪） |
| 裁剪 | 固定框 + 图片缩放平移，比例 1:1 / 4:3 / 自由（自实现，无原生插件） |
| 画布设置 | 板型 29×29 / 29 圆形 / 52×52 / **81×81（默认）** / **128×128** / 自定义 16–256；色卡 MARD 221（默认）/ MARD 291 / Perler / Hama；**偏好自动记忆** |
| 一键生成 | 区域平均色采样 → CIEDE2000 色卡映射（KD-tree）→ **Floyd–Steinberg 误差扩散（默认开）** → 杂色合并 → 背景移除 → 色数削减，Isolate 后台执行不卡 UI |
| 图纸预览 | 网格图纸 / 原图对比 / 圆形豆子成品模拟，双指缩放；**默认显示色号数字 + 图例式用量清单**，可返回上一步 |
| 用量清单 | **图例式**（色块图标下方标颗数），可复制为文本 |
| 库存/套盒匹配 | 录入已有豆子颗数，预览时**缺豆提醒**（缺哪几色、缺几颗）；生成时可**只用手头有的豆子**过滤色卡 |
| 导出 | 高清 PNG（≥1080px 含色号）、PDF（A4 图纸+BOM）、系统分享、返回首页 |
| 编辑器 | 画笔 / 橡皮 / 取色 / 填充 / 色号替换，10 步撤销重做 |
| 跟做模式 | **数字填色**：每格标编号 + 图例进度 + 点格打勾 + 高亮找格；**进度持久化，拼一半可续**；图例每色迷你进度条 + 完成态标记 |
| 历史记录 | 本地保存最近 20 个作品，可回看再编辑（**保存后可正常打开**） |
| 新手引导 | 磨砂玻璃质感 product tour，首次启动自动播放，设置可重看 |

## 核心算法（纯 Dart，`lib/core/`）

```
图片 → ①网格区域平均色采样（每格像素均值，保真、少糊细节）
     → ②CIEDE2000 色卡映射（Lab KD-tree 候选 + ΔE00 精确终选）
     → ②′Floyd–Steinberg 误差扩散（Lab 空间，默认开启，减轻渐变断层）
     → ③后处理（连通域杂色合并 + 边界 flood fill 背景移除）
     → ④板型掩码（圆形板圆外格子透明）
     → ⑤色数上限贪心削减（用量 top-K + ΔE00 重映射）
     → 色号网格 + BOM
```

- `ciede2000.dart` 通过 Sharma 2005 论文 34 对官方测试数据验证（容差 5e-4）
- 色卡映射器与暴力 ΔE00 扫描在随机查询上逐一对照
- 性能：300×300 网格转换在 Isolate 中执行，UI 无阻塞

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

## 构建

```bash
flutter pub get
flutter analyze          # 静态检查
flutter test             # 单元测试（算法 + 模型 + 存储）
flutter build apk --release --split-per-abi --obfuscate \
  --split-debug-info=./build/symbols --tree-shake-icons
```

> Android 需要 JDK 17+ 与 Android SDK（`flutter doctor` 检查）。

## 色卡数据来源

| 色卡 | 来源 | 许可 |
|------|------|------|
| MARD 221 / 291 | Jett-Wu/Perler_Beads_Generator（MIT）+ Zippland/perler-beads 事实型色号数据（clean-room） | MIT |
| Perler 103 色 | maxcleme/beadcolors 社区实测数据 | MIT |
| Hama 92 色 | maxcleme/beadcolors 社区实测数据 | MIT |

> 屏幕色与实物豆存在色差，批量采购前请以实物色卡为准。生成脚本：`tools/build_palettes.py`、`tools/build_perler_hama.py`。

## 字体

EricaOne / WorkSans / JetBrainsMono / PixelifySans（Google Fonts，OFL 许可），随附于 `assets/fonts/`；中文走系统字体（iOS PingFang SC / Android Noto Sans CJK SC）以控制包体。
