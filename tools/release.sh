#!/usr/bin/env bash
# 一键发版：自动升版本号 → 编译 → 产出 dist/ 里的安装包 → 打印要发的话术
# 用法：bash tools/release.sh [patch|minor|major]   默认 patch（1.11.0 → 1.11.1）
set -e

cd "$(dirname "$0")/.."
MODE="${1:-patch}"
export PATH="/d/dev/flutter/bin:$PATH"
# Gradle 缓存放 E 盘，避免撑爆 C 盘
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/e/dev-cache/gradle}"
# 依赖缓存也在 E 盘（和项目同盘，避免 Kotlin 增量编译跨盘报错）
export PUB_CACHE="${PUB_CACHE:-/e/dev-cache/pub}"

# 安装包输出目录：优先 E 盘（C 盘空间紧张），可用 DIST_DIR 覆盖
if [ -n "$DIST_DIR" ]; then
  DIST="$DIST_DIR"
elif [ -d /e/ ]; then
  DIST="/e/自学/dist"
else
  DIST="dist"
fi

echo "== 1/5 计算新版本号 =="
python - "$MODE" <<'PY'
import re, sys
mode = sys.argv[1]
p = 'pubspec.yaml'
s = open(p, encoding='utf-8').read()
m = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', s, re.M)
if not m:
    sys.exit('pubspec.yaml 里没找到 version: x.y.z+n')
maj, mi, pa, code = (int(x) for x in m.groups())
if mode == 'major':
    maj, mi, pa = maj + 1, 0, 0
elif mode == 'minor':
    mi, pa = mi + 1, 0
else:
    pa += 1
code += 1
new = f'{maj}.{mi}.{pa}+{code}'
s = s[:m.start()] + f'version: {new}' + s[m.end():]
open(p, 'w', encoding='utf-8', newline='\n').write(s)
open('.release_version', 'w').write(f'{maj}.{mi}.{pa}|{code}')
print(f'  {m.group(0).replace("version: ", "")}  →  {new}')
PY

VER=$(cut -d'|' -f1 .release_version)
CODE=$(cut -d'|' -f2 .release_version)

echo "== 2/5 编译 release APK =="
flutter build apk --release 2>&1 | tail -2

echo "== 3/5 输出到 $DIST =="
mkdir -p "$DIST"
APK="build/app/outputs/flutter-apk/app-release.apk"
cp "$APK" "$DIST/课表待办-v$VER.apk"
cp "$APK" "$DIST/课表待办-最新版.apk"
SIZE=$(du -h "$DIST/课表待办-v$VER.apk" | cut -f1)
# 只留最近两个带版本号的包，省空间
ls -1t "$DIST"/课表待办-v*.apk 2>/dev/null | tail -n +3 | while read -r old; do rm -f "$old"; done

echo "== 4/5 校验签名（必须和以前一致，否则朋友无法覆盖升级）=="
EXPECT="56:1f:80:e1:e6:33:12:a1:50:b4:d7:31:ff:26:81:b9:f0:2d:6d:8d"
KT="/c/Program Files/Android/Android Studio/jbr/bin/keytool"
if [ -x "$KT" ] && [ -f ~/.android/debug.keystore ]; then
  SHA=$("$KT" -list -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey 2>/dev/null \
        | grep -E "^[[:space:]]*SHA1:" | head -1 | sed 's/.*SHA1:[[:space:]]*//' | tr -d '\r' | tr 'A-F' 'a-f')
  if [ "$SHA" = "$EXPECT" ]; then
    echo "  ✅ 签名一致（SHA1 $SHA）—— 可以直接覆盖安装"
  else
    echo "  ⚠️ 签名与预期不一致！实际：$SHA"
    echo "     这意味着朋友手机会装不上，必须先找回备份的 debug.keystore"
  fi
else
  echo "  （跳过：找不到 keytool 或 debug.keystore）"
fi

echo "== 5/6 更新说明 =="
cat > "$DIST/更新说明-v$VER.txt" <<TXT
课表待办 v$VER（build $CODE）
日期：$(date +%Y-%m-%d)
大小：$SIZE

【怎么发出去】
云端会自动把安装包发布到 GitHub Releases，朋友永远用同一个链接下载最新版：
（链接在第一运行时的日志里，或浏览器打开仓库的 Releases 页面）
本地的「课表待办-最新版.apk」留作备份，也可以直接发文件给人。

【朋友那边怎么更新】
1. 点开固定链接，下载 kebiao-latest.apk
2. 点开文件 → 安装 → 若提示"未知来源"/"此类文件可能有害"，允许一次
3. 装完打开就是新版，数据全在
TXT

git add -A >/dev/null 2>&1 || true
git commit -m "release v$VER (build $CODE)" >/dev/null 2>&1 || true

echo "== 6/6 推送到 GitHub（触发云端打包，生成固定下载链接）=="
# 有些网络环境下 http_proxy 会拦住 github.com，直连反而通，所以失败后重试一次
push_direct() { env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY "$@"; }
if git remote get-url origin >/dev/null 2>&1; then
  if git push origin HEAD >/dev/null 2>&1 || push_direct git push origin HEAD >/dev/null 2>&1; then
    git tag -f "v$VER" >/dev/null 2>&1
    if git push -f origin "v$VER" >/dev/null 2>&1 || push_direct git push -f origin "v$VER" >/dev/null 2>&1; then
      echo "  ✅ 已推送 v$VER，云端正在打包（约 8 分钟）"
      echo "     下载链接：$(git remote get-url origin | sed -E 's#^.*github\.com[:/](.+)/(.+)\.git$#https://github.com/\1/\2/releases/latest/download/kebiao-latest.apk#')"
      echo "     构建进度：https://github.com/$(git remote get-url origin | sed -E 's#^.*github\.com[:/](.+)/(.+)\.git$#\1/\2#')/actions"
    else
      echo "  ⚠️ 标签推送失败，本地安装包照样能用"
    fi
  else
    echo "  ⚠️ 推送失败（网络或未登录 GitHub），本地安装包照样能用"
  fi
else
  echo "  （还没绑定 GitHub 仓库，跳过）"
fi

echo
echo "✅ 完成：v$VER（build $CODE），$SIZE"
echo "   要发出去的文件：$DIST/课表待办-最新版.apk"
echo "   配套话术：$DIST/更新说明-v$VER.txt"
ls -la "$DIST"
# 自动打开输出目录（中文路径交给 explorer 处理，避免 bat 编码问题）
command -v explorer.exe >/dev/null 2>&1 && explorer.exe "$(cygpath -w "$DIST")" 2>/dev/null || true
