import Foundation

/// 输入边界：UI 与业务层共用同一组上限。
enum InputLimits {
    /// 单笔金额上限：¥9,999,999
    static let amountCentsMax: Int64 = 999_999_900
    /// 备注最多字数
    static let noteLength = 100
    /// 目标名称最多字数
    static let goalTitleLength = 20
    /// 次数型目标上限
    static let countTargetMax = 9999
    /// 导入备份文件大小上限（字节）
    static let backupFileBytes = 20 * 1024 * 1024
}
