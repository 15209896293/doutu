/// App 设置页：默认色卡 / 默认板型 / 关于 / 数据来源说明。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/palette_repository.dart';
import '../../models/board_preset.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/product_tour.dart';

/// 设置页新手引导锚点（coach marks 目标）。
final _keyDefaultPalette = GlobalKey();
final _keyDefaultBoard = GlobalKey();
final _keyTourEntry = GlobalKey();
final _keyAbout = GlobalKey();

final _settingsTourSteps = <CoachStep>[
  CoachStep(
    targetKey: _keyDefaultPalette,
    icon: '🎨',
    title: '默认色卡',
    body: '生成图纸时默认使用的豆子品牌色卡。',
  ),
  CoachStep(
    targetKey: _keyDefaultBoard,
    icon: '📐',
    title: '默认板型',
    body: '生成图纸时默认的拼豆板尺寸，可随时改。',
  ),
  CoachStep(
    targetKey: _keyTourEntry,
    icon: '🎬',
    title: '新手引导',
    body: '想再看一遍讲解，随时点这里。',
  ),
  CoachStep(
    targetKey: _keyAbout,
    icon: 'ℹ️',
    title: '关于',
    body: '版权说明、联系作者与开源地址。',
  ),
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _tourVisible = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull;

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
      appBar: AppBar(title: const Text('⚙️ 设置')),
      body: SafeArea(
        child: settings == null
            ? const Center(child: BeadLoader())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('偏好',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          key: _keyDefaultPalette,
                          leading: const Text('🎨'),
                          title: const Text('默认色卡'),
                          trailing: DropdownButton<String>(
                            value: settings.paletteId,
                            underline: const SizedBox(),
                            items: [
                              for (final m in kPaletteMetas)
                                DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.displayName),
                                ),
                            ],
                            onChanged: (v) async {
                              if (v != null) {
                                await ref
                                    .read(settingsProvider.notifier)
                                    .saveSettings(
                                        settings.copyWith(paletteId: v));
                              }
                            },
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        ListTile(
                          key: _keyDefaultBoard,
                          leading: const Text('📐'),
                          title: const Text('默认板型'),
                          trailing: DropdownButton<String>(
                            value: settings.boardId,
                            underline: const SizedBox(),
                            items: [
                              for (final b in BoardPreset.presets)
                                DropdownMenuItem(
                                  value: b.id,
                                  child: Text(b.label),
                                ),
                              const DropdownMenuItem(
                                value: 'custom',
                                child: Text('自定义'),
                              ),
                            ],
                            onChanged: (v) async {
                              if (v != null) {
                                await ref
                                    .read(settingsProvider.notifier)
                                    .saveSettings(
                                        settings.copyWith(boardId: v));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('引导',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      key: _keyTourEntry,
                      leading: const Text('🎬'),
                      title: const Text('再看一遍新手引导'),
                      subtitle: const Text('重新播放完整流程讲解'),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondary),
                      onTap: () => setState(() => _tourVisible = true),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('关于',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  Card(
                    key: _keyAbout,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🧸 豆图 · 拼豆图纸转化器',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          SizedBox(height: 4),
                          Text('版本 0.6.0 · 开源免费 · 禁止商用 · 无广告无内购',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                          SizedBox(height: 12),
                          Text('隐私承诺',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            '所有图片与图纸数据仅保存在你的设备本地，'
                            '不上传任何服务器、不收集任何个人信息。'
                            '仅申请相册与相机权限用于选图。',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                          SizedBox(height: 12),
                          Text('色卡数据来源',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            'MARD 色卡：Jett-Wu/Perler_Beads_Generator (MIT)'
                            '与 Zippland/perler-beads 事实型色号数据；'
                            'Perler/Hama：maxcleme/beadcolors 社区实测数据 (MIT)。'
                            '屏幕色与实物豆存在色差，批量采购前请以实物色卡为准。',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                          SizedBox(height: 12),
                          Text('版权与开源',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            '© 2026 豆图作者 · 源代码开放，免费非商用。'
                            '未经书面授权禁止任何商业用途，详见 LICENSE。',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                          SizedBox(height: 12),
                          Text('联系作者',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            'QQ：3053676729\n邮箱：3053676729@qq.com',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                          SizedBox(height: 12),
                          Text('开源地址',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          SizedBox(height: 4),
                          Text(
                            'https://github.com/15209896293/doutu',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'made with 💖 for 拼豆玩家',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  ],
                ),
        ),
        ),
        if (_tourVisible)
          Positioned.fill(
            child: CoachTour(
              steps: _settingsTourSteps,
              onFinished: _onTourFinished,
            ),
          ),
      ],
    );
  }

  void _onTourFinished() => setState(() => _tourVisible = false);
}
