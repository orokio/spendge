#!/bin/sh
# Archive 时把当前 dSYM 传到 Bugly，崩溃堆栈才能符号化。
# 工具不随仓库分发：放到常见位置之一，或设置 BUGLY_SYMBOL_JAR。
# 任何一步缺失都只提示、不中断打包。

if [ "${CONFIGURATION}" != "Release" ] || [ "${ACTION}" != "install" ]; then
    exit 0
fi

DSYM_DIR="${DWARF_DSYM_FOLDER_PATH}"
if [ ! -d "${DSYM_DIR}" ]; then
    echo "note: dSYM 目录不存在，跳过 Bugly 上传"
    exit 0
fi

JAR="${BUGLY_SYMBOL_JAR}"
if [ -z "${JAR}" ] || [ ! -f "${JAR}" ]; then
    JAR="${SRCROOT}/tools/bugly/buglyqq-upload-symbol.jar"
fi
if [ ! -f "${JAR}" ]; then
    JAR="${HOME}/Library/BuglyTool/buglyqq-upload-symbol.jar"
fi
if [ ! -f "${JAR}" ]; then
    echo "warning: 没找到 Bugly 符号表工具，跳过上传（见 tools/bugly/README.md）"
    exit 0
fi

if ! command -v java >/dev/null 2>&1; then
    echo "warning: 没装 Java，跳过 Bugly 上传"
    exit 0
fi

PLIST="${SRCROOT}/spendge/Info.plist"
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :BuglyAppId" "${PLIST}" 2>/dev/null)
APP_KEY=$(/usr/libexec/PlistBuddy -c "Print :BuglyAppKey" "${PLIST}" 2>/dev/null)
if [ -z "${APP_ID}" ] || [ -z "${APP_KEY}" ]; then
    echo "warning: Info.plist 里没有 BuglyAppId / BuglyAppKey，跳过上传"
    exit 0
fi

echo "Uploading dSYM to Bugly: ${MARKETING_VERSION} (${DSYM_DIR})"
WORK_DIR=$(mktemp -d)
if (cd "${WORK_DIR}" && java -jar "${JAR}" \
    -appid "${APP_ID}" \
    -appkey "${APP_KEY}" \
    -version "${MARKETING_VERSION}" \
    -platform IOS \
    -inputSymbol "${DSYM_DIR}"); then
    :
else
    echo "warning: Bugly 上传失败，之后可在后台手动补传 dSYM"
fi
rm -rf "${WORK_DIR}"
