import Foundation

/// 金额工具：所有金额一律以「分」为单位存储（Int64），避免浮点误差。
enum Money {
    /// 将「元」转换为「分」，四舍五入到整数分。
    static func cents(from yuan: Decimal) -> Int64 {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let result = NSDecimalNumber(decimal: yuan)
            .multiplying(by: NSDecimalNumber(value: 100), withBehavior: handler)
        return result.int64Value
    }

    /// 将「分」转换为「元」。
    static func yuan(from cents: Int64) -> Decimal {
        Decimal(cents) / 100
    }
}
