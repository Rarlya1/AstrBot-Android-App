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

        print("[proot_fix] 正在修复 process_restart.py...")

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
            r'\1    os.execv(executable, argv)'
        )

        new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE)

        with open(target_file, 'w', encoding='utf-8') as f:
            f.write(new_content)

        if count != 1:
            print(f"[proot_fix] ❌ 修复失败: 匹配数量为 {count}")
            return
        print("[proot_fix] ✅ 修复完成")

    except Exception as e:
        print(f"[proot_fix] ❌ 修复失败: {e}")