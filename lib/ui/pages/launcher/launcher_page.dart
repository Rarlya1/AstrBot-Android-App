import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/terminal_controller.dart';

class LauncherPage extends StatefulWidget {
  final ValueChanged<int>? onNavigate;
  final VoidCallback? onOpenSettings;

  const LauncherPage({super.key, this.onNavigate, this.onOpenSettings});

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  final HomeController homeController = Get.find<HomeController>();

  void _openSettings() {
    widget.onOpenSettings?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'AstrBot',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: '设置',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
            children: [
              _buildQuickStartCard(context),
              const SizedBox(height: 12),
              _buildNapCatAccountsCard(context),
              const SizedBox(height: 12),
              _buildEnvironmentCard(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStartCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy),
                const SizedBox(width: 8),
                Text('AstrBot', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('监听端口'),
              subtitle: const Text('127.0.0.1:6185'),
              trailing: IconButton(
                tooltip: '修改 AstrBot 端口',
                onPressed: () {},
                icon: const Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动 AstrBot'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNapCatAccountsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pets),
                const SizedBox(width: 8),
                Text(
                  'NapCat 账号',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '添加账号',
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '添加账号后单独扫码登录，每个账号独立端口和登录态。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('添加账号'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text('环境管理', style: Theme.of(context).textTheme.titleMedium),
          subtitle: const Text('分步安装与修复组件'),
          children: [
            const SizedBox(height: 12),
            _buildStepTile(
              icon: Icons.construction,
              title: '基础命令',
              subtitle: 'sudo / git / curl',
            ),
            _buildStepTile(
              icon: Icons.download,
              title: 'uv',
              subtitle: 'Python 依赖管理工具',
            ),
            _buildStepTile(
              icon: Icons.extension,
              title: 'NapCat',
              subtitle: '安装或修复 NapCatQQ',
            ),
            _buildStepTile(
              icon: Icons.smart_toy,
              title: 'AstrBot',
              subtitle: '克隆 AstrBot 并同步依赖',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: FilledButton.tonalIcon(
        onPressed: () {},
        icon: const Icon(Icons.download),
        label: const Text('安装'),
      ),
    );
  }
}
