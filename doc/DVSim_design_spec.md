# DVSim 设计报告

**版本**：v1.49.x
**定位**：面向 ASIC 项目的 EDA 工具流程编排系统（build & run system），用 Python 编写，以 Hjson 配置驱动，工具无关。

---

## 一、设计目标

DVSim 旨在用**单一标准化命令行接口**封装 EDA 工具流程的多个步骤（编译、运行、覆盖率、报告），解决以下痛点：

1. 多种 EDA 工具（VCS/Xcelium/Questa/Riviera/Verilator/Dsim/DC/Ascentlint…）命令差异大；
2. 单次回归涉及大量并行 build/run，需依赖管理与负载均衡；
3. 配置分散、可复用性差、难以追溯。

设计哲学：**配置驱动、工具无关、声明式优先、冲突显式报错而非静默覆盖**。

---

## 二、整体架构

DVSim 采用分层流水线设计，从上到下依次为：

```
CLI (cli/run.py)
  └─ FlowCfg (flow/base.py)  ── 配置加载/合并/展开/重载
       └─ Flow 子类 (sim/flow.py, flow/{formal,lint,syn,one_shot}.py)
            └─ 创建 Deploy 对象 (job/deploy.py: CompileSim/RunTest/CovReport…)
                 └─ Scheduler (scheduler/core.py)  ── asyncio DAG 调度
                      └─ Launcher (launcher/{local,lsf,slurm,nc}.py)  ── 作业分发
                           └─ Tool 插件 (tool/*.py)  ── EDA 工具命令组装
```

**支持流程**：`sim`（两阶段 build→run）、`formal`/`lint`/`syn`/`cdc`/`rdc`（单次构建 OneShotCfg）。工厂 `flow/factory.py` 依据 Hjson 的 `flow` 字段选择子类。

---

## 三、核心设计原则

### 3.1 配置驱动：Hjson + 通配符展开

- **配置格式**：Hjson（`utils/hjson.py:16-34` 解析），支持注释、引号省略，便于人工维护。
- **包含机制**：`import_cfgs` 与 `use_cfgs` 两种包含方式，由 `flow/hjson.py:14-52 load_hjson` 以 worklist + seen 集合广度加载，**自动防环**（`hjson.py:39-47`）。二者语义不同，详见下文。

#### 3.1.1 `import_cfgs` — 字段级叠加合并

**语义**：把指定文件的字段**合并到当前这一个配置对象**（同一个 `FlowCfg` 实例）。用于复用公共配置。

**使用规则**：

| 规则 | 说明 | 代码位置 |
|---|---|---|
| 语法 | `import_cfgs: ["path1", "path2", ...]`，值为字符串列表 | `hjson.py:75-82` |
| 加载顺序 | worklist 广度优先，按列表顺序依次加载导入文件 | `hjson.py:36-50` |
| 字段合并 | 走 `set_target_attribute`：list 拼接、标量按默认值取舍、冲突报错 | `hjson.py:104` |
| 路径通配符 | 导入路径支持 `{var}` 替换（如 `{proj_root}`） | `hjson.py:107-110` |
| 防环 | seen 集合记录已加载路径，重复出现即抛 `RuntimeError` | `hjson.py:39-47` |
| 出现位置 | 可在任意层级的文件中出现（顶层或被导入文件中均可再嵌套） | — |
| 去重 | 导入文件中的 `import_cfgs` 自身也会被递归展开 | `hjson.py:81` |

**举例**（参考 OpenTitan `uart_sim_cfg.hjson`）：

```hjson
// hw/ip/uart/dv/uart_sim_cfg.hjson
{
  name: uart
  tool: vcs
  reseed: 10
  build_opts: ["+define+UART_DBG"]

  // 叠加导入公共配置：common 的 build_opts 会与本文件的拼接，
  // common 的标量默认值会被本文件的非默认值覆盖
  import_cfgs: ["{proj_root}/hw/dv/tools/dvsim/common_sim_cfg.hjson",
                "{proj_root}/hw/dv/tools/dvsim/prj_common_sim_cfg.hjson"]

  tests: [{ name: uart_smoke, uvm_test_seq: uart_smoke_vseq }]
}
```

合并效果（假设 `common_sim_cfg.hjson` 中 `build_opts: ["+define+UVM"]`）：

```
最终 build_opts = ["+define+UART_DBG"]  (本文件)
               + ["+define+UVM"]        (common 导入，list 拼接)
               = ["+define+UART_DBG", "+define+UVM"]

最终 reseed = 10  (本文件非默认值胜出，common 若为默认值则被覆盖)
```

#### 3.1.2 `use_cfgs` — 配置级聚合（primary 配置）

**语义**：声明当前文件是一个 **primary 配置**，并列出若干**互相独立的子配置**。每个子配置各自构建独立的 `FlowCfg` 实例，字段互不合并；primary 仅在最后汇总它们的 deploy 对象统一调度。

**使用规则**：

| 规则 | 说明 | 代码位置 |
|---|---|---|
| 语法 | `use_cfgs: ["path1", {name:..., ...}, ...]`，支持文件路径**或内联 dict** | `base.py:152-153` |
| 标识 primary | 文件中含 `use_cfgs` 即判定为 primary 配置 | `base.py:147` |
| 独立性 | 每个子配置是独立 `FlowCfg`，字段不互相合并 | `base.py:149-153` |
| 仅限顶层 | 只能在**第一个被加载的（顶层）文件**中定义；被 `import_cfgs` 导入的文件若含 `use_cfgs` 会报错 | `hjson.py:91-101` |
| 子配置加载 | 通过 `_load_child_cfg` 加载，内联 dict 会转成临时 hjson 文件 | `base.py:152-153` |
| 选择性运行 | `--select-cfgs` 可过滤要运行的子配置 | `cli/run.py:401-411` |
| 汇总调度 | primary 汇总所有子配置的 deploy 列表统一交给调度器 | `base.py:149-150` |

**举例 1**：primary 配置聚合多个 IP 的仿真

```hjson
// hw/top_earlgrey/dv/primary_sim_cfg.hjson（primary 配置）
{
  name: top_earlgrey
  flow: sim

  // 每个子配置独立加载，各自有自己的 tool/tests/build_modes
  use_cfgs: ["{proj_root}/hw/ip/uart/dv/uart_sim_cfg.hjson",
             "{proj_root}/hw/ip/spi_host/dv/spi_host_sim_cfg.hjson",
             {name: aes_variant, tool: vcs, tests: [{name: aes_smoke}]}]
}
```

运行方式：

```bash
# 运行所有子配置
dvsim hw/top_earlgrey/dv/primary_sim_cfg.hjson -i smoke

# 仅运行 uart 子配置
dvsim hw/top_earlgrey/dv/primary_sim_cfg.hjson -i smoke --select-cfgs uart
```

**举例 2**：内联 dict 子配置（无需独立文件）

```hjson
{
  name: my_chip
  flow: sim
  use_cfgs: [
    {name: fast_test, tool: verilator, reseed: 1, tests: [{name: smoke}]}
  ]
}
```

#### 3.1.3 `import_cfgs` 与 `use_cfgs` 对比

| 维度 | `import_cfgs` | `use_cfgs` |
|---|---|---|
| 合并粒度 | 字段级（多文件 → 一个配置对象） | 配置级（多个独立配置 → primary 汇总） |
| 字段是否互相合并 | 是（list 拼接、标量取舍） | 否（各子配置独立） |
| 出现位置 | 任意层级文件 | 仅顶层（第一个）文件 |
| 典型用途 | 复用公共 build_opts/run_opts/模式定义 | 一次回归聚合多个 IP/变体的独立仿真 |
| 冲突处理 | 走 `set_target_attribute` 规则 | 各自独立，无字段冲突 |
| 选择性运行 | 不适用（已合并） | `--select-cfgs` 过滤 |
- **通配符替换**：`{var}` 形式在合并后统一展开（`flow/base.py:206-214 _expand` → `utils/wildcards.py find_and_substitute_wildcards`），primary 配置允许部分未展开。
- **命令行优先**：`tool` 等 `_CMDLINE_FIELDS`（`hjson.py:11`）字段若由命令行设定，则忽略 Hjson 中的同名值。

### 3.2 配置选型与合并原则（重点）

这是 DVSim 最核心、也最易误解的设计。一个选项可在**配置文件、import 链、mode、CLI** 多处赋值。DVSim 用**三条独立路径**处理，遵循统一规则：**列表拼接、标量"默认值让位非默认值"、冲突即报错**。

#### 路径 A：`import_cfgs` 顶层字段合并 —— `set_target_attribute`（`flow/hjson.py:113-190`）

处理被导入的多份 Hjson 中**同名顶层字段**。规则：

| 旧值 / 新值类型 | 处理方式 | 代码位置 |
|---|---|---|
| 旧值为 `None` | 直接写入新值 | `hjson.py:121-125` |
| 都是 `list` | **拼接** `target[key] += dict_val` | `hjson.py:138-140` |
| 都是标量且相等 | 跳过 | `hjson.py:166-167` |
| 标量，新值是默认值（`str:""`/`int:0,-1`/`bool:False`） | 跳过（默认值不覆盖） | `hjson.py:174-175` |
| 标量，旧值是默认值、新值非默认 | 新值覆盖旧值 | `hjson.py:179-181` |
| 标量，都非默认且不等 | **抛 RuntimeError（冲突）** | `hjson.py:183-190` |

> 设计原则：**默认值是"占位"，任何明确的非默认值都胜出；两个明确值冲突说明配置矛盾，必须人工介入，绝不静默取舍。**

#### 路径 B：同名 Mode 合并 —— `merge_mode`（`modes.py:52-149`）

`build_mode`/`run_mode`/`test`/`regression` 同名定义出现在多文件时，由 `create_modes`（`modes.py:151-222`）两遍处理：Pass1 合并同名、Pass2 递归展开 sub_modes。合并规则与路径 A 一致（list 追加、标量按默认值取舍、冲突 `log.error` 退出，见 `modes.py:128-137`）。sub_mode 通过 `en_build_modes`/`en_run_modes` 表达依赖，并做**循环依赖检测**（`modes.py:169-171`）。

#### 路径 C：显式重载 `overrides` —— `_do_override`（`flow/base.py:321-378`）

Hjson 中可声明 `overrides: [{name: ..., value: ...}, ...]` 列表，在通配符展开**之前**强制覆盖（`base.py:160-161`）。规则：

- 必须命中已存在属性，否则报错（`base.py:376-378`）；
- 类型必须兼容，否则报错（`base.py:368-375`）；
- 同一 key 重复 override 直接报错（`base.py:344-350`）；
- 覆盖过程用 `log.debug` 打印（`base.py:365`）。

#### 优先级总览

```
命令行参数 (--tool 等)  >  overrides (显式重载)  >  mode 合并 (路径B)  >  import_cfgs 字段合并 (路径A)
```

CLI `--tool` 最高；`overrides` 次之且最强制；其后是 mode 内合并；最后是 import 链的顶层字段。**所有冲突均显式报错，无隐式优先级。**

> ⚠️ **可观测性现状**：仅路径 C（overrides）通过 `log.debug` 打印选择过程；路径 A、B 正常合并是**静默**的，仅冲突时报错。调试配置合并需用 `--verbose=debug`（`cli/run.py:851-864, 937-938`）。

#### 3.2.1 示例：`reseed` 的多路径叠加处理

`reseed`（每个测试的重跑次数）是最典型的"多路径赋值"字段，它贯穿所有三条路径加命令行。下面用 `uart` 配置演示完整叠加过程。

**处理链路（优先级从低到高）**：

```
① sim_cfg.reseed (hjson 顶层 / import_cfgs 合并)     (hjson.py:113-190)
  ↓ test 字典的 reseed 写入 Test 对象，未设的用 sim_cfg 顶层值回填
② Test 构造 + 回填 (modes.py:23-42, test.py:80-93)
  ↓ 命令行无条件覆盖
③ --reseed N (命令行)                                (sim/flow.py:429-430)
  ↓ 最后按倍率放大
④ --reseed-multiplier X (命令行)                     (sim/flow.py:435-436)
```

**场景设定**：

- `common_sim_cfg.hjson`：未设 `reseed`（不存在该字段）
- `uart_sim_cfg.hjson`：
  ```hjson
  reseed: 10                      // 顶层默认（路径 A）
  import_cfgs: [".../common_sim_cfg.hjson"]
  tests: [
    { name: uart_smoke },                          // 未设 reseed
    { name: uart_fifo_reset, reseed: 200 }         // 显式设 200
  ]
  ```

**逐步演算**：

**步骤 1 — import_cfgs 合并顶层 reseed（对应链路 ①，路径 A，`set_target_attribute`）**
- `common` 无 reseed → 不影响
- `uart` 的 `reseed: 10` 写入 `sim_cfg.reseed = 10`
- ⚠️ 若 `common` 也设了 `reseed: 5`：两者都是非默认 int 且不等 → **冲突报错**（`hjson.py:183-190`）。因此公共 cfg 通常**不设** reseed，留给 IP cfg 决定。

**步骤 2 — 创建 Test 对象（对应链路 ②，`test.py:34-56`）**

`Mode.__init__` 遍历 test 字典的 keys，对存在的 key 调用 `setattr` 写入 Test 对象（`modes.py:32-42`）：

- `uart_smoke`：test 字典未设 reseed → 不写入
- `uart_fifo_reset`：test 字典有 `reseed: 200` → `test.reseed = 200`

**步骤 3 — sim_cfg 默认值回填（对应链路 ②，`test.py:77-93`）**
- `uart_smoke`：未设 reseed → 用 `sim_cfg.reseed=10` 回填 → `test.reseed = 10`
- `uart_fifo_reset`：已设 reseed=200 → **不回填**，保持 200

此时各 test 的 reseed：

| test | reseed | 来源 |
|---|---|---|
| uart_smoke | 10 | 顶层默认回填 |
| uart_fifo_reset | 200 | test 字典显式值 |

**步骤 4 — 命令行 `--reseed 5`（`sim/flow.py:429-430`）**

```python
if self.reseed_ovrd is not None:
    test.reseed = self.reseed_ovrd
```

- 无条件覆盖**所有** test：`uart_smoke → 5`，`uart_fifo_reset → 5`

**步骤 5 — 命令行 `--reseed-multiplier 3`（`sim/flow.py:435-436`）**

```python
scaled = round(test.reseed * self.reseed_multiplier)
test.reseed = max(1, scaled)
```

- 在步骤 3 的结果上按倍率放大（保底 1）：
  - `uart_smoke`: round(10×3) = 30
  - `uart_fifo_reset`: round(200×3) = 600

**最终结果汇总**（不同命令行组合）：

| 命令行 | uart_smoke | uart_fifo_reset | 说明 |
|---|---|---|---|
| （无） | 10 | 200 | 顶层默认 + test 显式（步骤 1-3） |
| `--reseed 5` | 5 | 5 | 命令行全覆盖（步骤 4） |
| `--reseed-multiplier 3` | 30 | 600 | 按比例放大，保持比例（步骤 5） |
| `--reseed 5 --reseed-multiplier 3` | 15 | 15 | 先覆盖为 5，再 ×3 |
| `--fixed-seed 123` | 1 | 1 | 隐含 `--reseed 1`（`cli/run.py:724`） |

**关键要点**：

- `reseed` 作为**标量**，在 import_cfgs 合并时遵循"默认值让位、冲突报错"规则（路径 A）——公共 cfg 通常不设 reseed 以避免冲突。
- **test 级显式值**优先于 **sim_cfg 顶层默认值**：`test.py:84` 仅在 test 未设 reseed 时才用 sim_cfg 值回填。
- `--reseed` 是**无条件覆盖**，会抹平所有 test 间的 reseed 差异。
- `--reseed-multiplier` 在最终值上**按比例放大**，保持 test 间运行数比例，常用于夜间回归加量。
- `--fixed-seed S` 隐含 `--reseed 1`（固定种子单次运行）。

### 3.3 工具无关性

- 仿真器/工具通过 `tool/` 下的插件适配（`get_sim_tool_plugin`），每个插件提供 `build_opts`/`run_opts` 组装、覆盖率指标解析、波形格式支持等。
- 配置中用 `tool: vcs` 选择，命令行 `--tool` 可覆盖；`{tool}.hjson` 提供工具级默认参数。
- `is_equivalent_job`（`sim/flow.py:493`）做 build 去重——不同 build_mode 若在当前开关下（如未开 coverage）等价则合并，节省算力。

### 3.4 模式抽象：build_modes / run_modes / tests / regressions

- **BuildMode**（`modes.py:258-290`）：编译期选项集合（`build_opts`/`pre_build_cmds`…），含 sub-mode 依赖。
- **RunMode**（`modes.py:293-326`）：运行期选项集合。
- **Test**：引用一个 `build_mode` + `run_mode`，可设 `reseed`。
- **Regression**：test 的分组，可叠加 `en_sim_modes`/`en_build_modes`。

CLI `--items` 支持 glob 匹配（`sim/flow.py:368-376`），同时匹配 regression 与 test。`_expand_run_list`（`sim/flow.py:443-466`）按 reseed 交错排列，**最大化早期覆盖**（A/B reseed 5/2 → ABABAAA）。

### 3.5 并行调度与资源管理

- **DAG 调度器**（`scheduler/core.py`）：基于 asyncio 事件驱动，构建有向无环图（Kahn 拓扑校验），就绪堆按 `weight > timeout > dependents` 排序。
- **六态状态机**：`S`(scheduled) → `Q`(queued) → `R`(running) → `P/F/K`(终态)。依赖传播按 `needs_all_dependencies_passing` 决定是否要求全部上游通过。
- **资源管理**（`scheduler/resources.py`）：`-R RESOURCE=COUNT` 限制并发资源，`--on-missing-resource` 控制未知资源策略。
- **优雅退出**：SIGINT/SIGTERM 批量 kill 运行作业、取消排队（`_handle_exit_signal`）。
- **后端**（`launcher/`）：`--local`/`--remote`、LSF/Slurm/NC，`--max-parallel` 限制本地并发。

### 3.6 测试计划驱动

- `testplan.py` 解析 Hjson 测试计划，将 testpoint → tests 映射，按 `stage` 聚合为 regression（`sim/flow.py:323-330`）。
- 运行后 `map_test_results`（`sim/flow.py:697-698`）把仿真结果回填到 testpoint，生成 stage 级通过率与覆盖率。
- 支持 `--map-full-testplan` 展示完整计划（含未执行项）。

### 3.7 可观测性

- **日志**：六级 `DEBUG<VERBOSE<INFO<WARNING<ERROR<CRITICAL`（`logging.py:18,25`），`--verbose`/`--verbose=debug`/`--log-level` 控制；`--log-file` 落盘。
- **状态打印**：`scheduler/status_printer.py` 实时刷新 S/Q/R/P/F/K 计数。
- **报告**：`sim/report.py gen_reports` 生成 JSON + HTML 仪表盘 + Markdown。
- **插桩**（`instrumentation/`）：`--instrument {all,meta,timing,compute}` 采集调度时序，生成 timeline 报告。
- **dry-run / fake**：`--dry-run`（`-n`）只打印命令不执行；`--fake` 用随机结果驱动（仿真 RunTest 随机 50% pass/fail，`sim/flow.py:866-907`），便于验证调度与报告链路。

### 3.8 可扩展性

- 新增 flow：继承 `FlowCfg`（仿真）或 `OneShotCfg`（单次构建），实现 `_create_deploy_objects`/`_purge`/`_print_list`/`gen_results`，在 factory 注册即可。
- 新增工具：在 `tool/` 添加插件并配 `{tool}.hjson`。
- 子类可通过覆写 `_merge_hjson`/`_expand`/`_post_init` 在标准流程的固定切点插入逻辑（`base.py:196-214`）。

---

## 四、功能与使用指南

### 4.1 基本调用

```bash
dvsim <cfg.hjson> [options]
# 例：
dvsim hw/ip/uart/dv/uart_sim_cfg.hjson -i smoke
```

### 4.2 配置文件编写

```hjson
{
  name: uart
  dut: uart
  tb: tb
  tool: vcs
  fusesoc_core: lowrisc:dv:uart_sim:0.1
  ral_spec: "{proj_root}/hw/ip/uart/data/uart.hjson"

  // 叠加导入公共配置（同名 list 字段会拼接，标量按默认值取舍）
  import_cfgs: ["{proj_root}/hw/dv/tools/dvsim/common_sim_cfg.hjson"]

  build_modes: [{ name: my_mode, build_opts: ["+define+FOO"] }]
  run_modes:   [{ name: my_rmode, run_opts: ["+bar=1"] }]
  tests:       [{ name: uart_smoke, uvm_test_seq: uart_smoke_vseq }]
  regressions: [{ name: smoke, tests: ["uart_smoke"] }]

  // 显式重载（强制覆盖，会在 --verbose=debug 打印）
  overrides: [{ name: reseed, value: 5 }]
}
```

#### 4.2.1 `ral_spec` — RAL 规范文件及其生成全过程

**作用**：指向寄存器抽象层（Register Abstraction Layer）的规范文件，用于在构建阶段自动生成 UVM RAL 模型（`ral_pkg.sv`）。

| 项 | 说明 |
|---|---|
| 类型 | 标量（字符串路径） |
| 定义位置 | `SimCfg`（`sim/flow.py:149`）、`OneShotCfg`（`flow/one_shot.py:75`） |
| 取值 | 指向描述寄存器布局的 hjson 文件，如 `{proj_root}/hw/ip/uart/data/uart.hjson` |
| 合并规则 | 走 `set_target_attribute` 标量规则：公共 cfg 通常不设（留空），由 IP cfg 显式指定 |

**完整生成链路**：

```
① IP sim_cfg.hjson 设 ral_spec
     │  ral_spec: "{proj_root}/hw/ip/uart/data/uart.hjson"
     ↓  dvsim 加载为 SimCfg 属性 + 通配符展开 {ral_spec}
② IP 的 FuseSoC core 文件声明 ralgen generator
     │  generate.ral.parameters.ip_hjson: data/uart.hjson
     ↓  FuseSoC 解析依赖树时遇到 generator
③ FuseSoC 调用 ralgen.py（tools/ralgen/ralgen.py）
     │  传入含 parameters 的 YAML 文件
     ↓  ralgen.py 解析 ip_hjson / top_hjson
④ 调用后端工具生成 RAL 包
     │  IP 级 → util/regtool.py -s -t <outdir> <ral_spec>
     │  芯片级 → util/topgen.py -r -o <outdir> -t <ral_spec> -s <seed>
     ↓  生成 ral_pkg.sv（SystemVerilog UVM RAL package）
⑤ ralgen.py 生成 FuseSoC core 文件
     │  添加 lowrisc:dv:dv_base_reg 依赖（确保编译顺序）
     ↓  RAL 包加入 filelist 依赖树
⑥ sim.mk 编译阶段集成
        gen_sv_flist → do_build（编译含 ral_pkg.sv 的 filelist）
```

**分步说明**：

**步骤 ① — 配置定义**

在 IP 的 sim_cfg.hjson 中设置 `ral_spec`，dvsim 将其加载为 `SimCfg` 属性并参与通配符展开：

```hjson
// hw/ip/uart/dv/uart_sim_cfg.hjson
ral_spec: "{proj_root}/hw/ip/uart/data/uart.hjson"
```

> `ral_spec` 在 dvsim Python 源码中仅作为配置属性存储（`sim/flow.py:149`），dvsim 本身**不直接解析或生成 RAL**——实际生成由 FuseSoC generator 机制驱动。

**步骤 ② — FuseSoC core 文件声明 generator**

IP 的 FuseSoC core 文件（如 `uart_sim.core`）声明对 `ralgen` generator 的依赖，并将寄存器 spec 路径作为参数传入：

```yaml
# hw/ip/uart/dv/uart_sim.core（示意）
generate:
  ral:
    generator: ralgen
    parameters:
      name: uart                              # RAL 包名（通常同 IP 名）
      ip_hjson: data/uart.hjson               # 相对于 core 文件的路径

targets:
  default:
    generate:
      - ral
```

`ralgen` generator 由 `tools/ralgen/ralgen.core` 注册（`ralgen.core:8-11`）。

**步骤 ③ — FuseSoC 调用 ralgen.py**

FuseSoC 在解析依赖树遇到 generator 时，将参数打包成 YAML 文件传给 `ralgen.py`（`tools/ralgen/ralgen.py`）。`ralgen.py` 从中提取（`ralgen.py:37-44`）：

| 参数 | 说明 | 必填 |
|---|---|---|
| `name` | RAL 包名 | 是 |
| `ip_hjson` | IP 级寄存器 spec 路径（reggen 输入） | 二选一 |
| `top_hjson` | 芯片级 spec 路径（topgen 输入） | 二选一 |
| `alias_hjson` | 寄存器别名 spec | 否 |
| `dv_base_names` | 自定义 RAL 基类名 | 否 |
| `hjson_path` | topgen 的 hjson 搜索路径 | 否 |

> `ip_hjson` 与 `top_hjson` 必须**恰好设一个**，否则报错（`ralgen.py:46-49`）。

**步骤 ④ — 调用后端工具生成 RAL 包**

`ralgen.py` 根据参数选择后端工具（`ralgen.py:52-72`）：

- **IP 级**（`ip_hjson` 设定）：调用 `util/regtool.py`
  ```
  regtool.py -s -t <outdir> <ral_spec> [--alias <alias_hjson>]
  ```
- **芯片级**（`top_hjson` 设定）：调用 `util/topgen.py`
  ```
  topgen.py -r -o <outdir> -t <ral_spec> -s <seed_path> [--hjson-path <path>]
  ```

两者均生成 SystemVerilog UVM RAL package（`ral_pkg.sv`），包含寄存器模型。

**步骤 ⑤ — 生成 FuseSoC core 文件**

`ralgen.py` 还生成一个 FuseSoC core 文件，将生成的 RAL 包纳入依赖树，并自动添加 `lowrisc:dv:dv_base_reg` 依赖（因为 DV 寄存器模型继承自 DV 库基类，确保编译顺序正确，见 `README.md:84-92`）。若设了 `dv_base_names`，则额外添加自定义基类依赖。

**步骤 ⑥ — 编译集成**

生成的 RAL 包通过 filelist 参与 `sim.mk` 的编译流程：

```
sim.mk: gen_sv_flist（生成 filelist）→ do_build（${build_cmd} ${build_opts} 编译）
```

至此，`ral_spec` 指向的寄存器描述最终变为仿真可用的 UVM RAL 模型。

**关键要点**：

- `ral_spec` 是**声明性配置**，dvsim 只存储与展开它，不直接处理。
- 实际生成由 **FuseSoC generator 机制**驱动：core 文件声明 → FuseSoC 调用 `ralgen.py` → `regtool.py`/`topgen.py` 生成。
- `ralgen.py` 是 `regtool`/`topgen` 的**包装器**（`README.md:70-72`），本身不实现 RAL 生成逻辑。
- IP 级用 `ip_hjson` + `regtool`；芯片级用 `top_hjson` + `topgen`。
- 若 DUT 无需 RAL 模型，可不设 `ral_spec`（默认空字符串），同时 core 文件不声明 generator。


#### 4.2.2 `build_modes` — 编译模式

**作用**：定义一组编译期（及关联的运行期）选项集合，可被 test 引用或通过命令行启用，实现"同一 RTL、不同编译开关"的复用。

**`BuildMode` 属性**（`modes.py:258-290`）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `name` | str | 模式名（必填，唯一） |
| `is_sim_mode` | int | 是否为 sim mode（`1` 时可被 regression 的 `en_sim_modes` 启用） |
| `en_build_modes` | list | 依赖的子 build_mode（递归合并） |
| `build_opts` | list | 编译选项（如 `+define+FOO`） |
| `post_build_opts` | list | 编译后处理选项 |
| `pre_build_cmds` / `post_build_cmds` | list | 编译前/后 shell 命令 |
| `pre_run_cmds` / `post_run_cmds` | list | 运行前/后 shell 命令 |
| `run_opts` | list | 运行选项 |
| `sw_images` / `sw_build_opts` | list | 软件镜像及构建选项 |
| `build_timeout_mins` | int | 编译超时（分钟） |

**使用规则**：

- **同名合并**：多文件中同名 build_mode 通过 `merge_mode` 合并（list 追加、标量按默认值取舍，`modes.py:52-149`）。
- **子模式依赖**：`en_build_modes` 声明依赖的子模式，递归展开并做循环依赖检测（`modes.py:160-191`）。
- **test 引用**：test 通过 `build_mode: <name>` 字段引用一个 build_mode（`test.py:97`）。
- **CLI 启用**：`--build-modes (-bm) my_mode` 将该模式的选项应用到所有 build/run 目标（`sim/flow.py:286-303`）。
- **build 去重**：若不同 build_mode 在当前开关下等价（如未开 coverage），`is_equivalent_job` 会合并以节省算力（`sim/flow.py:491-506`）。

**示例**：

```hjson
build_modes: [
  { name: default,
    build_opts: ["+define+UVM"] },

  // 一个开启覆盖率的模式，依赖 default
  { name: cov,
    is_sim_mode: 1,
    en_build_modes: ["default"],
    build_opts: ["+define+COVERAGE"],
    run_opts: ["+cm_seq+no"] },

  // 子模式依赖示例
  { name: gate_level,
    en_build_modes: ["cov"],          // 递归继承 cov 的选项
    build_opts: ["+define+GATE_SIM"] }
]
```

运行：`dvsim <cfg> -bm cov` 或在 test 中 `build_mode: cov`。

#### 4.2.3 `run_modes` — 运行模式

**作用**：定义一组运行期选项集合，可被 test 通过 `en_run_modes` 引用，或通过命令行启用。

**`RunMode` 属性**（`modes.py:293-326`）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `name` | str | 模式名（必填，唯一） |
| `reseed` | int | 重跑次数 |
| `en_run_modes` | list | 依赖的子 run_mode |
| `run_opts` | list | 运行选项（如 `+bar=1`） |
| `uvm_test` / `uvm_test_seq` | str | UVM 测试类 / 序列类 |
| `build_mode` | str | 关联的 build_mode |
| `pre_run_cmds` / `post_run_cmds` | list | 运行前/后 shell 命令 |
| `run_timeout_mins` / `run_timeout_multiplier` | int/float | 运行超时及倍率 |
| `sw_images` / `sw_build_device` / `sw_build_opts` | list/str | 软件镜像相关 |

**使用规则**：

- **同名合并**：与 build_mode 相同的 `merge_mode` 规则。
- **test 引用**：test 通过 `en_run_modes: ["my_rmode"]` 引用，run_mode 的属性合并到 test（`test.py:74-75`）。
- **CLI 启用**：`--run-modes (-rm) my_rmode` 将该模式选项应用到每次仿真运行（`sim/flow.py:306-316`）。
- **与 build_mode 区别**：run_mode 不产生新的编译产物，仅影响运行参数；同一 build 可叠加不同 run_mode。

**示例**：

```hjson
run_modes: [
  { name: fast_mode,
    run_opts: ["+zero_delays=1"] },

  { name: long_xfer,
    en_run_modes: ["fast_mode"],     // 继承 fast_mode 的 run_opts
    run_opts: ["+xfer_len=4096"],
    run_timeout_mins: 60 }
]

tests: [
  { name: uart_long_xfer_wo_dly,
    uvm_test_seq: uart_long_xfer_wo_dly_vseq,
    en_run_modes: ["long_xfer"] }    // 引用 run_mode
]
```

运行：`dvsim <cfg> -rm fast_mode` 或 test 中 `en_run_modes: ["fast_mode"]`。

#### 4.2.4 `regressions` — 回归集

**作用**：将若干 test 分组为一组回归，可叠加 build_opts/run_opts/sim_modes，并覆盖 reseed，实现"一次命令运行一批测试"。

**`Regression` 属性**（`regression.py:18-42`）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `name` | str | 回归名（必填，不能与 test 同名，`regression.py:57-63`） |
| `tests` | list/None | `None`=所有 test；`[]`=无；`["t1","t2"]`=指定 test（`regression.py:21-28`） |
| `reseed` | int | 覆盖所含 test 的 reseed（`regression.py:178-179`） |
| `en_sim_modes` | list | 启用的 sim_mode（须 `is_sim_mode=1`，`regression.py:83-90`） |
| `en_run_modes` | list | 启用的 run_mode |
| `build_opts` / `post_build_opts` | list | 追加到所含 test 的 build_mode |
| `run_opts` | list | 追加到所含 test 的运行选项 |
| `pre/post_build_cmds` / `pre/post_run_cmds` | list | 前后置命令 |

**使用规则**：

- **tests 的三种取值**：
  - `None`（不设 `tests` 字段）→ 运行**所有** test（`regression.py:138-144`）
  - `[]`（空列表）→ 无 test
  - `["t1", "t2"]` → 仅运行指定 test
- **选项合并**：`merge_regression_opts`（`regression.py:164-179`）将 regression 的 build_opts 合并到所含 test 的 build_mode，run_opts 合并到 test；同一 build_mode 只合并一次。
- **reseed 覆盖**：若 regression 设了 `reseed`，覆盖所含所有 test 的 reseed。
- **sim_mode 约束**：`en_sim_modes` 只能引用 `is_sim_mode: 1` 的 build_mode（`regression.py:84-90`）。
- **CLI 引用**：`-i <regression_name>` 运行该回归（默认 `-i smoke`）。

**示例**：

```hjson
regressions: [
  // smoke 回归：运行所有 test，各 1 次，加 +smoke_test=1
  { name: smoke,
    tests: [],                       // 空列表（common 中约定为"运行所有"）
    reseed: 1,
    run_opts: ["+smoke_test=1"] },

  // nightly 回归：运行所有 test，启用覆盖率 sim_mode
  { name: nightly,
    en_sim_modes: ["cov"] },         // cov 须是 is_sim_mode:1 的 build_mode

  // 自定义回归：指定 test 集，覆盖 reseed
  { name: my_regr,
    tests: ["uart_smoke", "uart_intr"],
    reseed: 20,
    run_opts: ["+test_timeout_ns=3000000000"] }
]
```

运行：

```bash
dvsim <cfg> -i smoke          # 运行 smoke 回归
dvsim <cfg> -i nightly        # 运行 nightly 回归（含覆盖率）
dvsim <cfg> -i my_regr        # 运行自定义回归
dvsim <cfg> -i all            # common 默认提供 all 回归（运行所有 test）
```

**四者协作关系**：

```
build_modes ──定义编译开关──┐
                           ├─→ test 引用 build_mode + en_run_modes
run_modes ──定义运行开关──┘        │
                                   │
regressions ──分组 test + 叠加选项──┘──→ CLI: -i <regression>
```



### 4.3 常用选项分组

| 分组 | 关键选项 | 说明 |
|---|---|---|
| 选择运行项 | `-i ITEMS`, `--select-cfgs` | glob 匹配 test/regression；默认 `smoke` |
| 列举 | `-l [build_modes run_modes tests regressions]` | 解析后列举可运行项并退出 |
| 工具 | `-t vcs/xcelium/...` | 覆盖 `tool`（最高优先级） |
| 调度 | `--local/--remote`, `-mp N`, `-R A=COUNT` | 本地/远程、最大并行、资源限额 |
| 构建 | `--build-only`, `--build-unique`, `--build-seed` | 仅编译、目录加时间戳、固定编译种子 |
| 种子 | `--reseed N`, `--reseed-multiplier X` | 覆盖重跑次数、按比例放大 |
| 波形 | `-w {fsdb,shm,vpd,vcd,...}`, `-mw N` | 波形格式、仅前 N 个 |
| 覆盖率 | `--cov`, `--cov-merge-previous`, `--cov-unr`, `--cov-analyze` | 收集/合并/UNR/分析 |
| 调试 | `--gui`, `--gui-debug`, `--interactive` | GUI/断点/交互模式 |
| 可观测 | `--verbose[=debug]`, `--log-level DEBUG`, `--log-file`, `--instrument` | 日志级别、落盘、插桩 |
| 验证链路 | `--dry-run`(`-n`), `--fake` | 不实跑 / 随机结果 |
| 文件 | `-sr`, `-pr`, `-br`, `--purge`, `-mo N` | scratch/proj root/分支/清理/保留目录数 |

### 4.4 配置选型调试技巧

1. **列举可运行项**：`dvsim <cfg> -l tests build_modes run_modes` —— 验证 mode/test 是否被正确创建与合并。
2. **观察 overrides 重载**：`dvsim <cfg> --verbose=debug -n` —— 可见 `Overriding "x" value "old" with "new"`。
3. **冲突定位**：标量冲突会抛 `RuntimeError` 并指明文件路径与新旧值（`hjson.py:184-190`），据此定位是哪两份 Hjson 矛盾。
4. **验证调度与报告**：`dvsim <cfg> --fake` —— 不依赖 EDA 工具即可跑通调度→结果→报告全链路。

### 4.5 冲突处理约定（重要）

- **list 字段**（如 `build_opts`/`run_opts`）：总是拼接，不会冲突。
- **标量字段**：若两处都给了非默认值且不等 → **报错退出**，而非后者覆盖前者。这是有意的安全设计，避免配置被意外覆盖。
- 想强制覆盖某标量：使用 `overrides`（路径 C），它优先于路径 A/B 且会留 debug 日志。

---

## 五、设计取舍小结

| 设计决策 | 取舍 |
|---|---|
| 列表拼接而非覆盖 | 便于跨文件累加选项；代价是难"清空"已有列表（需用 overrides） |
| 标量冲突即报错 | 防止静默覆盖导致难调试；代价是配置者需显式用 overrides 表达意图 |
| 默认值让位非默认值 | 允许公共 cfg 设默认、子 cfg 覆盖，无需每次写 overrides |
| import 防环 + worklist | 安全加载任意深度包含；路径重复即报错 |
| asyncio DAG 调度 | 单进程高并发、依赖感知；UI 即状态打印通过回调解耦 |
| build 去重 | 节省编译资源，但依赖 `is_equivalent_job` 正确性 |
| dry-run/fake | 环境无关地验证配置与链路；但 dry-run 不校验文件路径等运行期问题 |

---

## 附录 A：DVSim 命令行选项完整清单

> 以下选项均定义于 `cli/run.py:343-874`，按 argparse 分组顺序列出。调用形式：`dvsim <cfg.hjson> [options]`。

### A.1 顶层参数（全局）

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `<cfg>` | — | 位置参数 | — | 配置 hjson 文件（必填） |
| `--version` | — | — | — | 显示 dvsim 版本并退出 |
| `--tool` | `-t` | `TOOL` | 配置文件值 | 显式设置工具；仿真可选，其他流程必填。可选：vcs, questa, xcelium, ascentlint, verixcdc, mrdc, veriblelint, verilator, dc |
| `--list` | `-l` | `[CAT ...]` | — | 解析配置后列举可运行项并退出；可按类别过滤：build_modes, run_modes, tests, regressions |
| `--log-level` | — | 枚举 | INFO | 日志级别：DEBUG, VERBOSE, INFO, WARNING, ERROR, CRITICAL |
| `--log-file` | — | `PATH` | — | 将日志写入指定文件（同时仍输出到 stderr） |

### A.2 Choosing what to run — 选择运行项

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--items` | `-i` | `[ITEMS ...]` | `["smoke"]` | 指定要运行的 regression 或 test（支持 glob），空格分隔 |
| `--select-cfgs` | — | `[CFG ...]` | — | primary 配置下仅运行指定的子配置 |

### A.3 Dispatch options — 调度分发

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--job-prefix` | — | `PFX` | `""` | 运行每个工具命令时前置的字符串 |
| `--local` | — | — | false | 强制作业在本地机器分发 |
| `--remote` | — | — | false | 触发将仓库拷贝到 scratch 区 |
| `--max-parallel` | `-mp` | `N` | 16 或 `$DVSIM_MAX_PARALLEL` | 本地最大并行 build/test 数 |
| `--gui` | — | — | false | 以 GUI 模式运行（非批处理） |
| `--gui-debug` | `-gd` | — | false | GUI 模式并启用断点/实时值/事务录制（仅 Xcelium，性能影响大） |
| `--interactive` | — | — | false | 非 GUI 交互模式，透明显示工具输出；隐含 `--reseed 1` |

### A.4 Resource management — 资源管理

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--resource` | `-R` | `RESOURCE=COUNT` | — | 设置资源并发上限（可重复），如 `-R A=30` 或 `-R B=unlimited` |
| `--on-missing-resource` | — | 枚举 | ignore | 作业请求未定义限额的资源时的行为：ignore, warn, error, fatal |

### A.5 File management — 文件管理

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--scratch-root` | `-sr` | `PATH` | `$SCRATCH_ROOT` 或 `./scratch` | build/run 目录根路径 |
| `--proj-root` | `-pr` | `PATH` | git 仓库根 | 项目根目录 |
| `--branch` | `-br` | `B` | 当前 git 分支 | scratch 路径下的分支子目录名 |
| `--max-odirs` | `-mo` | `N` | 5 | 旧运行结果备份时保留的最大目录数 |
| `--purge` | — | — | false | 运行前清理 scratch 目录 |

### A.6 Options for building — 构建

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--build-only` | `-bu` | — | false | 仅构建可执行文件后停止 |
| `--build-unique` | — | — | false | 构建目录追加时间戳，避免与正在运行的测试冲突 |
| `--build-opts` | `-bo` | `OPT ...` | `[]` | 每次构建工具运行时附加的命令行选项 |
| `--build-modes` | `-bm` | `MODE ...` | `[]` | 启用的 build_mode 列表，其选项应用到所有 build/run 目标 |
| `--build-timeout-mins` | — | `MINUTES` | — | 构建 wall-clock 超时（分钟），超时则 kill；GUI 模式下禁用 |

### A.7 Options for running — 运行

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--run-only` | `-ru` | — | false | 跳过构建（假定仿真可执行文件已构建） |
| `--run-opts` | `-ro` | `OPT ...` | `[]` | 每次测试运行时附加的命令行选项 |
| `--run-modes` | `-rm` | `MODE ...` | `[]` | 启用的 run_mode 列表，其选项应用到每次仿真运行 |
| `--profile` | `-p` | `[P]` | — | 开启仿真性能分析（`time` 或 `mem`，不带参数时为 `time`） |
| `--xprop-off` | — | — | false | 关闭仿真中的 X 传播 |
| `--run-timeout-mins` | — | `MINUTES` | — | 运行 wall-clock 超时（分钟）；GUI 模式下禁用 |
| `--run-timeout-multiplier` | — | `MULTIPLIER` | — | 运行超时倍率（浮点），常用于门级/代工测试统一放大超时 |
| `--verbosity` | `-v` | `V` | 配置文件值 | 仿真详细度：n(none)/l(low)/m(medium)/h(high)/f(full)/d(debug) |

### A.8 Build / test seeds — 种子

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--build-seed` | — | `[S]` | — | 随机化构建；带参数用指定种子，否则随机取 256-bit 整数 |
| `--seeds` | `-s` | `S ...` | `[]` | 按顺序指定各运行项的测试种子 |
| `--fixed-seed` | `-fs` | `S` | — | 所有运行项使用同一种子 S；隐含 `--reseed 1` |
| `--reseed` | `-r` | `N` | — | 覆盖测试配置中的 reseed 值，每个测试以新种子运行 N 次 |
| `--reseed-multiplier` | `-rx` | `N` | 1 | 按比例 N 放大各测试的 reseed 值，保持测试间运行数比例 |

### A.9 Dumping waves — 波形

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--waves` | `-w` | `FORMAT` | — | 启用波形转储，格式：fsdb, shm, vpd, vcd, evcd, fst |
| `--max-waves` | `-mw` | `N` | 5 | 仅为前 N 个测试转储波形（含自动重跑的） |
| `--dump-script` | `-ds` | `DUMP_SCRIPT` | `{proj_root}/hw/dv/tools/sim.tcl` | 自定义 dump 脚本（须位于 `{proj_root}` 下） |

### A.10 Generating simulation coverage — 覆盖率

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--cov` | `-c` | — | false | 启用覆盖率数据收集 |
| `--cov-merge-previous` | — | — | false | （需配合 `--cov`）将历史覆盖率数据库与新数据库合并 |
| `--cov-unr` | — | — | false | 运行覆盖率 UNR（不可达）分析并生成报告（仅 VCS） |
| `--cov-analyze` | — | — | false | 不构建/运行，直接分析上次运行的覆盖率 |

### A.11 Generating results — 结果

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--map-full-testplan` | — | — | false | 在最终结果中展示完整测试计划（含未执行项）的标注 |

### A.12 Controlling DVSim itself — DVSim 自身控制

| 选项 | 短选项 | 参数 | 默认值 | 说明 |
|---|---|---|---|---|
| `--instrument` | — | `TYPE ...` | `[]` | 启用调度器插桩，可选：all, meta, timing, compute（可多选） |
| `--print-interval` | `-pi` | `N` | 10 | 每 N 秒打印一次状态；0 表示每次作业状态变化即打印 |
| `--verbose` | — | `[D]` | — | 不带参数打印 verbose 消息；`--verbose=debug` 消息量更大 |
| `--dry-run` | `-n` | — | false | 仅打印 dvsim 工具消息，不实际运行任何命令 |
| `--fake` | — | — | false | 使用 fake launcher 生成随机结果 |

### A.13 互斥与冲突约束

以下组合会在运行前被拒绝（`cli/run.py:878` 起）：

- `--interactive` 与 `--remote` 不可同时使用。

