# agent-constraints

给 coding agent 设置和治理约束的 Agent Skill。

**它解决的不是「AGENTS.md 怎么写」，而是「这条约束该用什么机制来实现」。**

真实场景里人遇到的是「agent 老是用 pip 装依赖」或者「它又把 `legacy/` 当死代码删了」，默认反应是往 CLAUDE.md 加一行。这个技能拦住这个默认反应，把问题走一遍分层判断——多数时候正确答案是 hook 或权限规则，不是加一行文字。

## 核心认识

无配置文件时，一条明确写出的指令执行率是 **0%**；有文件时 **67.7%**。文件极其有效。

但同一批研究显示它**不可靠地改善任务成功率**，而推理成本上升 20%–23% 是稳定的。在单一研究内部，指令合规率与任务完成质量的相关性在控制任务类型后不可检出。

> **你写下的每一条都会被真的执行——而执行不等于有帮助。**

## 四层模型

每条规则放在**能承载它的最低层**。

| 层 | 机制 | 性质 |
|---|---|---|
| **1 执行层** | 执行门：hooks、`permissions.deny`、CI required check、pre-commit；检查器：linter、formatter、类型系统、测试 | 执行门确定性；检查器须接入执行门 |
| **2 常驻层** | AGENTS.md / CLAUDE.md | 每会话付费；单次应用命中 45%–84%，主要看任务类型 |
| **3 按需层** | Skill、path-scoped rule | 只在相关时进上下文 |
| **4 会话层** | prompt、plan mode、SPEC.md、`/goal` | 一次性 |

**检查器不是执行门。** linter、类型系统、测试单独躺在仓库里对 agent 是零约束力——只有接进 CI required check、pre-commit、`PostToolUse` 或 `Stop` hook，才算第 1 层。

能被第 1 层强制的，绝不放第 2 层——第 2 层会系统性失守：需要反复应用的规则，约 65% 的运行至少违反一次，首次失守通常在第 4 次应用附近。

## 安装

```sh
npx skills add SnowsonZ/agent-constraints --skill agent-constraints
```

或手动：

```sh
git clone https://github.com/SnowsonZ/agent-constraints
mkdir -p ~/.claude/skills && cp -r agent-constraints/skills/agent-constraints ~/.claude/skills/
```

装好后 `/agent-constraints` 调用，或直接描述问题——「我的 CLAUDE.md 太长了」「怎么禁止它动 migrations 目录」会自动触发。

## 五个工作流

| | 场景 | 做什么 |
|---|---|---|
| **A** | 从零配约束 | 先建第 1 层，再复制模板**先删后填** |
| **B** | agent 犯了错 | 单条规则走六步定层流程。触发条件是**第二次**犯同一个错 |
| **C** | 配置乱了 | 读全套配置逐条**重新定层**，输出建议，等确认再改 |
| **D** | 委派编写 | 开子 agent 写产物，强制要求验证并带回证据 |
| **E** | 定期复盘 | 读会话日志找重复出现的问题，只挑出现两次以上的 |

## 内容

```
skills/agent-constraints/
├── SKILL.md                 决策流程 + 四层落地要点（调用时加载）
├── LAYER1-ENFORCEMENT.md    hooks 与权限规则的实际写法
├── LAYER2-INSTRUCTIONS.md   AGENTS.md 写作规范、修剪判定表、反模式
├── LAYER3-ONDEMAND.md       Skill 与 path-scoped rule
├── EVIDENCE.md              支撑数字，自包含
├── templates/               AGENTS.md + CLAUDE.md 模板
└── hooks/                   SessionEnd 记录脚本
```

常规使用只加载 SKILL.md，其余按需展开。

## 维护

```sh
sh tests/run.sh
```

契约测试锁住四件会静默漂移的事：hook 的日志格式与权限、`LAYER1-ENFORCEMENT.md` 里 Stop hook 的 JSON 示例可解析、四层表的「机制」列在三份文件里一致、`evals/evals.json` 符合 skill-creator 的 schema。

它接在 push / PR 和发布流水线的第一步。**还差一步只能手工做**：在仓库 Settings → Branch protection 里把 `contracts` 设为 required check，否则它只是会报红的检查器，不是拦得住合并的执行门——这个技能自己的第 1 层定义就是这么划的。

## 证据基础

- [Evaluating AGENTS.md (arXiv:2602.11988)](https://arxiv.org/abs/2602.11988) — Gloaguen 等，ETH Zurich / LogicStar.ai
- [Instruction Adherence in Coding Agent Configuration Files (arXiv:2605.10039)](https://arxiv.org/abs/2605.10039) — McMillan
- [Agent READMEs (arXiv:2511.12884)](https://arxiv.org/abs/2511.12884) — Chatlatanagulchai 等

全部数字从论文 PDF 原文提取，未采用二手转述。

**已知边界**：两篇实验论文为 arXiv 预印本，未见同行评审。数据覆盖 Python 与 TypeScript，对 Go、Rust、Java 无证据。第 1 层的 hooks 与权限语法是 Claude Code 专有的。**任务类型对合规率的影响达 39 个百分点、模型 12.8、代码库 11.0，都大于文件怎么写——结论不可直接移植，要在你自己的环境实测。**

## License

MIT
