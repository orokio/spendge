import SwiftUI

/// 首启隐私页：不绑定登录，也不阻断本地功能。
struct PrivacyConsentView: View {
    let onAccept: () -> Void
    let onOpenPolicy: () -> Void

    @State private var agreed = false

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .padding(.top, 36)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("隐私与数据")
                            .font(Typography.pageTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text("几句话说明白，再开始记账")
                            .font(Typography.body)
                            .foregroundStyle(Color.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        row(icon: "iphone",
                            title: "账本存在本机与 iCloud",
                            detail: "默认只在这台设备；开启 iCloud 同步后，通过你自己的 iCloud 在设备间同步，不经过我们。")
                        row(icon: "mic",
                            title: "语音只在你说的时候开启",
                            detail: "麦克风与语音识别仅在你主动使用语音输入时启用。")
                        row(icon: "chart.bar",
                            title: "帮助我们改进",
                            detail: "只统计功能是否好用，比如保存有没有成功，详见《隐私政策》。")
                        row(icon: "gearshape",
                            title: "政策随时可查",
                            detail: "设置 → 隐私与数据里能看到完整说明。")
                    }

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Button {
                                agreed.toggle()
                            } label: {
                                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(agreed ? Color.brand : Color.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Text("我已阅读并同意")
                                .font(Typography.caption)
                                .foregroundStyle(Color.textSecondary)

                            Button("《隐私政策》") {
                                onOpenPolicy()
                            }
                            .font(Typography.caption)
                            .foregroundStyle(Color.brand)
                            .buttonStyle(.plain)

                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 4)

                        Button {
                            if agreed {
                                onAccept()
                            } else {
                                // 按钮本身就是明确的同意动作；先让勾选可见，再进入
                                agreed = true
                                Task {
                                    try? await Task.sleep(for: .milliseconds(140))
                                    onAccept()
                                }
                            }
                        } label: {
                            Text("同意并继续")
                                .font(Typography.bodyStrong)
                                .foregroundStyle(Color.onAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.brand, in: Capsule())
                        }
                        .buttonStyle(.plain)

                    }
                    .padding(.top, 36)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 36, height: 36)
                .background(Color.brandSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 隐私政策正文（先放 App 内，上架前再挂公网页）
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("隐私政策")
                            .font(Typography.pageTitle)
                        Spacer()
                        Button("完成") { dismiss() }
                            .font(Typography.bodyStrong)
                            .foregroundStyle(Color.brand)
                    }
                    .padding(.top, 24)

                    section("数据存在哪里",
                            "账单、目标、预算与「没花钱」确认默认保存在本机。开启 iCloud 同步后，数据保存在你的 iCloud 私有数据库，由 Apple 的 CloudKit 提供，只有登录同一 Apple ID 的设备能读到，不经过我们的服务器。")

                    section("崩溃上报",
                            "随 App 使用一并开启。通过第三方崩溃分析服务收集崩溃堆栈、App 版本与一个随机安装标识，用于把同一设备的崩溃归在一起；设备型号、系统版本等其他信息的采集已在配置中关闭。信息只用于定位和修复问题，不用于广告，也不与你的身份关联。")

                    section("权限",
                            "麦克风与语音识别只在你主动使用语音输入时启用；识别在本机完成，语音不会上传。")

                    section("使用记录",
                            "App 会在本机记录功能使用事件（事件名与基础属性），用于排查问题与改进产品。这些记录默认只保存在设备上，只有你主动导出诊断日志时才会离开设备；不包含金额、备注等账本内容，也不用于广告。App 会生成一个随机设备标识，仅用于设备登记与分类下发。")

                    section("第三方 SDK",
                            "Bugly（腾讯）：崩溃与异常监控。收集崩溃堆栈、App 版本与随机安装标识，仅用于修复问题，不用于广告或跨应用追踪；随 App 使用一并开启。具体处理规则见腾讯 Bugly 官方隐私政策。")

                    section("政策变更",
                            "政策内容变更时会提升版本号，并在下次启动重新询问。")

                    Text("生效日期：2026-11-27")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.bodyStrong)
                .foregroundStyle(Color.textPrimary)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
