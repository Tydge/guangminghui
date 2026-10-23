# 光明会：暗流对决

1V1 卡牌游戏，支持离线规则AI与在线好友对战。使用 Godot 4.6.2 / GDScript / Compatibility 渲染。

## 运行

Windows完整包：[直接下载](https://47.119.37.251/Illuminati-Windows.zip)（0.3.0，约240.5 MiB）。解压后运行`Illuminati.exe`，首次默认英文；0.2.0可通过游戏内检查更新下载约505 KiB的累积补丁，返回菜单后一键应用并自动重新打开。更新服务不可用时仍可离线游戏。发布、补丁和服务器维护见[更新服务](docs/更新服务.md)。

在 Godot 中打开本目录的 `project.godot`，等待首次资源导入，按 **F5** 运行整个项目。主场景为 `scenes/main.tscn`。无需导出试玩包或 APK。离线运行，无需 API 密钥。

主菜单「好友对战」可创建房间或输入6位房间号，双方准备后开局。每回合120秒、每次战斗／反制响应15秒，圆环显示双方时间。在线对战强制完整动画，语言、音量与布局各自独立；双方完成动画后统一开始计时。断线自动重连，结果页可在原房间再来一局。详细流程及运维见[好友对战](docs/好友对战.md)。

开局可选简单、普通、困难AI，设置中也可随时切换。三档统一使用新版AI，主要阶段分别最多前瞻1／2／4步；估值、候选筛选、搜索宽度、采样、攻防与资源逻辑全部相同，不额外加入随机失误。战斗／反制均比较完整当前战斗；大局面统一收紧预算，步数是上限。骰子、规则和信息权限不随难度改变。

设置中可通过「语言 / Language」切换中文和 English，并自动记住选择。卡牌、菜单、帮助、选择窗口、战斗记录和提示同步切换。英文入门说明见 [Basic Rules](docs/Quick_Start_EN.md)，包含数值、阵营对立、标签、忠诚、位置及P／GP支援规则；游戏内「玩法与操作 → 阵营与标签」也可查阅。

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
- 选择、战斗和预览窗口的「查看战场」可暂时收起窗口，平移缩放并查看场上与手牌；本地对局与AI暂停，在线思考时间继续。点击「返回操作窗口」继续原来的选择，保留已选目标和阅读位置。
- 攻击预览简短列出可支援的团体及P/GP加值、可用阴谋与需先支援的阴谋；其余阴谋手牌折叠，点卡可查看具体条件。预览不支付标记或出牌。
- 悬停半秒、右键、长按或「查看大卡」查看完整卡面；移动超过 8 像素会取消长按，长按结束不触发普通点击。
- 大卡显示当前忠诚、位置、被动防御、控制/摧毁防御拆分、印刷与有效数值、附着及行动恢复状态；移动布局可滚动阅读；点击附着牌按钮可读完整效果，关闭后回到原团体和阅读位置。
- 战斗中轮流追加支援、阴谋或救援，双方连续放行后才掷骰。每项响应旁的「查看」可以先读卡。
- 战斗的「不再追加」和反制窗口的「放行」固定在所有响应之后；攻击预览合计包含可用资源的直接强度加成，条件效果和固定骰点单独列出。
- 骰子先滚动并展示结果，窗口完全淡出后才开始目标控制转移、摧毁及下属回手。结果窗口存在期间真实场面与随机状态保持不变；决定胜负的一击也先展示结果，再进入胜利界面。
- 桌面动效期间，战斗等覆盖窗口暂时隐藏，完成后恢复。所有操作都等待进场、离场及布局移动完成，再继续后续选择或触发；战后抽牌、恢复行动逐项展示来源并结算，最后才宣告胜利。
- 结束面板显示获胜方及具体原因；目标阴谋获胜时展示对应卡牌。「查看战场」可回看已结束的桌面和手牌，点击「返回结果」恢复结算窗口。
- 战斗右侧持续记录双方支援团体、P/GP数值、阴谋对象与反制结果。结算后点击桌面的「最近战斗」回看。
- 双方打出阴谋、发动主动能力，以及救援/斡旋时，中央淡入完整卡牌、行动方和能力名，停留后淡出。展示彻底结束才支付费用和执行效果；期间阻止重复操作及AI继续行动。「减少动态效果」缩短淡入淡出，保留阅读停留与相同的结算顺序。
- 重组等多目标操作分步选择团体、上级和费用，场上高亮可选目标，允许返回或取消；确认前不支付。
- 抽牌从对应牌堆移向手牌，弃牌移向弃牌堆；未知牌只显示牌背。指定团体的阴谋展示后飞向并高亮目标。所有动效落点结束后才提交规则，期间锁定输入和 AI，重开会取消待执行动作。
- 有下属的团体可「收起 / 展开」。进入目标选择时自动展开相关分支。
- 点击牌堆查看公开弃牌、墓地与已公开的对手手牌；点击记录条查看对局记录。
- 设置中可调整音量、减少动态效果，以及在电脑上预览横屏移动布局。

## 本版内容

12种光明会、170种团体、70种阴谋、23种资源，共275种。团体、资源、阴谋各用独立共享牌堆，每种卡各一张。所有卡均有独立插画，界面文字与数值由 Godot 绘制。共同维护的完整卡牌表是 `docs/光明会_全部卡牌完整效果_当前版.md`；用户阅读副本的位置见 `data/card_sync_config.json`。游戏运行时读取 `data/cards.json` 和规则引擎。

初始团体选择后，每人从随机5张资源候选中选1张入手，可独立重随2次。回合开始不自动抽资源。主要阶段的「抽牌」入口可花主牌1行动，从三堆任选一堆抽1张；资源手牌默认上限2，满额只禁止抽资源。秘密保险库可提高资源与阴谋手牌上限。

部署资源与自动接管各每回合1次，通常各花主牌1行动。场上资源最多2张，位于各自主牌左右；满额时可报废替换1张。资源不占控制槽、不接控制线、不计团体胜利目标。行动资源进场当回合为0标记，下次己方回合补至1；持续、触发与报废使用的资源不显示行动标记。资源部署、使用、替换与报废先完整展示，之后才提交规则。普通团体攻击不能直接以资源为目标，精密爆破与技术封锁等明确效果可以影响资源。

目标阴谋藏在手牌中并占阴谋上限，每人最多保留1张。己方主要阶段达标后主动打出「宣告胜利」，可以被普通反制取消；不会在回合末自动亮出。未公开的目标及进度只对持有者显示。主牌目标仍在回合末检查。香格里拉可将暴力转为和平，赫尔墨斯门徒让魔法团体以P互相支援普通攻击和防守。

实现共享牌堆循环、主动能力、筛牌与私密排序、弃牌回收、行动恢复额度、位置与忠诚防御、整支夺取、摧毁下属回手、红十字会救援、吸血鬼转化、附着牌、单一公共秩序、交替响应、骗局反制、失败招募区与回合末胜利检查。

名人、地点、巨大与沿海标签参与支援、巡演、换位、委托攻击、防灾和重建。巨大按面积至少100万平方公里判定；日本、法国、德国、英国与瑞士不带巨大标签。

灾难对地点发动独立攻击，忽略阵营、忠诚和位置；通常使目标受灾，部分灾难达到差值才摧毁。受灾团体P/GP减半、不能行动或补标记、不计胜利，需重建。新世界秩序、反制、疏散、保险、防备、救援与普通战斗使用相同的交替响应及展示时序。详细规则以完整卡牌文档为准。

太空、科学、魔法、共产、军队、名人和绿色标签可相互配合。保镖挡下一次普通摧毁，监管调查将GP降为0且可用目标行动解除；律师可移除合法附着。技术融合和公有化授予的标签随易主保留、离场清除。抽牌和标签收益通过触发队列逐项显示来源，展示结束后结算。

大卡、小卡、手牌、选牌窗口和移动详情的图片区统一1:1，原图等比完整显示。选牌卡宽度统一、按钮始终可见；长卡名适配字号后换行。12张主牌分页选择，每页4张。光明会插画采用高辨识度的神秘主义象征；普通团体和阴谋继续按各自主题使用清晰的当代场景。

手牌分类与操作按钮共用一行，桌面在900逻辑像素高时可见高度489（原405）。场上卡138×192、手牌94×142；层间距28。己方/对手定位同时考虑树的宽度与高度，深层结构可完整纳入镜头，再用缩放和平移查看细节。

紧凑卡面为名字、数值与阵营保留三行完整文字：场上卡的P/GP/R和阵营使用12号深色字，手牌使用11号深色字；三阵营手牌用空格分隔，避免隐藏其中一项。卡片外部尺寸不变，正方形插画在必要时略缩小并居中完整显示。

图鉴分类分页显示，异步加载当前页插画并预读下一页；文字按完整行排版。鼠标放在卡面上时，滚轮仍可滚动图鉴。

## 修改卡牌

用户可在当前版Markdown表格修改卡牌，再让开发者同步进游戏。在新电脑默认使用项目内总表；如需额外的阅读副本，复制 `data/card_sync_config.example.json` 为 `data/card_sync_config.json`，填写本机路径（此配置不上传）。原电脑配置中的路径不存在时也会退回项目内总表。以下工具会按字段合并用户表格、项目表格及运行数据，保护双方各自的修改：

```powershell
python tools/card_table.py check
python tools/card_table.py sync
```

修改技能、胜利条件或费用时，必须同时实现、验证对应规则，再用 `sync --accept-rule-text` 完成同步。工具会阻止未确认的规则文字变更，以及同一字段的冲突；不会把技能文字自动当作已实现的程序。新增卡牌也需同步表格、规则及素材。英文译文和来源快照维护在 `data/localization/en.json`；同步中文卡文后需核对并更新对应英文，再运行 `python tools/check_localization.py` 检查遗漏、过期文本及占位符。

总表开头的阵营、标签数量由 `sync` 自动重算并更新所有阅读副本，`check` 也会发现统计过期。同卡可计入多个阵营／标签，但每个项目内只计一次；只统计牌面印刷属性，不计能力赋予的临时属性，统计数字无需人工修改。

AI 使用自己手牌、公开场面和被合法揭示的信息；`AiAgent` 不持有 `GameState` 引用。决策只接收脱敏 observation，不接收真实牌堆顺序、对手隐藏手牌或对局RNG。规划器从未见牌池构造两个独立样本，使用同一规则引擎预演后续合法动作、交替响应和结束回合，再比较双方局面。普通掷骰按完整2d6分布评估，固定骰按已知点数评估；后续随机抽弃牌、重掷仍使用样本。团体、资源和防守行动均有机会成本；不为每张准备卡另写后续结算。搜索在独立工作线程中计算，主线程逐帧等待，保持界面可响应；查看战场、打开设置和新对局会取消过期计划。大桌面按合法动作数量收紧候选与节点预算。它是规则与估值 AI，不需要联网或 API 密钥。

最近完整验收版`201aecd`对旧版困难AI为76/100胜：50个连续种子、同派系镜像、交换席位，0未结束和非法动作。统一三档时保留这版困难策略，只缩短简单／普通的前瞻深度；本轮用固定6场完整复跑核对困难档，不重跑100局或改写旧记录哈希。`tests/benchmark_challenger.gd`使用冻结旧策略`tests/ai_baseline/`；`tools/summarize_ai_benchmark.py`核验完整种子、席位、派系和版本哈希。风格、局限及复现步骤见[AI策略](docs/AI策略.md)，上次逐局结果见[强度记录](docs/ai_benchmark_current.json)。

补充[输家替换对照](docs/ai_replacement_current.json)：同种子先旧对旧，再匹配原输家席位的新AI对局，36/50翻盘；50个开局指纹一致，固定6场完整重跑复现。该对照复用原强度样本，不重复计数。

## 目录

- `scripts/game_state.gd`：规则、合法操作和信息边界。
- `scripts/wave_rules.gd`：名人、地点、灾难、重建及相应触发队列。
- `scripts/synergy_rules.gd`：太空、魔法、共产、军队等标签联动，以及保镖和监管附着。
- `scripts/covenant_rules.gd`：主牌目标、隐藏目标阴谋、主动宣告、和平转化和秘术共鸣。
- `scripts/ai_agent.gd`、`scripts/ai_tactics.gd`、`scripts/ai_planner.gd`：三档离线AI、公开局势估值与防守规划。
- `scripts/contemporary_rules.gd`：当代团体、世界秩序与秘宝等扩展机制。
- `scripts/board_view.gd`：势力树布局、镜头、折叠和移动。
- `scripts/card_view.gd`、`scripts/card_text_layout.gd`：卡面完整行排版、悬停、长按与选择。
- `scripts/action_flow.gd`：规则副本预演、抽弃牌和目标移动计划，保持真实对局及 RNG 在动效结束前不变。
- `scripts/action_picker.gd`、`scripts/game_interactions.gd`：分步选目标、分页图鉴、附着牌阅读与移动动效。
- `scripts/game_locale.gd`、`data/localization/en.json`：中英文显示与卡牌译文，不改变规则和命令。
- `scripts/main.gd`：菜单、对局、响应、选择、图鉴和设置。
- `scripts/window_access.gd`：动效时暂藏窗口、暂停查看战场及原操作恢复。
- `scripts/panel_drag_handle.gd`：浮动窗口标题的鼠标/触摸拖动、边界约束及手势释放。
- `scripts/resource_rules.gd`：独立资源堆、手牌容量、部署、资源能力及资源相关阴谋。
- `data/cards.json`：全部275种卡牌，可修改数值和文案。
- `docs/光明会_全部卡牌完整效果_当前版.md`：与用户共同维护的唯一完整卡牌文档。
- `docs/卡牌重做待确认.md`：尚未确认的农民抗议联盟能力提案，不代表游戏中的当前能力。
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
godot --headless --path . --script res://tests/test_renewal.gd
godot --headless --path . --script res://tests/test_housing_clone.gd
godot --headless --path . --script res://tests/test_covenant.gd
godot --headless --path . --script res://tests/test_covenant_ui.gd
godot --headless --path . --script res://tests/test_renewal_ui.gd
godot --headless --path . --script res://tests/test_opening_balance.gd
godot --headless --path . --script res://tests/test_interaction_polish.gd
godot --headless --path . --script res://tests/test_ui.gd
godot --headless --path . --script res://tests/test_battle_clarity.gd
godot --headless --path . --script res://tests/test_modern_mechanics.gd
godot --headless --path . --script res://tests/test_modern_ui.gd
godot --headless --path . --script res://tests/test_presentation.gd
godot --headless --path . --script res://tests/test_dice_sequence.gd
godot --headless --path . --script res://tests/test_flow_order.gd
godot --headless --path . --script res://tests/test_expansion_ui.gd
godot --headless --path . --script res://tests/test_synergy_ui.gd
godot --headless --path . --script res://tests/test_match.gd
python tests/test_card_sync.py
```

也可运行 `tests/run_checks.ps1`，默认使用 PATH 中的 `godot` 和 `python`；未配置 PATH 时传入 `-GodotPath` 与 `-PythonPath` 的完整路径。Python 仅用于同步工具和测试，不是运行游戏所需。测试覆盖真实规则状态与输入处理，并不替代实际安卓设备的触摸、性能和安全区验证。本轮完成桌面实际渲染与横屏布局模拟，未做 APK/真机测试。首版阈值和 AI 强度仍需人工试玩平衡。

AI镜像对局使用 `tests/benchmark_ai.gd`：`--pair=0/1/2`分别比较困难／普通、普通／简单、困难／简单；每个种子交换双方难度再打一次。默认包含完整合法动作和规则守恒检查，记录行动分布、树形、保留防守与重复操作。例：`godot --headless --path . --script res://tests/benchmark_ai.gd -- --test-defaults --pair=0 --seeds=8 --max-commands=1000`。`--offset`、`--stride`可抽取不同派系，`--label`区分报告；未结束的对局单独记为达到指令上限，不当作平局或胜利。当前结果和局限见 `docs/验证报告.md`。

## Windows试玩包

分享文件为 `outputs/windows/Illuminati-Windows-x64-EN.zip`，完整解压后运行 `Illuminati/Illuminati.exe`，EXE与同名PCK须放在一起。无需安装Godot。首次运行默认英文，可在设置中切回中文；本机F5开发版本保留原来的中文默认与玩家设置。

使用 `Windows Share` 导出预设。可重复执行 `python tools/export_windows.py --godot "本机Godot控制台程序的完整路径"`：工具仅补齐官方4.6.2 Windows x64 Release模板，导出后校验源纹理、优化PCK、逐图验证并运行正式EXE截图，最后生成ZIP、英文说明、许可与SHA-256。未通过验证不会生成新的分享包。产物、模板下载与截图不进Git。

优化只复用已证明解码像素一致的现有WebP数据，不重新编码或降低分辨率；有缩放或mipmap处理的纹理原样保留。格式实现参照 [Godot 4.6.2 PCK打包器](https://github.com/godotengine/godot/blob/4.6.2-stable/core/io/pck_packer.cpp) 与 [纹理导入器](https://github.com/godotengine/godot/blob/4.6.2-stable/editor/import/resource_importer_texture.cpp)。包内排除开发文档、测试、同步副本、缓存及照片原件，只保留运行资源与许可。

## 素材

- 卡牌、桌布、框与牌背：273张卡图及4张界面素材由内置图像生成工具制作，以高质量WebP存放；G084泰勒与G089梅西使用用户提供的真人照片，选取方形构图后无损转换。所有275张卡图均为1:1，完整显示且不拉伸、裁切。来源、提示词和处理记录见 `docs/art-prompts.json`，逐图压缩记录见 `docs/image-compression.json`。照片原件保存在 `assets/sources/`，通过 `.gdignore` 排除Godot导入；原作者和许可未随照片提供，不标记为开放许可。历史 `generation_source` 路径仅用于追溯，不是运行依赖。
- 音效：[Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)，CC0，原始许可见 `assets/audio/Kenney-License.txt`。用于选牌、按钮、落牌、开启、关闭、掷骰、成功、失败及反制；可在设置静音。
- 字体：[Google Fonts / Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，SIL Open Font License，许可见 `assets/fonts/OFL.txt`。
- 名称和主题参考 Steve Jackson Games 的 INWO。本项目是本地非官方简化改编；卡牌数值、能力和插画均不代表原版卡面。
