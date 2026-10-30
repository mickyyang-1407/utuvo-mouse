# RELEASING — UTUVO Mouse 發行流程（MOUSE-008A）

這份文件描述「已經有一個建置好的 App 之後，怎麼把它變成一個可發布的簽章版本」。
文件本身是公開文件：只用佔位符，不寫任何個人憑證標籤、憑證路徑或帳號名稱。

工具：`scripts/package-release.sh`（同一個 `scripts/release-input-check.sh` 是它的自我檢查）。

---

## 0. 誰能做什麼

「發行維護者」指負責驗收與發行的人或其獲授權代理，不是作業系統的 root 帳號；不需要 sudo。

| 動作 | 誰 |
|---|---|
| `--plan`（只驗證輸入、印出計畫） | 任何人；零副作用 |
| `--execute`（真的簽章／公证／產生 appcast） | **只有發行維護者**，而且要在 UI 與裝置關卡全數通過之後 |
| 上傳發布檔、動 GitHub 發布頁 | **只有發行維護者**，而且本腳本不會代勞 |
| 公鑰以外的任何秘密 | 不進 argv、不進環境變數、不進檔案、不進 repo |

`--plan` 不讀 Keychain。`--execute` 會透過官方 Sparkle 工具查詢及使用指定的既有 Keychain 金鑰。
本腳本**不做**：不建立／匯出／匯入金鑰或憑證、不新增 notary profile、
不新增 Apple 帳號、不接受私鑰、不上傳、不動 git、不登錄、不動 TCC、不結束任何 App 或服務。

---

## 1. 執行前必須存在的東西（由發行維護者準備）

1. 已建置且設定好更新金鑰的 App（`SUPublicEDKey` 已經寫進 `Info.plist`）。
   只有 ad-hoc 簽章、沒有金鑰的 App 會被本腳本拒絕——那是刻意的。
2. 明確的 **Developer ID Application** 簽章身分（不放進 repo，只在執行時當參數給）。
3. 已存在的 **notarytool keychain profile**（本腳本不會建立，也不會改動它）。
4. **Sparkle 更新金鑰**放在 Keychain，對應一個明確的帳號名稱；本腳本只會用
   `--account` 指定它，永遠不會用預設的全域帳號（官方文件記載的預設值 `ed25519`
   會被直接拒絕）。
5. **官方 Sparkle artifact**：`--sparkle-tools-dir` 要指到官方 artifact 裡的 `bin/`
   目錄（內含 `sign_update`、`generate_appcast`、`generate_keys`）。本腳本只用**靜態中繼資料**
   確認版本：artifact 根目錄的 `CHANGELOG` 第一個標題必須是釘住版本（預設 2.10.1，
   可用 `--expected-sparkle-version` 覆寫），`Sparkle.xcframework/Info.plist` 必須含 arm64。
   工具缺任何必要旗標時，本腳本會在動手之前就停下。

> 公鑰（base64 的 32 bytes）可以公開，它是 App 內嵌的更新公鑰，不是秘密。
> 私鑰永遠留在 Keychain。

---

## 2. 先跑計畫

```sh
scripts/package-release.sh --plan \
  --app "/path/to/UTUVO Mouse.app" \
  --output "/path/to/new-output-dir" \
  --version "NEXT_VERSION" \
  --build "NEXT_BUILD" \
  --identity "Developer ID Application: PLACEHOLDER (PLACEHOLDER)" \
  --notary-profile "PLACEHOLDER" \
  --sparkle-account "PLACEHOLDER" \
  --public-key "BASE64_PUBLIC_KEY" \
  --download-prefix "https://example.com/releases/download/vNEXT_VERSION" \
  --project-link "https://example.com/project/utuvo-mouse" \
  --sparkle-tools-dir "/path/to/sparkle-2.10.1/bin"
```

`--plan` 會做的事：

- 檢查 `.app` 存在、不是符號連結、`Info.plist` 可解析
- 確認 bundle id 仍是 `com.utuvo.mouse`
- 確認版本比目前版本大、**build 是正整數且大於目前 build**（monotonic）
- 確認 `LSMinimumSystemVersion` 是 macOS 14 以上
- 確認**架構**：App 主執行檔必須剛好是 arm64；Sparkle.framework 與它的 helper
  （Autoupdate、Updater、Downloader.xpc、Installer.xpc）可以是 universal
  （arm64 + x86_64），但**一定要含 arm64**。架構讀不到就 fail closed，不會放行。
- 確認公鑰是合法 base64、剛好 32 bytes、不是全零／單位元佔位值，
  而且**與 App 內嵌的 `SUPublicEDKey` 完全一致**
- 確認 feed、下載前綴、專案連結都是 https、而且有真實的公開主機名稱
- 確認輸出目錄不存在、不是符號連結、也不在輸入 App 內部或其上層
- 確認官方 artifact 的**靜態**中繼資料：`CHANGELOG` 版本、`Sparkle.xcframework` 架構、
  三支工具的 SHA-256

`--plan` **不會**做的事：建立任何檔案或目錄、執行 App、**執行任何被提供的
Sparkle 工具（連 `--help`／`--version` 都不行）**、讀 Keychain、簽章、連網、
變更登入項目。

輸出計畫會把個人憑證標籤遮蔽（只留 `(TEAMID)`），公鑰只顯示 SHA-256 指紋。

---

## 3. 真正執行（發行維護者）

```sh
scripts/package-release.sh --execute [同上全部參數] \
  --public-key-fingerprint "SHA256_OF_PUBLIC_KEY"
```

`--execute` 本身就是那個明確動作，不需要再敲一次授權旗標。
`--public-key-fingerprint` 在執行模式是必填：它必須等於公鑰的 SHA-256，
目的是擋掉「拿佔位金鑰當成發行金鑰」。

輸出目錄結構：

```
<output>/
  staging/            私有：pre-notary ZIP、公证收據、sign_update 輸出、執行紀錄
  publish/            發布清單：正式 ZIP、appcast.xml、SHA256SUMS（只有這三個）
  release-receipt.txt 本機稽核收據；不在發布白名單（版本、team id、公鑰指紋、帳號、feed、長度、SHA256、EdDSA 簽章、公证狀態、artifact 版本與工具雜湊）
```

範例中的 `NEXT_VERSION` 與 `NEXT_BUILD` 必須換成比輸入 App 更高的版本及 build。

步驟（本腳本會照順序做，任何一步失敗就停，不重試、不覆蓋、不靜默繼續）：

0. **動手之前**：確認官方工具的 CLI 真的支援我們要用的旗標；
   用 `generate_keys --account ACCOUNT -p` **只查詢**該帳號在 Keychain 裡的公開金鑰，
   必須等於 App 內嵌的 `SUPublicEDKey`（查不到就是查不到，**絕不自動產生金鑰**）。
   這兩個檢查都通過才會建立輸出目錄。
1. **複製**：`ditto` 把 App 複製到 `staging/app/`，只用 PlistBuddy 改
   `CFBundleShortVersionString` 與 `CFBundleVersion`，其他一概不動。
   有了 `--feed-url` 就用 `plutil -replace` 把它套用到暫存 App 的 `SUFeedURL`，
   套用後必須與選定的 feed 一致。複製後會再確認 bundle id 與內嵌公鑰沒有變。
2. **由內而外簽章**：順序是 Downloader.xpc → Installer.xpc → Autoupdate →
   Updater.app → Sparkle.framework → App 本體。每一項都用明確身分 +
   `--options runtime`（hardened runtime）+ `--timestamp`（安全時間戳），
   並保留既有 entitlements。**簽章永遠不用 `--deep`**；`--deep` 只出現在驗證。
   缺任何一項必要元件就停。簽完會檢查外層權威是 `Developer ID Application`、
   team id 非空、巢狀項目與外層同 team，並留下 designated requirement 收據。
3. **公證**：先產生 pre-notary ZIP（留在 `staging`，不進發布目錄），
   `xcrun notarytool submit --keychain-profile ... --wait --output-format json`，
   JSON 從 **stdout** 收（`notarytool` 沒有 `--output-file` 這個選項），
   **必須是 `Accepted` 才繼續**，然後 staple、`stapler validate`、
   `codesign --verify --deep --strict`、`spctl --assess`。
4. **正式 ZIP**：staple 之後才用 `ditto` 產生正式 ZIP 到 `publish/`。
   ZIP 產生後不再改動（Ed25519 簽章是決定性的，不會改寫檔案）。
   `sign_update --account ACCOUNT -p ARCHIVE` 取得簽章，再用
   `sign_update --account ACCOUNT --verify ARCHIVE SIGNATURE` 驗證——
   驗證一定要用**同一個** `--account`，否則驗的不是同一把金鑰。
   不用 `-s`、不用 `--ed-key-file`、不用預設帳號、不接受私鑰環境變數。
5. **appcast**：`generate_appcast --account ... --download-url-prefix ... --link ...
   --maximum-deltas 0 publish/`，發布目錄在跑之前只有正式 ZIP。
   產生的 appcast 會被逐項比對（格式照官方 `SampleAppcast.xml`：`sparkle:version`、
   `sparkle:shortVersionString` 是 `<item>` 的子元素，`url`、`length` 是無命名空間屬性，
   `sparkle:edSignature` 是帶前綴的屬性）：
   - 剛好一個項目符合版本與 build
   - `length` 等於實際 ZIP 大小
   - `url` 在下載前綴內且指向正式 ZIP
   - `sparkle:edSignature` 是合法 base64、64 bytes，**而且與先前用
     `sign_update --verify`（同一個帳號）驗證過的簽章字串完全一致**
   - App 內嵌公鑰、版本、bundle id、feed 都與發布內容一致

   任一項不符就停。接著寫 `SHA256SUMS`。
6. **發布清單**：只輸出 `publish/` 裡的三個檔案。**本腳本不上傳**，
   也拒絕把私有暫存或合成／損壞的檔案放進發布目錄。

---

## 4. 發行維護者還要做的事（本腳本不做，也不證明）

- 真的上傳三個發布檔，並確認 appcast 的網址在公開 HTTPS 上可讀
- `spctl --assess` 的結果、Gatekeeper 與 TCC 連續性（designated requirement 必須被新版本滿足）
- 從「先前的正式版本」實際升級到新版本，確認自動更新真的會走完整條路
- 實際安裝 `UTUVO Mouse.app`、啟動、登入項目狀態
- 需要時另外做一份**臨時損壞副本**給 `sign_update --verify` 看它拒絕；
  絕對不要覆蓋已簽章的 ZIP 或已發布的 feed，也不要上傳損壞檔

---

## 5. 自我檢查

```sh
scripts/release-input-check.sh
```

這支腳本只用暫存目錄與合成 fixture，檢查：

- `--help` 零副作用
- `--plan` 零副作用（前後檔案清單完全相同，且完全沒有呼叫 `security`／`codesign`／
  `xcrun`／`notarytool`／`stapler`／`spctl`／`ditto`，也**沒有執行任何被提供的
  Sparkle 工具**——測試時那些都是會留下記錄的假工具）
- 壞輸入全部在副作用之前被拒（結束碼 2）：壞 base64、長度不對、全零佔位金鑰、
  與 App 內嵌值不一致、http／無主機／非公開網域的網址、build 為 0／負數／非整數／
  沒有比目前 build 大、版本沒有比目前版本大、輸出在 App 內部／是 App 上層／已存在、
  缺身分、缺 profile、缺帳號、帳號是官方預設值 `ed25519`、身分不是 Developer ID
  Application、App 沒有內嵌公鑰、bundle id 被改掉、架構讀不到
- universal 的 Sparkle.framework（arm64 + x86_64）**不會**被誤判拒絕
- `--i-have-authorization` 已經不存在（多打會被當成未知選項）
- **mock 執行流程**：`codesign`、`xcrun`、`spctl`、`sign_update`、`generate_appcast`、
  `generate_keys` 全部換成假的，驗證：
  - 沒有用 `notarytool` 不支援的 `--output-file`（假 `xcrun` 會直接拒絕這個選項）
  - `sign_update --verify` 帶的是同一個 `--account`
  - `generate_keys` 是以 `--account ACCOUNT -p` 查詢公開金鑰，沒有產生金鑰
  - 帳號公開金鑰與 App 內嵌金鑰不符時拒絕發行
  - appcast 是用**真實格式**（前置命名空間、版本為子元素）產生的，而且能被抓到
  - `--feed-url` 真的被套用到暫存 App 的 `SUFeedURL`
  - Sparkle 工具缺必要旗標時 fail-closed

> mock 用的公鑰是合成的填充值，**不是任何真實的發行金鑰**。
> mock 跑完只證明流程與比對邏輯，**完全不構成簽章、公证或更新的證據**。
