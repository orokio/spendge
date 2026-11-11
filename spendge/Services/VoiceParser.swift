import Foundation

/// 从一句中文里抽出「分类」和「金额」。
/// 只做高置信度的简单匹配：匹配不到就留空，让用户自己点，绝不猜。
enum VoiceParser {
    struct Result {
        var categoryCode: CategoryCode?
        var yuan: Int?

        var isEmpty: Bool { categoryCode == nil && yuan == nil }
    }

    /// 关键词按长度优先匹配，避免「菜」抢走「买菜」。
    private static let keywords: [(CategoryCode, [String])] = [
        (.takeout, ["外卖", "美团", "饿了么"]),
        (.dineout, ["下馆子", "饭店", "餐厅", "火锅", "馆子", "吃饭"]),
        (.grocery, ["买菜", "菜市场", "超市", "生鲜"]),
        (.drink, ["咖啡", "奶茶", "星巴克", "瑞幸", "蜜雪", "茶百道", "喜茶"]),
        (.snack, ["零食", "水果"]),
        (.outing, ["打车", "地铁", "公交", "加油", "停车", "高铁", "机票", "电影", "演出", "门票", "旅游"]),
        (.housing, ["房租", "物业", "水电", "燃气"]),
        (.daily, ["纸巾", "洗衣液", "垃圾袋", "日用品", "清洁剂"]),
        (.wear, ["衣服", "鞋", "裤子", "外套", "帽子"]),
        (.gear, ["耳机", "键盘", "相机", "数码", "配件", "支架"]),
        (.appliance, ["冰箱", "洗衣机", "空调", "家具", "沙发"]),
        (.health, ["医院", "看病", "买药", "体检"]),
        (.social, ["红包", "随礼", "请客", "礼物"]),
        (.subscription, ["会员", "话费", "宽带", "订阅"]),
    ]

    static func parse(_ text: String) -> Result {
        var result = Result()

        for (code, words) in keywords {
            if words.contains(where: { text.contains($0) }) {
                result.categoryCode = code
                break
            }
        }

        result.yuan = amount(from: text)
        return result
    }

    // MARK: - 金额

    private static func amount(from text: String) -> Int? {
        // 优先阿拉伯数字，取第一个 1–99999 的数
        if let value = firstArabicNumber(in: text), (1...99_999).contains(value) {
            return value
        }
        // 退而求其次：中文数字（三十、两百、一千五 这类简单写法）
        if let value = firstChineseNumber(in: text), (1...99_999).contains(value) {
            return value
        }
        return nil
    }

    private static func firstArabicNumber(in text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        guard !digits.isEmpty, let value = Double(digits) else { return nil }
        return Int(value.rounded())
    }

    private static let digitMap: [Character: Int] = [
        "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    private static let unitMap: [Character: Int] = ["十": 10, "百": 100, "千": 1_000]

    /// 只处理「三十」「一百二」「两千五」这类常见口语，不支持万以上。
    private static func firstChineseNumber(in text: String) -> Int? {
        var total = 0
        var current: Int?
        var matched = false

        for character in text {
            if let digit = digitMap[character] {
                current = digit
                matched = true
            } else if let unit = unitMap[character] {
                total += (current ?? 1) * unit
                current = 0
                matched = true
            } else if matched, current != nil {
                // 遇到非数字字符，先把最后一位收尾
                total += current ?? 0
                return total > 0 ? total : nil
            } else if matched {
                break
            }
        }

        if matched {
            total += current ?? 0
        }
        return total > 0 ? total : nil
    }
}
