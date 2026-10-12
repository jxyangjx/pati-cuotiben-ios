import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsRoute: Hashable {
    case privacy
    case usage
    case children
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var children: [Child]
    @Query private var jobs: [LocalJob]
    @Query private var wrongItems: [WrongItem]
    @AppStorage(DefaultsKey.inferenceMode) private var inferenceMode = InferenceMode.stub.rawValue
    @AppStorage(DefaultsKey.inferenceBaseURL) private var inferenceBaseURL = ""
    @State private var exportURL: URL?
    @State private var message: String?
    @State private var confirmPurge = false
    @State private var gatewayKey = ""
    @State private var hasGatewayKey = false

    var body: some View {
        NavigationStack {
        List {
            Section("孩子") {
                NavigationLink(value: SettingsRoute.children) {
                    Label("孩子管理", systemImage: "person.2")
                }
            }

            Section("隐私与数据") {
                NavigationLink(value: SettingsRoute.privacy) {
                    Label("隐私说明", systemImage: "hand.raised")
                }
                Button {
                    exportBackup()
                } label: {
                    Label("生成备份包", systemImage: "square.and.arrow.down")
                }
                if let exportURL {
                    ShareLink(item: BackupFile(url: exportURL)) {
                        Label("分享备份包", systemImage: "square.and.arrow.up")
                    }
                }
                Button("清理 30 天前的页面原图", role: .destructive) {
                    confirmPurge = true
                }
            }

            Section("用量") {
                NavigationLink(value: SettingsRoute.usage) {
                    Label("用量说明", systemImage: "speedometer")
                }
            }

            Section("推理") {
                Picker("来源", selection: $inferenceMode) {
                    Text("离线桩").tag(InferenceMode.stub.rawValue)
                    Text("推理网关").tag(InferenceMode.live.rawValue)
                }
                if inferenceMode == InferenceMode.live.rawValue {
                    TextField("网关地址", text: $inferenceBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("网关密钥（可选）", text: $gatewayKey)
                    Button("保存密钥到钥匙串") { saveGatewayKey() }
                    Button("清除钥匙串里的密钥", role: .destructive) { clearGatewayKey() }
                    Text(hasGatewayKey ? "钥匙串里已有网关密钥。" : "尚未保存网关密钥。本地网关可以不设密钥。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("当前地址：\(InferenceConfig.baseURLString(userValue: inferenceBaseURL))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("照片和错题仍留在本机。网关只接收当题文字，不接收照片，也不使用对象存储。厂商、模型和厂商密钥在运行网关的电脑上配置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("离线桩在本机返回标答、判分、错因和题型总结，不会出网。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "0.1.0")
                Text("模式 A。照片和错题在本机。推理默认是离线桩，也可以改用本机推理网关。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .privacy:
                PrivacyView()
            case .usage:
                UsageView()
            case .children:
                ChildManagementView()
            }
        }
        .confirmationDialog("清理页面原图", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("清理 30 天前的原图", role: .destructive) { purge() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错题本里的裁切快照会留下。结构化的题目和错题也不会删。")
        }
        .onAppear {
            hasGatewayKey = InferenceKeychain.hasSecret
            session.reloadInference()
        }
        .onChange(of: inferenceMode) { _, _ in
            session.reloadInference()
        }
        .onChange(of: inferenceBaseURL) { _, _ in
            session.reloadInference()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("好", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        }
    }

    private func exportBackup() {
        do {
            exportURL = try BackupExporter.makePackage(children: children, jobs: jobs, wrongItems: wrongItems)
        } catch {
            message = "备份包没有生成。请再试一次。"
        }
    }

    private func saveGatewayKey() {
        do {
            try InferenceKeychain.save(gatewayKey)
            gatewayKey = ""
            hasGatewayKey = InferenceKeychain.hasSecret
            session.reloadInference()
            message = hasGatewayKey ? "网关密钥已保存在本机钥匙串。" : "已清除网关密钥。"
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "密钥没有保存。"
        }
    }

    private func clearGatewayKey() {
        InferenceKeychain.clear()
        gatewayKey = ""
        hasGatewayKey = false
        session.reloadInference()
        message = "已清除网关密钥。"
    }

    private func purge() {
        do {
            let count = try JobPipeline.purgeOriginals(olderThan: 30, context: context)
            message = count == 0 ? "没有超过 30 天的页面原图。" : "已清理 \(count) 张页面原图。"
        } catch {
            message = "清理没有完成。"
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("仅用于本人作业整理。照片、识别文字、标答和错题保存在这台手机的沙盒里，使用 SwiftData 和本地文件。")
                Text("相机和相册权限只用来拍摄或导入自己的作业页面。")
                Text("卸载 App 或清除数据后，这些内容会消失。需要留存时，请在设置里导出备份包。")
                Text("默认批改走本机离线桩。设置里改成推理网关后，只会送出当题文字，照片仍留在这台手机上，也不会写入对象存储。")
                Text("页面原图可以按时间清理。错题本另外保留裁切快照和作答、标答、错因。")
                Text("本期以本机孩子档案使用，不做多设备同步，也不提供微信登录。Apple 登录可以以后再加。")
            }
            .font(.body)
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paperBackground()
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UsageView: View {
    @AppStorage(DefaultsKey.lockThreshold) private var lockThreshold = GradingPolicy.defaultLockThreshold

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("孩子档案、切题核对和错题本都在本机完成，不产生对象存储费用。")
                Text("离线桩不会计费，也不会出网。推理网关按所选厂商的价格计费，密钥留在运行网关的电脑上。")
                VStack(alignment: .leading, spacing: 8) {
                    Text("自动锁定阈值 \(lockThreshold, format: .number.precision(.fractionLength(2)))")
                        .font(.headline)
                    Slider(value: $lockThreshold, in: 0.70...0.95, step: 0.01)
                    Text("置信度达到这个值，而且是客观题、标答和步骤都齐全时，系统会自动确认并锁定对错。低于这个值时保持待确认，不写入错题本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardChrome()
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paperBackground()
        .navigationTitle("用量说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BackupFile: Transferable, Sendable {
    var url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .zip) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            BackupFile(url: received.file)
        }
    }
}
