- [x] 现状分析：梳理文章类型、生成设置、Prompt 约束、UI 展示与测试覆盖点
- [x] 功能设计：定义新增文章类型与“真实性强约束”在数据模型中的落点
- [x] 风险决策：确认“客户”是否指“客服/客户案例”主题，并确认真实性约束适用范围
- [x] 用户确认轻量 Spec（HARD-GATE）
- [x] 实现模型与设置持久化改动
- [x] 实现 Prompt 与文章展示改动
- [x] 补齐并运行相关测试

## Review

- 实现结果：已拆分“文章体裁”和“文章主题”，并为科技、医疗、客户、AI 主题加入更强的真实性 Prompt 约束。
- 工程调整：新增 `ArticleTopic.swift` 后已通过 `xcodegen generate` 重建 `VocabReader.xcodeproj`，确保新文件进入工程。
- 验证结果：`xcodebuildmcp test_sim -quiet` 通过，65/65 测试通过。
- 已知告警：`ArticleReaderView.swift` 里 `UITextItemInteraction` 仍是 iOS 17 弃用 API，但当前不影响编译和测试通过。
- 修复结果：已移除设置页保存后回调首页刷新的链路，保存设置不再触发首页自动重新加载。
- 增量修复：保存设置后会同步首页后续分页使用的词汇数量参数，但不会清空当前文章列表或触发首页重载。
