# SOP：papertok-reader 按 commit 自动发布（iOS TestFlight + Android GitHub Release）

> 目标：把“给一个 commit → 自动构建 → 自动上传/发布 → 可验证”的流程做成**可重复、可观测、可回滚**的发布流水线。
>
> 本 SOP 以 `papertok-reader` 为唯一目标（不包含 anx-reader）。

---

## 0. 术语与约束

- **ASC**：App Store Connect
- **TF**：TestFlight
- **match repo**：用于存放加密的证书/描述文件的仓库（本项目为 `ViffyGwaanl/papertok-reader-match`）
- **核心约束**
  - TestFlight 的 **build number 必须单调递增**（即使 ASC processing/展示有延迟）
  - ASC **外部测试（External Testing）同一时间只能有一个 build 在外审**
  - 本机/隔离浏览器可能需要你输入 Apple ID/2FA（不要在聊天里传密码）

---

## 1. DoD（完成标准）

对指定 commit：

### iOS
- [ ] 生成 IPA（Release）
- [ ] 上传到 ASC（看到 `Successfully uploaded the new binary...` 或等价日志）
- [ ] ASC 处理完成（processing = done/available）
- [ ] 分发给 internal testers（`Successfully distributed build to Internal testers`）

### Android
- [ ] 生成 `app-release.apk` + `app-release.aab`
- [ ] 生成 `CHECKSUMS.txt`（sha256）
- [ ] 发布 GitHub Release（tag：`android-v<version>-<versionCode>`，附件三件套）

### 外部测试（可选）
- [ ] 将外部组 `EX External` 切换到目标 build
- [ ] 自动撤掉上一条外审中的 build（保证 ASC 规则）
- [ ] 提交 Beta App Review

---

## 2. 发布输入/输出约定

### 输入
- commit SHA（短/长均可）

### 输出（落盘）
- Android artifacts：
  - `/Users/gwaanl/.openclaw/workspace/artifacts/papertok-reader/android/<shortsha>-<build>/`
- iOS 过程日志（建议）：
  - `/tmp/tf_<commit>_<timestamp>.log`（或执行命令输出重定向）

### 关键状态文件
- iOS build number 单调递增本地计数器：
  - `/Users/gwaanl/.openclaw/workspace/state/papertok-reader/last_testflight_build_number.txt`

> 说明：该文件的意义是**“即使 ASC 还没显示最新 build，也不重用 build number”**。

---

## 3. 依赖与环境

### 必备
- Xcode（可 archive）
- Flutter（可 `flutter build ipa` / `flutter build appbundle`）
- CocoaPods
- Ruby + bundler

### Secrets（均应 gitignore）
- `ios/fastlane/.env`
  - ASC API Key（`ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8_BASE64`）
  - match 密码（`MATCH_PASSWORD`）
  - match 基础认证（`MATCH_GIT_BASIC_AUTHORIZATION`，为 base64 payload，不含 `Basic ` 前缀）

---

## 4. 关键工程化设计（为什么这样做）

### 4.1 build number 单调递增（防 ASC processing 延迟）
**问题**：ASC 刚上传的 build 可能一段时间内 API/UI 都查不到，导致下一次“读取 ASC 最新 build+1”会撞号。

**策略**：
- 取 `next = max(ASC_latest, local_latest) + 1`
- 将 `next` 写回本地 state file

### 4.2 签名路径必须确定（避免 Xcode 自动签名/Development 证书问题）
**问题**：Xcode Automatic Signing 可能触发：
- `No Accounts`
- `iOS Team Provisioning Profile ... Apple Development ...`
- Development 证书上限

**策略**：
- TestFlight 统一走 **match AppStore profiles + Apple Distribution**（手动签名）
- 避免生成/依赖 Development 证书

### 4.3 match repo 分支一致性（防“空资产仓库放大问题”）
**问题**：若 default branch 与 assets branch 不一致，某些 clone/mirror 会拿到“只有 README”的空仓库，match 会走到“生成新证书”的分支。

**策略**：
- `papertok-reader-match` 的 signing assets 必须存在于 default branch（推荐 `main`）
- `ios/fastlane/Matchfile` 显式 `git_branch("main")`

### 4.4 上传与 processing/distribute 解耦（可重试、可恢复）
**问题**：
- altool 上传可能卡死
- Spaceship 等待 processing 的 API 结构可能变化

**策略**：
- 上传：先把“上传成功”做成事实（允许跳过等待）
- 等待/分发：作为第二阶段独立执行，可重复运行

---

## 5. iOS：从 commit → TestFlight

### 5.1 一键命令
在 repo 根目录：

```bash
cd /Users/gwaanl/.openclaw/workspace/repos/papertok-reader
./scripts/tf_from_commit.sh <COMMIT_SHA>
```

脚本应完成：
1) 创建临时 worktree（干净环境）
2) overlay fastlane/export options（确保与主仓库一致）
3) bundler 使用稳定缓存目录（减少每次重装 gems）
4) match 同步 App Store 证书/Profiles
5) `flutter build ipa --build-number=<next>`
6) 上传 ASC
7) 分发 internal testers（或由二阶段处理）

### 5.2 验证（强制执行）
**上传验证**（任一满足即可）：
- fastlane 输出包含：`Successfully uploaded the new binary...`
- 或 `pilot builds` 能看到新 build number

**processing 验证**：
- 在 ASC TestFlight 构建列表中状态为可用（非 processing）

### 5.3 常见故障与处置

#### (1) `No Accounts` / `iOS Team Provisioning Profile` / `Apple Development ...`
- 判定：Xcode 走了自动签名/开发签名路径
- 处理：固定为手动签名（match AppStore + Apple Distribution），不要依赖 Development cert。

#### (2) `SSL_connect SYSCALL`（GitHub/Dev Portal/ASC）
- 判定：网络/SSL 抖动
- 处理：增加重试（指数退避），优先减少外部依赖（本地缓存 bundler、match mirror）。

#### (3) altool 上传卡死
- 判定：上传进程长时间无收尾
- 处理：中断 → 用已生成 IPA `pilot upload --ipa <path>` 重传（不重建）。

---

## 6. Android：从 commit → GitHub Release

### 6.1 一键构建（建议脚本化）
流程建议：
1) worktree checkout 指定 commit
2) `dart run build_runner ...`
3) `flutter build apk --release --build-number=<build>`
4) `flutter build appbundle --release --build-number=<build>`
5) 复制产物到 artifacts 目录 + 生成 sha256

### 6.2 发布 GitHub Release（每次都发布）
- tag：`android-v1.68.0-<build>`
- 附件：APK/AAB/CHECKSUMS.txt
- Notes 必须标注：若无 keystore 则为 debug signing，不适合 Play Store

---

## 7. 外部测试（External Testing）切换与提交外审（可选）

### 7.1 操作原则
- 同一时间只能有一个 build 在外审
- 切换到新 build 前，必须撤掉旧 build 的外审状态

### 7.2 推荐命令（pilot distribute）
在 `ios/` 下使用 API key：

```bash
bundle exec fastlane pilot distribute \
  --api_key_path /tmp/asc_api_key_papertok.json \
  --apple_id 6759330889 \
  --app_identifier ai.papertok.paperreader \
  --app_platform ios \
  --groups "EX External" \
  --build_number <BUILD> \
  --app_version 1.68.0 \
  --distribute_external true \
  --submit_beta_review true \
  --reject_build_waiting_for_review true
```

> 注意：这一步会因为网络/SSL 抖动失败，建议做 3~5 次重试。

---

## 8. 证书治理（只构建 papertok-reader 时的建议）

- **绝对不要删**：当前 App Store profiles 使用的 Distribution 证书（例如 `YZJJR2Z97G`）
- Development 证书上限触发时：优先修流程（不走自动签名、不创建 dev cert），其次再考虑删除“明显遗留”的 dev cert（例如 `Created via API`）。

---

## 9. 建议的后续优化（可选，但强烈推荐）

1) 新增 `scripts/release_from_commit.sh`：统一编排 iOS + Android +（可选 external）
2) 加互斥锁（file lock）防止并发跑多个 commit 把 state/build number 搞乱
3) 日志与产物统一归档到 `artifacts/`，便于追溯
4) 针对 `SSL_connect` 做统一的 retry wrapper（GitHub/Dev Portal/ASC 共用）

---

## 10. 快速检查清单（Runbook）

- [ ] match repo `main` 是否包含 `certs/` `profiles/` `match_version.txt`
- [ ] `ios/fastlane/Matchfile` 是否 `git_branch("main")`
- [ ] 本地 state file 是否存在并可写
- [ ] build 结束后是否出现 `Successfully uploaded...`
- [ ] ASC 是否出现新 build
- [ ] processing 完成后是否分发 internal

