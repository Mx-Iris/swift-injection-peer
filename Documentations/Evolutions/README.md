# Evolution 提案

本库的变更提案。每份提案一个文件，从调研到落地在同一份里原地更新。

## 状态总表

| # | 标题 | 状态 |
|---|------|------|
| — | 尚无本库自己的提案 | — |

## 本库的成立不在这里

「为什么要有这个库、从哪里搬出来、谁还挂注册表」的论证在 `swift-helper-service` 的提案
**共享 daemon 只管注入，回传通道移到独立库** 里。那份提案决定了搬家本身；本库的提案从 API 设计
开始。

已知的候选题目：

- **`PeerLink` 的两条入口要不要收拢。** 现在 `host(...)` 与 `hostReconnecting(...)` 分开，而重连
  只在 XPC 路径成立，socket 路径上抛 `reconnectionNeedsXPC`。
- **端口碰撞要不要做候选序列。** 现在推导出的端口撞上就失败（监听方报错，不静默换端口，因为对端
  无从跟随）。曾在共享 daemon 那份提案的澄清提问里定过「推导候选序列依次尝试」，随后随范围收窄
  移出，结论是「这归通道的实现者」—— 也就是本库。
- **XPC 握手有没有测试的办法。** 现在 `HelperPeerTests` 只覆盖 socket 那半边，XPC 握手需要两个
  进程，一个都没有测。

## 状态机

`Draft` → `In Review` → `Accepted` → `In Progress` → `Implemented`，另有 `Rejected` /
`Deferred` / `Withdrawn`。

落地时才分配编号：提案合进集成分支时取下一个序号，在此之前文件名用 `draft-<slug>.md`。
