# 文档索引

`swift-injection-peer` 的文档。面向使用者的说明在仓库根的
[README.md](../README.md) 与 [CHANGELOG.md](../CHANGELOG.md)，面向 coding agent 的速查表在
[AGENTS.md](../AGENTS.md)。

## 愿景

无独立愿景文档。本库的职责范围由它的来源决定：它是从 `swift-helper-service` 移出的通道层，
服务两类使用者 ——

- **自带 daemon 的应用**（RuntimeViewer、`InjectionScaffold` 生成的项目）：用 brokered XPC 路径，
  把 `InjectedEndpointRegistryService` 挂在自己的 daemon 上。
- **用共享注入平台的工具**（`ViewHierarchyCapture`、平台的参考载荷）：用 loopback socket 路径，
  不碰注册表。

这两条路**并行、不互相替代**。本库是它们的公共底座 —— 在此之前，同一套管道被 RuntimeViewer、
MediaRemoteWizard、HopperMCP 各自手写过一遍。

## 提案（Evolutions）

见 [Evolutions/README.md](Evolutions/README.md)。

本库成立本身的论证不在这里，而在 `swift-helper-service` 的提案
`Documentations/Evolutions/0004-daemon-only-injects.md`（共享 daemon 只管注入，回传通道移到
独立库）里 —— 那份提案决定了「搬出去、搬到哪、谁还挂注册表」。
本库自己的提案从 API 设计开始（例如要不要收拢 `PeerLink` 的两条入口、端口碰撞要不要做候选序列）。

## 实现说明

尚无。需要写的时候，候选主题是：

- **为什么共享 daemon 不中转回传，而专属 daemon 可以。** 关键在 `HelperServer` 的
  `codeSigningRequirement` 默认值，以及共享者与专属者处境的差异。这是代码本身看不出来、
  而下次维护会反复追问的决策。
- **两条传输为什么角色相反。** 沙盒强制的结果，不是设计偏好。
