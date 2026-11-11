import Foundation

/// 从一句中文里抽出「分类」和「金额」。
/// 只做高置信度的简单匹配：匹配不到就留空，让用户自己点，绝不猜。
enum VoiceParser {
    struct Result {
        var categoryCode: CategoryCode?
        var yuan: Int?
        /// 句子里有没有明确的「钱」的线索（块 / 元 / 花 / 付…）。
        /// 用来区分「苹果12」的 12 是型号、「花了50」的 50 是金额。
        var hasMoneyCue = false

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
        (.daily, ["纸巾", "洗衣液", "垃圾袋", "日用品", "清洁剂", "洗洁精"]),
        (.wear, ["衣服", "鞋", "裤子", "外套", "帽子"]),
        (.gear, ["充电宝", "充电器", "数据线", "手机", "平板", "电脑", "耳机", "键盘", "相机", "支架", "硬盘", "数码", "配件"]),
        (.appliance, ["冰箱", "洗衣机", "空调", "家具", "沙发", "电视"]),
        (.health, ["医院", "看病", "买药", "体检"]),
        (.social, ["红包", "随礼", "请客", "礼物"]),
        (.subscription, ["会员", "话费", "宽带", "订阅"]),
    ]

    static func parse(_ text: String) -> Result {
        let normalized = normalize(text)
        var result = Result()

        for (code, words) in keywords {
            if words.contains(where: { normalized.contains($0) }) {
                result.categoryCode = code
                break
            }
        }

        result.yuan = amount(from: normalized)
        result.hasMoneyCue = ["块", "元", "钱", "花", "付"].contains { normalized.contains($0) }
        return result
    }

    /// 全角数字转半角，避免「３０」解析不出金额。
    static func normalize(_ text: String) -> String {
        String(text.map { character in
            guard let scalar = character.unicodeScalars.first,
                  (0xFF10...0xFF19).contains(scalar.value),
                  let ascii = UnicodeScalar(scalar.value - 0xFF10 + 0x30) else {
                return character
            }
            return Character(ascii)
        })
    }

    // MARK: - 金额

    private static func amount(from text: String) -> Int? {
        if let value = firstArabicNumber(in: text), (1...99_999).contains(value) {
            return value
        }
        if let value = firstChineseNumber(in: text), (1...99_999).contains(value) {
            return value
        }
        return nil
    }

    /// 取第一段连续数字（允许小数），忽略其余字符。
    private static func firstArabicNumber(in text: String) -> Int? {
        var digits = ""
        var started = false

        for character in text {
            if character.isNumber || (character == "." && started) {
                digits.append(character)
                started = true
            } else if started {
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
                total += current ?? 0
                return total > 0 ? total : nil
            } else if matched {
                // 数字后直接跟汉字（如「三十块」），收尾返回
                total += current ?? 0
                return total > 0 ? total : nil
            }
        }

        if matched { total += current ?? 0 }
        return total > 0 ? total : nil
    }
}
