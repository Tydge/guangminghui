# 光明会：暗流对决

本地 1V1 卡牌游戏，玩家对离线规则 AI。使用 Godot 4.6.2 / GDScript / Compatibility 渲染。

## 运行

在 Godot 中打开本目录的 `project.godot`，等待首次资源导入，按 **F5** 运行整个项目。主场景为 `scenes/main.tscn`。无需导出试玩包或 APK。离线运行，无需 API 密钥。

在其他电脑继续开发：

```powershell
git clone https://github.com/Tydge/guangminghui.git
cd guangminghui
```

使用 Godot 4.6.2 打开 `project.godot` 并等待首次导入。仓库包含全部运行素材，不依赖原电脑路径；`.godot/` 缓存会自动生成。

## 操作

- 选择光明会，再从五张起手团体中选初始手下；可至多2次将全部团体手牌放回共享堆洗匀并重抽等量，阴谋不变。开局点击卡面仅查看，点击「选择」按钮确认。AI 独立选择，随后掷骰决定先手，后手额外抽1张阴谋。
- 空白桌面拖动平移，滚轮或双指缩放；「己方 / 对手 / 全局」定位。普通选牌和出牌保留镜头位置。
- 单击选牌后使用下方动作。自动接管选择上级，新团体当回合无行动标记且不能额外恢复；攻击选择目标后先预览，再确认花费行动。
- 可先选对手团体，点击「控制 / 摧毁」，再选高亮的己方带头团体；也保留先选带头者的方式。两种路径都先进入预览，确认前不消耗行动。
- 拖动战斗窗口或攻击预览的标题栏移动窗口；鼠标和触摸均支持。战斗响应刷新后保留位置，可将窗口暂时移至边缘查看势力树；标题始终保留可抓取的区域。
- 攻击预览简短列出可支援的团体及P/GP加值、可用阴谋与需先支援的阴谋；其余阴谋手牌折叠，点卡可查看具体条件。预览不支付标记或出牌。
- 悬停半秒、右键、长按或「查看大卡」查看完整卡面；移动超过 8 像素会取消长按，长按结束不触发普通点击。
- 大卡显示当前忠诚、位置、被动防御、控制/摧毁防御拆分、印刷与有效数值、附着及行动恢复状态；移动布局可滚动阅读；点击附着牌按钮可读完整效果，关闭后回到原团体和阅读位置。
- 战斗中轮流追加支援、阴谋或救援，双方连续放行后才掷骰。每项响应旁的「查看」可以先读卡。
- 战斗右侧持续记录双方支援团体、P/GP数值、阴谋对象与反制结果。结算后点击桌面的「最近战斗」回看。
- 双方打出阴谋、发动主动能力，以及救援/斡旋时，中央淡入完整卡牌、行动方和能力名，停留后淡出。展示彻底结束才支付费用和执行效果；期间阻止重复操作及AI继续行动。「减少动态效果」缩短淡入淡出，保留阅读停留与相同的结算顺序。
- 重组等多目标操作分步选择团体、上级和费用，场上高亮可选目标，允许返回或取消；确认前不支付。
- 抽牌从对应牌堆移向手牌，弃牌移向弃牌堆；未知牌只显示牌背。指定团体的阴谋展示后飞向并高亮目标。所有动效落点结束后才提交规则，期间锁定输入和 AI，重开会取消待执行动作。
- 有下属的团体可「收起 / 展开」。进入目标选择时自动展开相关分支。
- 点击牌堆查看公开弃牌、墓地与已公开的对手手牌；点击记录条查看对局记录。
- 设置中可调整音量、减少动态效果，以及在电脑上预览横屏移动布局。

## 本版内容

6 种光明会、130 种团体、50 种阴谋，共186种。两种共享牌堆每种卡各一张。所有卡均有独立插画，界面文字与数值由 Godot 绘制。共同维护的完整卡牌表是 `docs/光明会_全部卡牌完整效果_当前版.md`；用户阅读副本的位置见 `data/card_sync_config.json`。游戏运行时读取 `data/cards.json` 和规则引擎。

实现共享牌堆循环、主动能力、筛牌与私密排序、弃牌回收、行动恢复额度、位置与忠诚防御、整支夺取、摧毁下属回手、红十字会救援、吸血鬼转化、附着牌、单一公共秩序、交替响应、骗局反制、失败招募区与回合末胜利检查。

名人、地点、巨大与沿海标签参与支援、巡演、换位、委托攻击、防灾和重建。巨大按面积至少100万平方公里判定；日本、法国、德国、英格兰与瑞士不带巨大标签。

灾难对地点发动独立攻击，忽略阵营、忠诚和位置；通常使目标受灾，部分灾难达到差值才摧毁。受灾团体P/GP减半、不能行动或补标记、不计胜利，需重建。新世界秩序、反制、疏散、保险、防备、救援与普通战斗使用相同的交替响应及展示时序。详细规则以完整卡牌文档为准。

太空、科学、魔法、共产、军队、名人和绿色标签可相互配合。保镖挡下一次普通摧毁，监管调查将GP降为0且可用目标行动解除；律师可移除合法附着。技术融合和公有化授予的标签随易主保留、离场清除。抽牌和标签收益通过触发队列逐项显示来源，展示结束后结算。

大卡、小卡、手牌、选牌窗口和移动详情的图片区统一1:1，原图等比完整显示。选牌卡宽度统一、按钮始终可见；长卡名适配字号后换行。普通团体和阴谋按各自主题使用不同色彩与场景，不套用统一的光明会符号背景。

手牌分类与操作按钮共用一行，桌面在900逻辑像素高时可见高度489（原405）。场上卡138×192、手牌94×142；层间距28。己方/对手定位同时考虑树的宽度与高度，深层结构可完整纳入镜头，再用缩放和平移查看细节。

紧凑卡面为名字、数值与阵营保留三行完整文字：场上卡的P/GP/R和阵营使用12号深色字，手牌使用11号深色字；三阵营手牌用空格分隔，避免隐藏其中一项。卡片外部尺寸不变，正方形插画在必要时略缩小并居中完整显示。

图鉴分类分页显示，异步加载当前页插画并预读下一页；文字按完整行排版。

## 修改卡牌

用户可在当前版Markdown表格修改卡牌，再让开发者同步进游戏。在新电脑默认使用项目内总表；如需额外的阅读副本，复制 `data/card_sync_config.example.json` 为 `data/card_sync_config.json`，填写本机路径（此配置不上传）。原电脑配置中的路径不存在时也会退回项目内总表。以下工具会按字段合并用户表格、项目表格及运行数据，保护双方各自的修改：

```powershell
python tools/card_table.py check
python tools/card_table.py sync
```

修改技能、胜利条件或费用时，必须同时实现、验证对应规则，再用 `sync --accept-rule-text` 完成同步。工具会阻止未确认的规则文字变更，以及同一字段的冲突；不会把技能文字自动当作已实现的程序。新增卡牌也需同步表格、规则及素材。

AI 使用自己手牌、公开场面和被合法揭示的信息；`AiAgent` 不持有 `GameState` 引用。决策只接收脱敏 observation，不接收牌堆顺序或对手隐藏手牌。它是规则与估值 AI，不需要联网或 API 密钥。

## 目录

- `scripts/game_state.gd`：规则、合法操作和信息边界。
- `scripts/wave_rules.gd`：名人、地点、灾难、重建及相应触发队列。
- `scripts/synergy_rules.gd`：太空、魔法、共产、军队等标签联动，以及保镖和监管附着。
- `scripts/ai_agent.gd`：离线 AI。
- `scripts/board_view.gd`：势力树布局、镜头、折叠和移动。
- `scripts/card_view.gd`、`scripts/card_text_layout.gd`：卡面完整行排版、悬停、长按与选择。
- `scripts/action_flow.gd`：规则副本预演、抽弃牌和目标移动计划，保持真实对局及 RNG 在动效结束前不变。
- `scripts/action_picker.gd`、`scripts/game_interactions.gd`：分步选目标、分页图鉴、附着牌阅读与移动动效。
- `scripts/main.gd`：菜单、对局、响应、选择、图鉴和设置。
- `scripts/panel_drag_handle.gd`：浮动窗口标题的鼠标/触摸拖动、边界约束及手势释放。
- `data/cards.json`：全部186种卡牌，可修改数值和文案。
- `docs/光明会_全部卡牌完整效果_当前版.md`：与用户共同维护的唯一完整卡牌文档。
- `tools/card_table.py`：卡牌表格与数据的双向合并、冲突检测及完整性检查。
- `assets/cards/`：逐卡插画，稳定 ID 命名。
- `assets/ui/`：生成的桌布、界面框和两种牌背。
- `docs/art-prompts.json`：最终生图提示词与资产记录。
- `tests/`：规则、特殊效果和交互测试；报告在本机生成并被 Git 忽略。截图默认写入 Godot 用户目录的 `test-captures/`，支持 `--output=绝对路径`。

## 测试

使用 Godot 控制台入口运行：

```powershell
godot --headless --path . --script res://tests/test_rules.gd
godot --headless --path . --script res://tests/test_effects.gd
godot --headless --path . --script res://tests/test_expansion.gd
godot --headless --path . --script res://tests/test_synergy.gd
godot --headless --path . --script res://tests/test_opening_balance.gd
godot --headless --path . --script res://tests/test_interaction_polish.gd
godot --headless --path . --script res://tests/test_ui.gd
godot --headless --path . --script res://tests/test_battle_clarity.gd
godot --headless --path . --script res://tests/test_modern_mechanics.gd
godot --headless --path . --script res://tests/test_modern_ui.gd
godot --headless --path . --script res://tests/test_presentation.gd
godot --headless --path . --script res://tests/test_expansion_ui.gd
godot --headless --path . --script res://tests/test_synergy_ui.gd
godot --headless --path . --script res://tests/test_match.gd
python tests/test_card_sync.py
```

也可运行 `tests/run_checks.ps1`，默认使用 PATH 中的 `godot` 和 `python`；未配置 PATH 时传入 `-GodotPath` 与 `-PythonPath` 的完整路径。Python 仅用于同步工具和测试，不是运行游戏所需。测试覆盖真实规则状态与输入处理，并不替代实际安卓设备的触摸、性能和安全区验证。本轮完成桌面实际渲染与横屏布局模拟，未做 APK/真机测试。首版阈值和 AI 强度仍需人工试玩平衡。

## 素材

- 卡牌、桌布、框与牌背：使用内置图像生成工具逐资产生成，以保留原始尺寸的高质量 WebP 存放（界面无损），190张合计约213 MB，较PNG减少约62%；未裁切、未缩小。提示词见 `docs/art-prompts.json`，逐图压缩与质量记录见 `docs/image-compression.json`。记录中的 `generation_source` 仅作历史追溯，不是运行依赖。
- 音效：[Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)，CC0，原始许可见 `assets/audio/Kenney-License.txt`。用于选牌、按钮、落牌、开启、关闭、掷骰、成功、失败及反制；可在设置静音。
- 字体：[Google Fonts / Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，SIL Open Font License，许可见 `assets/fonts/OFL.txt`。
- 名称和主题参考 Steve Jackson Games 的 INWO。本项目是本地非官方简化改编；卡牌数值、能力和插画均不代表原版卡面。
