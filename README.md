## sunfil项目结构

```shell
├── math
│   └── SafeMath.sol
├── models
│   ├── actorInfo.sol
│   ├── stake.sol
│   └── vote.sol
├── utils
│   ├── data-convert.sol
│   └── FilAddress.sol
├── debtTokens.sol
├── interstRateFormula.sol
├── manageNode.sol
├── opNode.sol
├── rate.sol
└── stakingPool.sol
└── sunPond.sol
└── vote.sol
```

| 文件夹                       | 说明           | 描述                                    |
|---------------------------|--------------|---------------------------------------|
| `math`                    | 数学计算方法       | solidity通用安全数学计算方式                    |
| `models`                  | 数据存储结构       | 用于存储在合约内部结构                           |
| `--actorInfo.sol`         | 节点信息         | 加入sunfil池子的节点信息                       |
| `--stake.sol`             | 结构体合约        | 质押相关结构体                               |
| `--vote.sol`              | 投票信息         | 投票合约内部使用结构体                           |
| `utils`                   | 通用工具包        | 一些地址、类型转换方法                           |
| `--data-convert`          | 数据类型转换工具     | 字符串拼接,转换,日期等处理                        |
| `--FilAddress.sol`        | filecion地址处理 | f系列地址转ETH地址方法                         |
| `DebtTokens.sol`          | 借贷合约         | 用以记录opNode合约借贷、还款等信息，包括对应借贷信息查询       |
| `InterestRateFormula.sol` | 公式合约         | 用以计算缩放因子相关的方法                         |
| `manageNode.sol`          | 节点管理合约       | 节点加入sunfil池子、离职、修改操作人等操作，管理着所有加入池子节点信息 |
| `opNode.sol`              | 节点操作合约       | 进行借贷、还款、修改worker、control地址等操作         |
| `rate.sol`                | 利率合约         | 设置平台基础值、贷款、存款、负债、杠杆、年化等相关利率计算         |
| `StakingPool.sol`         | 质押合约         | 进行质押、解质押、质押信息查询等操作                    |
| `sunPond.sol`             | 池子主合约        | 管理所有资金、支付权限、所有节点的owner、受益人替换合约        |
| `vote.sol`                | 投票合约         | 获取投票提案、固化投票人及投票权重、参与投票等操作             |


### 合约关联关系
```shell
StakingPool.sol关联：
DebtTokens.sol，sunPond.sol，rate.sol

DebtTokens.sol关联:
sunPond.sol，rate.sol，StakingPool.sol

rate.sol关联：
DebtTokens.sol，manageNode.sol，sunPond.sol，StakingPool.sol

sunPond.sol关联：
地址支付权限：
GrantPayableAuthority: StakingPool.sol,opNode.sol,manageNode.sol
地址操作权限：
GrantOpAuthority: StakingPool.sol,opNode.sol,manageNode.sol

opNode.sol关联：
DebtTokens.sol，manageNode.sol，sunPond.sol，rate.sol

manageNode.sol关联：
DebtTokens.sol，sunPond.sol

vote.sol关联：
rate.sol，DebtTokens.sol，StakingPool.sol
```