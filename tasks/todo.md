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

## 2026-04-13 文章页菜单调整

- [x] 定位文章页双击单词展开菜单的实现位置
- [x] 移除自定义“翻译”菜单项，并将“收藏”前置到 `Lookup` 位置
- [x] 编译验证文章页菜单调整没有引入回归

### Review

- 实现结果：移除了选词菜单里的自定义“翻译”按钮，仅保留系统菜单，并把自定义“收藏”替换到系统 `Lookup` 的原位置。
- 代码清理：同步移除了 `SelectableAttributedTextView` 中仅服务于选词翻译的回调链路，避免保留无用参数。
- 验证结果：`xcodebuildmcp build_sim -quiet` 编译通过。

## 2026-04-13 菜单修正

- [x] 分析用户纠正，确认问题是误删系统 `translator`
- [x] 调整选词菜单逻辑为“收藏插到 `Lookup` 前，保留原系统 `translator`”
- [x] 重新编译并启动 iPhone 17 验证修正生效

### Review

- 根因修复：原实现把整个 `Lookup` 菜单替换成“收藏”，连系统 `Translate` 一起移除了；现已改为在 `Lookup` 前插入“收藏”，保留后续系统项。
- 运行验证：`xcodebuildmcp build_run_sim -quiet` 在 `iPhone 17` 成功启动。
- UI 证据：当前可访问性树中已看到 `Copy / 收藏 / Look Up / Translate`，说明菜单顺序和保留项均符合预期。

## 2026-04-13 收藏页动画优化

- [x] 定位收藏页点击单词时的动画与状态更新实现
- [x] 优化点击单词动画，消除进入详情时的抖动
- [x] 编译并运行验证收藏页交互无回归

### Review

- 根因分析：收藏页原实现同时使用 `withAnimation` 和 `.move(edge: .top)` 过渡，`List` 在行高变化时会叠加位移动画，导致点击展开句子时出现抖动。
- 实现结果：已将点击切换收敛到 `toggleExpandedWord(_:)`，并把句子展开动画改成仅透明度过渡，保留点击反馈但去掉会引发抖动的位移效果。
- 验证结果：`xcodebuildmcp build_run_sim -quiet` 在 `iPhone 17` 启动成功；运行中已实际打开收藏页，截图见 `/var/folders/3d/68946v9n4h17f9hfg4_862d80000gn/T/screenshot_optimized_85419eec-526c-4bff-87b6-0ad0179d0a3d.jpg`。

## 2026-04-13 收藏页动画二次修正

- [x] 分析单词仍然跳动的原因
- [x] 将收藏行改为稳定结构，折叠时显示一行例句摘要
- [x] 编译运行并验证收藏页折叠态与展开态交互

### Review

- 根因分析：即使去掉位移动画，只要收藏行仍然通过条件插入/移除例句视图，`List` 仍会对整行做高度重排，单词会跟着产生跳动感。
- 实现结果：收藏行改为始终渲染例句文本，折叠态使用单行摘要，展开态显示完整例句；点击时只切换 `lineLimit` 和文字样式，不再插入/删除子视图。
- 验证结果：`xcodebuildmcp build_run_sim -quiet` 在 `iPhone 17` 启动成功；当前收藏页可访问性树中，`integration` 下方已直接看到一行摘要例句，说明折叠态生效。

## 2026-04-13 收藏页样式统一

- [x] 对比收藏页与首页/文章页的现有视觉实现
- [x] 将收藏页背景、卡片和分组样式统一到应用主体风格
- [x] 编译并运行验证收藏页视觉改动无回归

### Review

- 视觉统一：收藏页现在复用了应用的暖色纸张背景、暖橙标题色和手绘卡片底板，不再保留系统 `List` 的白底分组观感。
- 工程整理：将首页文章卡片原先私有的纸片形状提炼到 `ReadingTheme.swift` 里做共享背景组件，首页文章卡片和收藏卡片改为同一套底板。
- 交互保留：移除 `onDelete` 后，收藏删除动作改为卡片侧滑删除，避免样式统一时丢失原有删除能力。
- 验证结果：`xcodebuildmcp build_run_sim -quiet` 在 `iPhone 17` 启动成功；运行截图见 `/var/folders/3d/68946v9n4h17f9hfg4_862d80000gn/T/screenshot_optimized_ff2686a8-9c56-434a-bb3f-b30a54ebf22b.jpg`。

## 2026-04-13 文章菜单中文化

- [x] 确认系统菜单英文的根因在工程本地化配置
- [x] 修正开发语言和混合本地化配置，让系统菜单跟随中文
- [x] 重新生成工程并验证文章选词菜单显示为中文

### Review

- 根因分析：工程生成结果里 `VocabReader.xcodeproj/project.pbxproj` 原本是 `developmentRegion = en;`，同时 `VocabReader/Info.plist` 缺少 `CFBundleAllowMixedLocalizations`，所以文章页选词菜单优先落回了 UIKit 的英文系统资源。
- 实现结果：已在 [project.yml](/Users/wenren/code/swiftui/VocabReader/project.yml:1) 将开发语言切到 `zh-Hans`，并在 [Info.plist](/Users/wenren/code/swiftui/VocabReader/VocabReader/Info.plist:1) 启用 `CFBundleAllowMixedLocalizations`，随后用 `xcodegen generate` 重建工程。
- 验证结果：`xcodebuildmcp build_run_sim -quiet` 在 `iPhone 17` 启动成功；当前模拟器选词菜单已显示为 `拷贝 / 收藏 / 查询 / 翻译 / 搜索网页 / 共享…`。

## 2026-04-13 收藏成功提示

- [x] 定位文章页收藏动作的现有链路
- [x] 添加顶部“收藏成功”提示，并在 1 秒后自动消失
- [x] 编译并运行验证收藏提示无回归

### Review

- 实现结果：文章页选词菜单点击“收藏”后，会在页面顶部显示“收藏成功”胶囊提示；若用户连续收藏，新的提示会重置 1 秒消失计时，不会提前闪退。
- 代码落点：在 [ArticleReaderView.swift](/Users/wenren/code/swiftui/VocabReader/VocabReader/Views/ArticleReaderView.swift:1) 新增 `showBookmarkToast` 与 `bookmarkToastPresentationID` 状态，并通过 `presentBookmarkSuccessToast()` 驱动顶部 overlay 展示。
- 验证结果：`xcodebuildmcp build_run_sim -quiet` 在 `iPhone 17` 编译并启动成功，当前改动未引入构建回归。

## 2026-04-13 推送与 App Store Connect 发布

- [x] 盘点当前待发布改动并完成本地提交
- [x] 推送 `main` 到远端仓库
- [x] 确认发布签名、构建号与 App Store Connect 上传链路
- [x] 完成归档与上传，记录发布结果

### Review

- 提交结果：已提交 `2bf594b fix: polish article reader and restore release config`，并推送到 `origin/main`。
- 根因修复：已把 `DEVELOPMENT_TEAM / MARKETING_VERSION / CURRENT_PROJECT_VERSION` 从易被 `xcodegen` 覆盖的工程文件回收到 [project.yml](/Users/wenren/code/swiftui/VocabReader/project.yml:1)，同时让 [Info.plist](/Users/wenren/code/swiftui/VocabReader/VocabReader/Info.plist:1) 读取构建设置，避免后续重新生成工程时丢失发布配置。
- 发布版本：当前上传包版本为 `1.0 (202604132150)`。
- 归档结果：`xcodebuild archive -allowProvisioningUpdates` 成功，归档路径为 `/tmp/VocabReader-AppStoreConnect.xcarchive`，签名身份为 `Apple Development: ren wen (4HXCVF58F5)`，团队为 `N4TQ2P9B46`。
- 上传结果：`xcodebuild -exportArchive` 使用 `method = app-store-connect` 和 `destination = upload` 成功上传，终态为 `Uploaded package is processing.`，分发日志路径为 `/var/folders/3d/68946v9n4h17f9hfg4_862d80000gn/T/VocabReader_2026-04-13_21-55-56.548.xcdistributionlogs`。
