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

    private struct Candidate {
        let value: Int
        let end: String.Index
    }

    /// 句子里可能有好几个数字：「一瓶香水500块」里的 1 是量词，500 才是金额。
    /// 优先取紧跟「块 / 元 / 钱」的，其次取最大的。
    private static func amount(from text: String) -> Int? {
        let candidates = numberCandidates(in: text).filter { (1...9_999_999).contains($0.value) }
        guard !candidates.isEmpty else { return nil }

        if let last = candidates.last(where: { isFollowedByMoneyUnit($0.end, in: text) }) {
            return last.value
        }
        // 没有钱单位时取最大的：一份、两杯、三次这类量词通常比金额小
        return candidates.map(\.value).max()
    }

    /// 扫描所有数字（阿拉伯与中文），记录每个数字结束的位置
    private static func numberCandidates(in text: String) -> [Candidate] {
        var results: [Candidate] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            // 只把半角阿拉伯数字当「阿拉伯数字」：汉字数字（三、十）的 isNumber 也是 true
            if character.isASCII, character.isNumber {
                var end = index
                var digits = ""
                var sawDot = false
                while end < text.endIndex {
                    let current = text[end]
                    if current.isASCII, current.isNumber {
                        digits.append(current)
                        end = text.index(after: end)
                    } else if current == ".", !sawDot, !digits.isEmpty {
                        sawDot = true
                        digits.append(current)
                        end = text.index(after: end)
                    } else {
                        break
                    }
                }
                if let value = Double(digits) {
                    results.append(Candidate(value: Int(value.rounded()), end: end))
                }
                index = end
            } else if digitMap[character] != nil || unitMap[character] != nil {
                var end = index
                var total = 0
                var current: Int?
                while end < text.endIndex {
                    let next = text[end]
                    if let digit = digitMap[next] {
                        current = digit
                        end = text.index(after: end)
                    } else if let unit = unitMap[next] {
                        total += (current ?? 1) * unit
                        current = 0
                        end = text.index(after: end)
                    } else {
                        break
                    }
                }
                total += current ?? 0
                if total > 0 {
                    results.append(Candidate(value: total, end: end))
                }
                index = end
            } else {
                index = text.index(after: index)
            }
        }

        return results
    }

    /// 数字后面紧跟「块 / 元 / 钱 / 毛 / 角」就认为它是金额
    private static func isFollowedByMoneyUnit(_ index: String.Index, in text: String) -> Bool {
        var cursor = index
        var steps = 0
        while cursor < text.endIndex, steps < 2 {
            let character = text[cursor]
            if character == " " {
                cursor = text.index(after: cursor)
                steps += 1
                continue
            }
            return ["块", "元", "钱", "毛", "角"].contains(String(character))
        }
        return false
    }

    private static let digitMap: [Character: Int] = [
        "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    private static let unitMap: [Character: Int] = ["十": 10, "百": 100, "千": 1_000]

}
