import SwiftUI

/// Shown once, before a child profile can be created and before the first grading pass.
struct PrivacyConsentView: View {
    var onAgree: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("拍题错题本")
                            .font(.largeTitle.weight(.semibold))
                        Text("开始之前，请确认这些内容只留在这台手机上。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("仅用于本人作业整理。")
                            .font(.headline)
                        Text("相机和相册只用来拍摄或导入自己的作业、试卷。照片、识别出的文字、系统标答和错题都保存在本机沙盒里。")
                        Text("不会上传到对象存储，也不会做多设备同步。卸载 App 或清除数据后，这些内容会消失。")
                        Text("同意之后才能建立孩子档案，以及开始第一次批改。")
                            .foregroundStyle(.secondary)
                        Text("默认批改在本机离线桩完成。如果以后在设置里改用推理网关，只会送出当题文字，照片仍留在这台手机上。")
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                    .cardChrome()

                    Button(action: onAgree) {
                        Text("同意并继续")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .paperBackground()
            .navigationTitle("隐私确认")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
