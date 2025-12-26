# Voice Changer for macOS - Development Bible

> **本ドキュメントについて**
>
> このドキュメントは、macOS向けリアルタイム音声変換システム開発における**唯一の信頼できる情報源（Single Source of Truth）**です。
>
> 設計判断、実装方針、検証基準に迷った場合は、本ドキュメントを参照してください。
> 変更が必要な場合は、本ドキュメントを更新した上で実装に反映してください。

---

## 1. プロダクトビジョン

### 1.1 目的

macOSユーザーが、ビデオ会議（Google Meet / Zoom / Teams）において：

1. **Speaking Mode**: 自分の声をリアルタイムで変換し、相手に届ける
2. **Listening Mode**: 相手の声をリアルタイムで変換し、自分のヘッドホンで聴く

を低遅延・安定的に実現するデスクトップアプリケーション。

### 1.2 設計原則

| 原則 | 説明 |
|------|------|
| **安定性最優先** | クラッシュしない、会議を壊さない。品質より安定を選ぶ |
| **低遅延** | 端末内処理40ms以下を目標。遅延は体験を破壊する |
| **シンプル** | 最小構成で動くものを作り、段階的に拡張する |
| **ユーザー体験** | 設定の手間を最小化。ON/OFFだけで使える状態を目指す |

### 1.3 非ゴール（やらないこと）

- ブラウザ拡張としての実装
- iOS/Android対応（macOS専用）
- 著作権侵害となる音声の無断学習機能
- プロ向け音楽制作ツール級の高機能化

---

## 2. システムアーキテクチャ

### 2.1 全体構成

```
┌─────────────────────────────────────────────────────────────┐
│                        macOS                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ Physical Mic │    │   会議アプリ   │    │Physical HP   │  │
│  └──────┬───────┘    └───────┬──────┘    └──────▲───────┘  │
│         │                    │                   │          │
│         ▼                    ▼                   │          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Voice Changer App                        │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │Audio Capture│→│Audio Engine│→│Audio Output │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  │         │              │               │              │  │
│  │         │              ▼               │              │  │
│  │         │       ┌────────────┐        │              │  │
│  │         │       │  DSP Chain │        │              │  │
│  │         │       │ NS→AGC→FX→ │        │              │  │
│  │         │       │  Limiter   │        │              │  │
│  │         │       └────────────┘        │              │  │
│  └─────────┼──────────────────────────────┼──────────────┘  │
│            │                              │                  │
│            ▼                              ▼                  │
│  ┌──────────────┐                ┌──────────────┐          │
│  │ Virtual Mic  │                │ Virtual Spk  │          │
│  │ (V-Mic)      │                │ (V-Spk) v1.5 │          │
│  └──────────────┘                └──────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 データフロー

**Speaking Mode (v1)**
```
Physical Mic → App (Capture) → DSP Chain → Virtual Mic → 会議アプリ
                                    ↓
                              Monitor出力 → Physical HP（任意）
```

**Listening Mode (v1.5)**
```
会議アプリ → Virtual Spk → App (Capture) → DSP Chain → Physical HP
```

### 2.3 コンポーネント責務

| コンポーネント | 責務 | 技術 |
|--------------|------|------|
| **App (UI)** | ユーザー操作、設定管理、状態表示 | SwiftUI |
| **Audio Engine** | 音声キャプチャ、処理、出力制御 | Core Audio |
| **DSP Chain** | 音声変換処理 | Accelerate.framework |
| **Virtual Mic** | 仮想入力デバイス（会議アプリが選択） | Audio Server Driver Plug-in |
| **Virtual Spk** | 仮想出力デバイス（v1.5） | Audio Server Driver Plug-in |

---

## 3. 開発フェーズ

### Phase 1: MVP - Speaking Mode（最優先）

**目標**: Google Meetで自分の変換した声を相手に届ける

#### 3.1.1 成果物

1. **Virtual Mic Driver**
   - BlackHoleをベースに、最小限の仮想マイクを実装
   - 外部アプリから「入力デバイス」として認識される

2. **Voice Changer App**
   - Physical Mic からの音声キャプチャ
   - DSP Chain（NS / AGC / Pitch / Formant / EQ / Limiter）
   - Virtual Mic への音声出力
   - Monitor機能（自分の声をヘッドホンで確認）

3. **基本UI**
   - Speaking ON/OFF トグル
   - 入力デバイス選択
   - プリセット選択
   - レイテンシモード（Ultra Low / Balanced / High Quality）
   - VUメーター（入力/出力）
   - 状態表示

#### 3.1.2 受入基準

| 項目 | 基準 | 測定方法 |
|------|------|----------|
| レイテンシ | 40ms以下 | ループバック測定 |
| 安定性 | 30分連続で音切れなし | 実会議テスト |
| 互換性 | Google Meet（Chrome）で動作 | 実機確認 |
| CPU使用率 | 15%以下（M1 Mac） | Activity Monitor |
| 切替応答 | ON/OFF 1秒以内 | ストップウォッチ |

---

### Phase 2: Listening Mode + 安定化

**目標**: 相手の声を変換して聴く + Zoom/Teams対応

#### 3.2.1 成果物

1. **Virtual Spk Driver**
   - 会議アプリの出力先として選択可能

2. **Listening Mode**
   - Virtual Spk からのキャプチャ
   - DSP Chain 経由で Physical HP へ出力

3. **AEC（エコーキャンセル）**
   - Speaking + Listening 同時使用時のエコー/ハウリング防止

4. **安全機能**
   - Bluetooth遅延検出と警告
   - スピーカー使用時の制限

#### 3.2.2 受入基準

| 項目 | 基準 |
|------|------|
| 安定性 | 2時間連続で音切れなし |
| 互換性 | Zoom / Teams でも動作 |
| AEC | 同時使用でエコーなし |

---

### Phase 3: 高度な音声変換

**目標**: より自然な音声変換、カスタマイズ性向上

#### 3.3.1 成果物

1. 軽量ニューラルVC（RVCベースのリアルタイムモデル）
2. カスタム音声プリセット登録
3. Metal による GPU アクセラレーション

---

## 4. 技術仕様

### 4.1 音声パラメータ

| パラメータ | 値 | 理由 |
|-----------|-----|------|
| サンプルレート | 48kHz | 会議アプリの標準 |
| チャンネル | Mono | 音声通話に十分 |
| ビット深度 | Float32（内部） | DSP処理精度 |
| フレームサイズ | 256 samples（約5.3ms） | 低遅延と安定のバランス |

### 4.2 DSP Chain 構成

```
Input → HPF(80Hz) → Noise Suppressor → AGC → Voice FX → Limiter → Output
                                              ↓
                                        Pitch Shift
                                        Formant Shift
                                        EQ (3-band)
```

| モジュール | 役割 | 実装 |
|-----------|------|------|
| HPF | DC除去、低周波ノイズ除去 | Accelerate vDSP |
| Noise Suppressor | 環境ノイズ抑制 | WebRTC NS or RNNoise |
| AGC | 自動ゲイン調整 | Accelerate vDSP |
| Pitch Shift | 音高変更 | Phase Vocoder |
| Formant Shift | フォルマント変更 | LPC + Pitch独立制御 |
| EQ | 音質調整 | Biquad Filter |
| Limiter | クリッピング防止 | Soft Knee Limiter |

### 4.3 レイテンシモード

| モード | フレームサイズ | バッファ | 想定遅延 | FX制限 |
|--------|--------------|---------|---------|--------|
| Ultra Low | 128 (2.7ms) | 3 frames | ~20ms | Pitch/Formant OFF |
| Balanced | 256 (5.3ms) | 4 frames | ~30ms | 全FX使用可 |
| High Quality | 512 (10.7ms) | 6 frames | ~50ms | 重いFX許可 |

### 4.4 状態遷移

```
     ┌─────────┐
     │  IDLE   │ ← 初期状態
     └────┬────┘
          │ start()
          ▼
     ┌─────────┐
     │  ARMED  │ ← デバイス準備完了
     └────┬────┘
          │ 音声処理開始
          ▼
     ┌─────────┐     負荷過大      ┌──────────┐
     │ RUNNING │ ───────────────→ │ DEGRADED │
     └────┬────┘ ←─────────────── └──────────┘
          │           復旧
          │ stop() or エラー
          ▼
     ┌─────────┐
     │  ERROR  │ → 自動復旧試行 or ユーザー操作待ち
     └─────────┘
```

---

## 5. ディレクトリ構成

```
VoiceChanger/
├── README.md
├── DEVELOPMENT_BIBLE.md          # 本ドキュメント
├── LICENSE
│
├── App/                          # メインアプリケーション
│   ├── VoiceChanger.xcodeproj
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── VoiceChangerApp.swift
│   │   │   ├── AppController.swift
│   │   │   └── SettingsStore.swift
│   │   │
│   │   ├── Audio/
│   │   │   ├── AudioEngine.swift
│   │   │   ├── DeviceManager.swift
│   │   │   ├── AudioCapture.swift
│   │   │   └── AudioOutput.swift
│   │   │
│   │   ├── DSP/
│   │   │   ├── DSPChain.swift
│   │   │   ├── NoiseSuppressor.swift
│   │   │   ├── AutoGainControl.swift
│   │   │   ├── VoiceFX.swift
│   │   │   ├── PitchShifter.swift
│   │   │   ├── FormantShifter.swift
│   │   │   ├── Equalizer.swift
│   │   │   └── Limiter.swift
│   │   │
│   │   ├── UI/
│   │   │   ├── MainView.swift
│   │   │   ├── ControlPanel.swift
│   │   │   ├── VUMeter.swift
│   │   │   ├── PresetPicker.swift
│   │   │   └── StatusIndicator.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── AudioFrame.swift
│   │   │   ├── EngineState.swift
│   │   │   ├── VoicePreset.swift
│   │   │   └── LatencyMode.swift
│   │   │
│   │   └── Utilities/
│   │       ├── RingBuffer.swift
│   │       ├── Logging.swift
│   │       └── Constants.swift
│   │
│   ├── Resources/
│   │   ├── Presets/              # デフォルトプリセット
│   │   └── Assets.xcassets
│   │
│   └── Tests/
│       ├── DSPTests/
│       └── AudioEngineTests/
│
├── VirtualMicDriver/             # 仮想マイクドライバ
│   ├── VirtualMicDriver.xcodeproj
│   └── Sources/
│       ├── VirtualMicDriver.mm
│       ├── VirtualMicDevice.mm
│       └── VirtualMicStream.mm
│
├── VirtualSpkDriver/             # 仮想スピーカー（v1.5）
│   └── ...
│
├── Installer/                    # インストーラ
│   ├── Scripts/
│   └── Distribution/
│
├── Tools/                        # 開発ツール
│   ├── latency_tester/
│   └── log_viewer/
│
└── Docs/                         # 参考ドキュメント（旧）
    ├── requirements.txt
    ├── SRC.txt
    ├── IF.txt
    └── repository_folder_structure.txt
```

---

## 6. 検証仕様

### 6.1 テストマトリクス

#### 機能テスト

| ID | カテゴリ | テスト内容 | 合格基準 |
|----|---------|-----------|---------|
| FT-01 | Speaking | ON/OFF切替 | 1秒以内に切替、クリックノイズなし |
| FT-02 | Speaking | プリセット変更 | 100ms以内で切替、破綻なし |
| FT-03 | Speaking | デバイス変更 | DEGRADED表示→復旧 |
| FT-04 | Monitor | 自分の声確認 | 遅延が体感で許容範囲 |
| FT-05 | UI | 設定保存/復元 | 再起動後も設定維持 |

#### 互換性テスト

| ID | アプリ | テスト内容 | 合格基準 |
|----|-------|-----------|---------|
| CT-01 | Google Meet (Chrome) | V-Mic選択、10分通話 | 途切れなし |
| CT-02 | Google Meet (Safari) | V-Mic選択、10分通話 | 途切れなし |
| CT-03 | Zoom (Client) | V-Mic選択、10分通話 | 途切れなし |
| CT-04 | Teams (Client) | V-Mic選択、10分通話 | 途切れなし |
| CT-05 | Teams (Browser) | V-Mic選択、10分通話 | 途切れなし |

#### 性能テスト

| ID | 項目 | 合格基準 | 測定方法 |
|----|------|---------|----------|
| PT-01 | レイテンシ（Ultra Low） | 25ms以下 | ループバック測定 |
| PT-02 | レイテンシ（Balanced） | 40ms以下 | ループバック測定 |
| PT-03 | CPU使用率 | 15%以下（M1） | Activity Monitor |
| PT-04 | メモリ使用量 | 100MB以下 | Activity Monitor |

#### 安定性テスト

| ID | テスト内容 | 合格基準 |
|----|-----------|---------|
| ST-01 | 30分連続使用 | 音切れ0回 |
| ST-02 | 2時間連続使用（v1.5） | 音切れ0回 |
| ST-03 | スリープ復帰 | 5秒以内に復旧 |
| ST-04 | デバイス抜き差し | クラッシュなし |

#### 異常系テスト

| ID | シナリオ | 期待動作 |
|----|---------|---------|
| ET-01 | マイク権限なし | 設定誘導UI表示 |
| ET-02 | 入力デバイス切断 | DEGRADED → ERROR、復旧案内 |
| ET-03 | CPU高負荷 | DEGRADED移行、品質低下で継続 |
| ET-04 | Bluetooth遅延大 | 警告表示 |

### 6.2 リリース基準

**Phase 1 (v1.0) リリース条件**
- [ ] FT-01〜FT-05 全合格
- [ ] CT-01 合格（Google Meet最低限）
- [ ] PT-01〜PT-04 全合格
- [ ] ST-01 合格
- [ ] ET-01〜ET-03 全合格

**Phase 2 (v1.5) リリース条件**
- [ ] Phase 1 条件に加えて
- [ ] CT-02〜CT-05 全合格
- [ ] ST-02 合格
- [ ] Listening Mode 関連テスト全合格
- [ ] AEC関連テスト全合格

---

## 7. 開発ガイドライン

### 7.1 コーディング規約

- **言語**: Swift 5.9+, Objective-C++（Driver）
- **フォーマット**: SwiftFormat 準拠
- **命名規則**: Apple Swift API Design Guidelines 準拠

### 7.2 リアルタイム処理の鉄則

1. **Audio Callback内での禁止事項**
   - メモリアロケーション（malloc, new, Swiftの配列拡張）
   - ロック取得（mutex, semaphore）
   - I/O操作（ファイル、ネットワーク）
   - Objective-Cメッセージ送信（できるだけ避ける）

2. **必須パターン**
   - Lock-free Ring Buffer でスレッド間通信
   - 事前アロケーションしたバッファを再利用
   - Atomic変数でフラグ管理

### 7.3 エラーハンドリング方針

| レベル | 対応 |
|--------|------|
| 致命的 | 状態をERRORへ、ユーザーに復旧方法を案内 |
| 回復可能 | DEGRADEDへ移行、品質を下げて継続 |
| 警告 | ログ記録、UIに通知（任意） |

### 7.4 ログ方針

- **記録する**: 状態遷移、エラー、パフォーマンス統計
- **記録しない**: 生音声データ、個人を特定できる情報
- **フォーマット**: 構造化ログ（JSON）、タイムスタンプ必須

---

## 8. 依存関係とライセンス

### 8.1 使用予定ライブラリ

| ライブラリ | 用途 | ライセンス |
|-----------|------|-----------|
| BlackHole | 仮想デバイス参考 | MIT |
| WebRTC (audio_processing) | NS/AEC | BSD-3-Clause |
| RNNoise | ノイズ抑制（代替） | BSD-3-Clause |

### 8.2 Apple Frameworks

- Core Audio
- Audio Toolbox
- Accelerate
- SwiftUI
- Combine

---

## 9. 変更履歴

| 日付 | バージョン | 変更内容 | 著者 |
|------|-----------|---------|------|
| 2025-12-27 | 1.0 | 初版作成 | Claude |

---

## 付録

### A. 用語集

| 用語 | 説明 |
|------|------|
| Physical Mic | 物理マイク（内蔵/USB/Bluetooth） |
| Physical HP | 物理ヘッドホン/イヤホン |
| V-Mic | 仮想マイク（本アプリが作成） |
| V-Spk | 仮想スピーカー（本アプリが作成、v1.5〜） |
| DSP | Digital Signal Processing |
| NS | Noise Suppression（ノイズ抑制） |
| AGC | Automatic Gain Control（自動ゲイン調整） |
| AEC | Acoustic Echo Cancellation（エコーキャンセル） |
| XRUN | バッファオーバーラン/アンダーラン |

### B. 参考ドキュメント

- `Docs/requirements.txt` - 元のシステム要件定義書
- `Docs/SRC.txt` - 元のSRS実装指示書
- `Docs/IF.txt` - 元のモジュールI/F定義
- `Docs/repository_folder_structure.txt` - 元のフォルダ構成案

これらは参考資料として保持しますが、**本ドキュメントが正**です。
