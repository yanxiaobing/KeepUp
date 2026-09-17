# 预置配置资源

预置数据统一使用 JSON；Swift 定义数据结构、校验规则和业务算法。用户记录仍由 WCDB 保存。

| 文件 | 内容 | 原版来源 |
| --- | --- | --- |
| `KeepUp/Resources/cards.json` | 45 张卡的稳定 ID、原版编号、单位、顺序、文案键和图片；6 张初始卡的历史迁移配置 | `database.db` / `CARD`（排除自定义模板） |
| `KeepUp/Resources/activity-energy.json` | 31 组热量系数、39 项食物、匹配份数上限、兜底食物 ID | `database.db` / `CARD_CALORIE` 和 `calorie_match_food.plist` |
| `KeepUp/Resources/themes.json` | 14 套主题及颜色、图片 | `database.db` / `CALENDAR_STYLE` |

三类配置使用 `BundledJSON` 统一读取，并在首次读取时缓存。卡片和热量配置有 `version` 字段；当前支持版本 1。缺失、格式错误或校验不通过的必需资源会明确报错，不会静默使用空目录。所有 JSON 已加入 Xcode Copy Bundle Resources；重新生成项目的脚本也会自动包含 JSON。

显示文案继续集中在 `Localizable.xcstrings`。JSON 保存文案键，食物使用稳定的语义 ID（如 `chickenNugget`），文案不再通过数组下标关联。食物数组顺序仅用于沿用原版的同误差优先级；小热量和超范围兜底均通过 ID 指定。

## 修改和检查

- 修改卡片、图片映射、系数或食物时编辑对应 JSON，无需改 Swift 常量。
- 新增名称时同步添加中英文 string catalog 条目。
- 卡片 `id` 是持久化身份，不随改名或排序修改；`legacyStarters` 保持历史值，用于旧 schema 升级。
- 历史热量目前从数量派生。不要直接改变版本一系数；若要调整算法或系数，需同时引入记录版本或结果快照。
- `python3 Scripts/validate_configuration.py` 检查跨资源引用、图片存在性、文案翻译和配置值，不依赖原 PunchCard 工程。
- 单元测试检查 Bundle 打包读取、错误版本、缺失/重复引用、非法系数和旧数据库升级；UI 测试覆盖输入、详情、分享、时间线和重启后的中英文显示。

此次迁移核对原版 31 组热量系数、39 项食物的能量、顺序和中文份量，全部一致。
