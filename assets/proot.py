#!/usr/bin/env python3
"""独立的 proot 修复模块，位于 AstrBot 更新范围之外。"""

import os
import re
import subprocess
import sys

def proot_fix() -> None:
    """
    修复 process_restart.py，使其包含 proot 兼容的重启逻辑。
    每次调用都会检查并修复，确保文件始终处于修复状态。
    """
    target_file = "/root/AstrBot/astrbot/core/process_restart.py"
    if not os.path.exists(target_file):
        print(f"[proot_fix] 目标文件不存在: {target_file}")
        return

    try:
        with open(target_file, 'r', encoding='utf-8') as f:
            content = f.read()

        # 检查是否已修复
        if 'from proot import proot_fix' in content:
            print("[proot_fix] 已修复，跳过")
            return

        # 1. 替换 _exec_restart 函数
        pattern = r'^(\s*)os\.execv\(executable,\s*argv\)\s*$'
        replacement = (
            r'\1# proot 环境检测\n'
            r'\1import sys\n'
            r'\1sys.path.append("/root")\n'
            r'\1from proot import proot_fix\n'
            r'\1proot_fix()\n'
            r'\1if not os.path.exists("/proc/self/root"):\n'
            r'\1    subprocess.Popen([executable, *argv[1:]], close_fds=True)\n'
            r'\1    os._exit(0)\n'
            r'\1else:\n'
            r'\1    os.execv(executable, argv)\n'
        )

        new_content, count = re.subn(pattern, replacement, content, flags=re.MULTILINE)

        if count != 1:
            print(f"[proot_fix] ❌ 重启修复失败: 匹配数量为 {count}")
            return

        with open(target_file, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print("[proot_fix] ✅ 重启修复完成")

    except Exception as e:
        print(f"[proot_fix] ❌ 重启修复失败: {e}")



    """
    同时修改 python 日志级别。
    避免输出大量来自 python 模块的 debug 日志到终端。
    """
    target_file2 = "/root/AstrBot/astrbot/core/log.py"
    try:
        with open(target_file2, 'r', encoding='utf-8') as f:
            content2 = f.read()

        # 检查是否已修复
        if not 'level="DEBUG"' in content2:
            print("[proot_fix] python 日志级别已修改，跳过")
            return

        # 2. 替换日志配置部分
        pattern2 = r'(level=")DEBUG(")'
        replacement2 = r'\1INFO\2'

        new_content2, count2 = re.subn(pattern2, replacement2, content2, flags=re.MULTILINE)

        if count2 < 1:
            print(f"[proot_fix] ❌ python 日志级别修改失败: 匹配数量为 {count}")
            return

        with open(target_file2, 'w', encoding='utf-8') as f:
            f.write(new_content2)
        print("[proot_fix] ✅ python 日志级别修改完成")

    except Exception as e:
        print(f"[proot_fix] ❌ python 日志级别修改失败: {e}")



    """
    恢复新版 Local 本机环境为旧版本逻辑
    # 不使用 bwrap 隔离；sandbox 环境不作修改。
    # 文件访问范围仅支持关闭或整个环境，选择工作区视为关闭。
    """

    # 仅对高于 4.28.2 的 AstrBot 版本注入 Local 补丁
    version_file3 = "/root/AstrBot/astrbot/__init__.py"
    try:
        with open(version_file3, 'r', encoding='utf-8') as f:
            version_content3 = f.read()
        version_match3 = re.search(
            r'__version__\s*=\s*["\']([^"\']+)["\']',
            version_content3,
        )
        version_parts3 = re.match(
            r"^(\d+)\.(\d+)\.(\d+)",
            version_match3.group(1) if version_match3 else "",
        )
        if not version_parts3:
            print("[proot_fix] ❌ 未找到 AstrBot 版本号，跳过 local 补丁")
            return
        astrbot_version3 = tuple(int(part) for part in version_parts3.groups())
        if astrbot_version3 <= (4, 28, 2):
            print(
                f"[proot_fix] AstrBot {version_match3.group(1)} 不高于 4.28.2，"
                "跳过 local 补丁"
            )
            return
    except (OSError, AttributeError, TypeError, ValueError) as e:
        print(f"[proot_fix] ❌ AstrBot 版本检查失败，跳过 local 补丁: {e}")
        return

    # 修改 Local 权限策略：workspace 视为关闭，保留执行权限配置。
    target_file3 = "/root/AstrBot/astrbot/core/tools/computer_tools/util.py"
    try:
        with open(target_file3, 'r', encoding='utf-8') as f:
            content3 = f.read()

        pattern3 = (
            r'^(\s*)filesystem_scope = role_policy\.get\('
            r'"filesystem_scope", defaults\["filesystem_scope"\]\)[ \t]*$'
        )
        replacement3 = (
            r'\1filesystem_scope = role_policy.get('
            r'"filesystem_scope", defaults["filesystem_scope"])\n'
            r'\1if filesystem_scope == "workspace":\n'
            r'\1    filesystem_scope = "none"'
        )

        new_content3, count3 = re.subn(
            pattern3,
            replacement3,
            content3,
            flags=re.MULTILINE,
        )

        if count3 != 1:
            print(f"[proot_fix] ❌ Local 权限策略修改失败: 匹配数量为 {count3}")
            return

        with open(target_file3, 'w', encoding='utf-8') as f:
            f.write(new_content3)
        print("[proot_fix] ✅ Local 权限策略修改完成")

    except Exception as e:
        print(f"[proot_fix] ❌ Local 权限策略修改失败: {e}")
        return

    # 修改 Shell 工具：关闭 bwrap，使用 host 文件范围并允许网络
    target_file4 = "/root/AstrBot/astrbot/core/tools/computer_tools/shell.py"
    try:
        with open(target_file4, 'r', encoding='utf-8') as f:
            content4 = f.read()

        pattern4 = (
            r'^(\s*)sandboxed=sandboxed,[ \t]*$'
            r'([\s\S]*?)^(\s*)allow_network=\([ \t]*\n'
            r'\s*local_policy\.allow_network if local_policy else True\n'
            r'\s*\),[ \t]*$'
            r'([\s\S]*?)^(\s*)filesystem_scope=\([ \t]*\n'
            r'\s*local_policy\.filesystem_scope if local_policy else "host"\n'
            r'\s*\),[ \t]*$'
            r'([\s\S]*?)^(\s*)\*\*sandbox_roots,[ \t]*$'
        )
        replacement4 = (
            r'\1sandboxed=False,\n'
            r'\2'
            r'\3allow_network=True,\n'
            r'\4'
            r'\5filesystem_scope="host",\n'
            r'\6'
            r'\7**{},'
        )

        new_content4, count4 = re.subn(
            pattern4,
            replacement4,
            content4,
            flags=re.MULTILINE,
        )

        if count4 != 1:
            print(f"[proot_fix] ❌ Shell 工具修改失败: 匹配数量为 {count4}")
            return

        with open(target_file4, 'w', encoding='utf-8') as f:
            f.write(new_content4)
        print("[proot_fix] ✅ Shell 工具修改完成")

    except Exception as e:
        print(f"[proot_fix] ❌ Shell 工具修改失败: {e}")
        return

    # 修改 Python 工具：关闭 bwrap，使用 host 文件范围并允许网络
    target_file5 = "/root/AstrBot/astrbot/core/tools/computer_tools/python.py"
    try:
        with open(target_file5, 'r', encoding='utf-8') as f:
            content5 = f.read()

        pattern5 = (
            r'^(\s*)sandboxed = (?:False if legacy_local_runtime else )?'
            r'local_policy\.requires_sandbox[ \t]*$'
            r'([\s\S]*?)^(\s*)sandboxed=sandboxed,[ \t]*$'
            r'([\s\S]*?)^(\s*)allow_network=(?:True if legacy_local_runtime else )?'
            r'local_policy\.allow_network,[ \t]*$'
            r'([\s\S]*?)^(\s*)filesystem_scope=(?:"host" if legacy_local_runtime else )?'
            r'local_policy\.filesystem_scope,[ \t]*$'
        )
        replacement5 = (
            r'\1sandboxed = False\n'
            r'\2\3sandboxed=False,\n'
            r'\4\5allow_network=True,\n'
            r'\6\7filesystem_scope="host",'
        )

        new_content5, count5 = re.subn(
            pattern5,
            replacement5,
            content5,
            flags=re.MULTILINE,
        )

        if count5 != 1:
            print(f"[proot_fix] ❌ Python 工具修改失败: 匹配数量为 {count5}")
            return

        with open(target_file5, 'w', encoding='utf-8') as f:
            f.write(new_content5)
        print("[proot_fix] ✅ Python 工具修改完成")

    except Exception as e:
        print(f"[proot_fix] ❌ Python 工具修改失败: {e}")
        return

    # 修改 WebUI 文案：扫描包含“本地隔离功能”的 JS 文件并替换提示
    target_dir6 = "/root/AstrBot/data/dist/assets"
    target_file6 = None
    for candidate6 in sorted(os.listdir(target_dir6)):
        if not candidate6.endswith(".js"):
            continue
        candidate_path6 = os.path.join(target_dir6, candidate6)
        try:
            with open(candidate_path6, 'r', encoding='utf-8') as f:
                candidate_content6 = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        if "本地隔离功能" in candidate_content6:
            target_file6 = candidate_path6
            break

    if target_file6 is None:
        print("[proot_fix] ❌ 未找到包含‘本地隔离功能’文案的 WebUI JS 文件")
        return

    try:
        with open(target_file6, 'r', encoding='utf-8') as f:
            content6 = f.read()

        pattern6 = (
            r'配置 \{backend\}，启用完整的本地隔离功能。'
            r'|安装 \{dependency\} 以获得完整的本地隔离功能。'
        )
        replacement6 = (
            r'已为proot绕过bwrap隔离，文件访问范围仅支持关闭或整个环境，选择工作区将视为选择关闭'
        )

        new_content6, count6 = re.subn(
            pattern6,
            replacement6,
            content6,
            flags=re.MULTILINE,
        )

        if count6 != 2:
            print(f"[proot_fix] ❌ WebUI 提示文案修改失败: 匹配数量为 {count6}")
            return

        with open(target_file6, 'w', encoding='utf-8') as f:
            f.write(new_content6)
        print(f"[proot_fix] ✅ WebUI 提示文案已修改:")

        print("[proot_fix] ✅ local 本机环境兼容修改完成")

    except Exception as e:
        print(f"[proot_fix] ❌ WebUI 提示文案修改失败: {e}")
        return