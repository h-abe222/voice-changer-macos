# GCP 環境構築ガイド

Voice Changer for macOS プロジェクトの GCP 環境セットアップ手順です。

---

## 1. GCP プロジェクト作成

### 1.1 プロジェクト作成

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 上部の「プロジェクトを選択」→「新しいプロジェクト」
3. 以下を入力：
   - **プロジェクト名**: `voice-changer-macos`
   - **プロジェクトID**: `voice-changer-macos`（利用可能な場合）
   - **場所**: 組織または「組織なし」

4. 「作成」をクリック

### 1.2 請求先アカウント設定

1. ナビゲーションメニュー → 「お支払い」
2. 「アカウントをリンク」をクリック
3. 請求先アカウントを選択（なければ作成）

---

## 2. 必要な API の有効化

Cloud Shell または gcloud CLI で以下を実行：

```bash
# プロジェクトを設定
gcloud config set project voice-changer-macos

# 必要な API を有効化
gcloud services enable \
  cloudbuild.googleapis.com \
  storage.googleapis.com \
  firestore.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com
```

---

## 3. Cloud Storage 設定

### 3.1 バケット作成

```bash
# ビルド成果物用バケット
gsutil mb -l asia-northeast1 gs://voice-changer-builds

# クラッシュログ/診断データ用バケット
gsutil mb -l asia-northeast1 gs://voice-changer-logs

# プリセット/モデル配布用バケット（将来用）
gsutil mb -l asia-northeast1 gs://voice-changer-assets
```

### 3.2 ライフサイクルポリシー設定

`lifecycle-builds.json` を作成：

```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
```

適用：

```bash
gsutil lifecycle set lifecycle-builds.json gs://voice-changer-builds
gsutil lifecycle set lifecycle-builds.json gs://voice-changer-logs
```

### 3.3 CORS 設定（アセット用）

`cors.json` を作成：

```json
[
  {
    "origin": ["*"],
    "method": ["GET"],
    "maxAgeSeconds": 3600
  }
]
```

適用：

```bash
gsutil cors set cors.json gs://voice-changer-assets
```

---

## 4. IAM 設定

### 4.1 サービスアカウント作成

```bash
# CI/CD 用サービスアカウント
gcloud iam service-accounts create voice-changer-cicd \
  --display-name="Voice Changer CI/CD"

# アプリ用サービスアカウント（将来用）
gcloud iam service-accounts create voice-changer-app \
  --display-name="Voice Changer App"
```

### 4.2 権限付与

```bash
PROJECT_ID=voice-changer-macos
CICD_SA=voice-changer-cicd@${PROJECT_ID}.iam.gserviceaccount.com

# Cloud Build 用権限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CICD_SA" \
  --role="roles/cloudbuild.builds.builder"

# Storage 用権限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CICD_SA" \
  --role="roles/storage.objectAdmin"

# Secret Manager 用権限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CICD_SA" \
  --role="roles/secretmanager.secretAccessor"
```

### 4.3 サービスアカウントキー生成（GitHub Actions用）

```bash
gcloud iam service-accounts keys create ~/voice-changer-cicd-key.json \
  --iam-account=$CICD_SA
```

> **注意**: このキーは安全に保管し、GitHub Secrets に登録してください。

---

## 5. Secret Manager 設定

### 5.1 シークレット作成

```bash
# Apple 証明書パスワード（例）
echo -n "your-certificate-password" | \
  gcloud secrets create apple-cert-password --data-file=-

# Apple Developer Team ID
echo -n "YOUR_TEAM_ID" | \
  gcloud secrets create apple-team-id --data-file=-
```

---

## 6. Cloud Build 設定（将来用）

### 6.1 GitHub 連携

1. Cloud Console → Cloud Build → トリガー
2. 「リポジトリを接続」
3. 「GitHub (Cloud Build GitHub アプリ)」を選択
4. GitHub で認証、リポジトリ `h-abe222/voice-changer-macos` を選択

### 6.2 ビルドトリガー作成

> **注意**: macOS ビルドは Cloud Build でネイティブサポートされていないため、
> GitHub Actions を使用するか、外部 macOS CI（Mac Stadium 等）と連携します。

GitHub Actions との連携設定は別途 `.github/workflows/` で管理します。

---

## 7. Firestore 設定（将来用）

### 7.1 データベース作成

```bash
gcloud firestore databases create --location=asia-northeast1
```

### 7.2 セキュリティルール

`firestore.rules` を作成：

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // ユーザープリセット
    match /users/{userId}/presets/{presetId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // 公開プリセット（読み取りのみ）
    match /public_presets/{presetId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

デプロイ：

```bash
firebase deploy --only firestore:rules
```

---

## 8. 環境変数・設定ファイル

### 8.1 ローカル開発用 `.env`

プロジェクトルートに `.env.local` を作成（**Git にコミットしない**）：

```bash
GCP_PROJECT_ID=voice-changer-macos
GCP_REGION=asia-northeast1
STORAGE_BUCKET_BUILDS=voice-changer-builds
STORAGE_BUCKET_LOGS=voice-changer-logs
STORAGE_BUCKET_ASSETS=voice-changer-assets
```

### 8.2 GitHub Secrets に登録

GitHub リポジトリ → Settings → Secrets and variables → Actions

| シークレット名 | 値 |
|---------------|-----|
| `GCP_PROJECT_ID` | `voice-changer-macos` |
| `GCP_SA_KEY` | サービスアカウントキー（JSON） |
| `APPLE_CERTIFICATE` | Base64エンコードした証明書 |
| `APPLE_CERTIFICATE_PASSWORD` | 証明書パスワード |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

---

## 9. 検証チェックリスト

- [ ] GCP プロジェクト作成完了
- [ ] 請求先アカウントリンク完了
- [ ] API 有効化完了
- [ ] Cloud Storage バケット作成完了
- [ ] サービスアカウント作成完了
- [ ] IAM 権限設定完了
- [ ] シークレット登録完了（必要な場合）
- [ ] GitHub Secrets 設定完了

---

## 10. コスト見積もり

### 無料枠内で収まる想定

| サービス | 無料枠 | 想定使用量 |
|---------|--------|-----------|
| Cloud Storage | 5GB/月 | 1-2GB（ビルド成果物） |
| Cloud Build | 120分/日 | 使用しない（GitHub Actions） |
| Firestore | 1GB | <100MB |
| Secret Manager | 6アクティブバージョン | 3-5 |

### 月額想定: $0〜5

開発初期は無料枠で十分収まります。

---

## トラブルシューティング

### API 有効化エラー

```bash
# 請求先アカウントが紐づいているか確認
gcloud beta billing projects describe voice-changer-macos
```

### 権限エラー

```bash
# 自分のアカウントに Owner 権限があるか確認
gcloud projects get-iam-policy voice-changer-macos \
  --filter="bindings.members:$(gcloud config get-value account)"
```

---

## 次のステップ

1. 上記手順を実行
2. 検証チェックリストを確認
3. [TASK_LIST.md](../TASK_LIST.md) の 0.2 タスクを更新
