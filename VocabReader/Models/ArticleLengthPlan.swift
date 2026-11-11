import Foundation

/// 按目标词数量给出篇幅和段落数，词越多文章越长，避免目标词在短文里挤成一团。
struct ArticleLengthPlan: Equatable {
    /// 平均每个目标词配 16-22 个英文单词的上下文。
    private static let wordsPerTargetRange = 16...22
    private static let minimumWordRange = 90...140
    /// 手机上一段约 60 个英文单词读起来比较舒服。
    private static let wordsPerParagraph = 60.0
    /// 对话每轮约 18 个英文单词，即一到两句。
    private static let wordsPerDialogueTurn = 18.0

    let wordRange: ClosedRange<Int>
    let paragraphRange: ClosedRange<Int>
    let dialogueTurnRange: ClosedRange<Int>

    init(targetWordCount: Int) {
        let count = max(targetWordCount, 1)
        let lowerWords = max(Self.minimumWordRange.lowerBound, count * Self.wordsPerTargetRange.lowerBound)
        let upperWords = max(Self.minimumWordRange.upperBound, count * Self.wordsPerTargetRange.upperBound)
        wordRange = lowerWords...upperWords
        paragraphRange = Self.unitRange(words: wordRange, wordsPerUnit: Self.wordsPerParagraph, minimum: 2)
        dialogueTurnRange = Self.unitRange(words: wordRange, wordsPerUnit: Self.wordsPerDialogueTurn, minimum: 4)
    }

    private static func unitRange(words: ClosedRange<Int>, wordsPerUnit: Double, minimum: Int) -> ClosedRange<Int> {
        let lower = max(minimum, Int((Double(words.lowerBound) / wordsPerUnit).rounded()))
        let upper = max(lower + 1, Int((Double(words.upperBound) / wordsPerUnit).rounded()))
        return lower...upper
    }
}
