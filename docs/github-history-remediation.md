# GitHub 历史补救

在新提交里删除文件，并不会把它从已有 Git 历史中移除。只要旧提交仍可访问，别人仍可能恢复之前的内容。即使重写历史，已有 clone、fork、pull request ref、缓存或下载副本也可能继续存在。

## 先判断严重程度

低风险示例：

- Xcode 用户状态路径里的本机用户名。
- Apple Developer Team ID。
- Bundle identifier。
- 非密钥类项目元数据。

这些内容通常值得后续清理，但一般不需要按泄密事故处理。

高风险示例：

- 私钥。
- 证书或 provisioning profile。
- App Store Connect API key。
- 密码、token、session cookie 或 personal access token。
- 私有用户数据或剪贴板内容。

如果提交过高风险内容，应默认它已经暴露。

## 如果真的提交了密钥

1. 立刻吊销或轮换该密钥。
2. 从当前工作区移除文件或敏感值。
3. 使用 `git filter-repo` 或 BFG 重写 Git 历史。
4. Force push 清洗后的分支和 tag。
5. 要求协作者重新 clone，或谨慎 rebase 到清洗后的历史。
6. 检查 GitHub pull request、fork、release、Actions log、issue 附件中是否还有副本。
7. 如果 GitHub 托管缓存视图中仍显示敏感数据，联系 GitHub Support。

历史重写能降低主仓库暴露面，但不能保证互联网上所有副本都会消失。

## 如果只是项目元数据

对于 Team ID、bundle id、Xcode 用户状态路径这类元数据，通常处理方式是：

1. 停止继续提交这些数据。
2. 增加 ignore 规则和本地配置文件。
3. 从当前文件树中移除生成的用户状态。
4. 只有在仓库还很新，或这些元数据不可接受时，才重写历史。

## TypeCarrier 当前策略

TypeCarrier 将个人签名配置放在 `Configs/Signing.local.xcconfig`，该文件被 Git 忽略。公开默认值放在 `Configs/TypeCarrier.xcconfig`，使用占位 bundle id。
