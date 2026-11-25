# Bugly dSYM 上传

Archive（Release）时自动把当前 dSYM 传给 Bugly，崩溃堆栈才能符号化。

## 一次性准备

1. 从 Bugly 后台下载符号表工具（`buglyqq-upload-symbol-v3.x.x.zip`），解压出 `buglyqq-upload-symbol.jar`
2. 放到以下任意位置：
   - `~/Library/BuglyTool/buglyqq-upload-symbol.jar`（推荐，不占仓库）
   - `tools/bugly/buglyqq-upload-symbol.jar`（会被 git 忽略）
   - 或设置环境变量 `BUGLY_SYMBOL_JAR` 指到 jar
3. 安装 Java：`brew install --cask temurin`，装完 `java -version` 能输出版本号

App ID 与 App Key 从 `spendge/Info.plist` 读取，不需要额外配置。

## 行为

- 只在 `CONFIGURATION=Release` 且 `ACTION=install`（Archive/导出）时执行
- 工具、Java、dSYM 任一缺失都只打印提示，不中断打包
- 上传失败同样只提示，可在 Bugly 后台手动补传
