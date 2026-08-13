#!/bin/sh
set -e

# Flutter SDKをインストール
FLUTTER_VERSION="3.32.2"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${FLUTTER_VERSION}-stable.tar.xz"

cd $HOME
curl -O $FLUTTER_URL
tar -xf flutter_macos_arm64_${FLUTTER_VERSION}-stable.tar.xz
export PATH="$HOME/flutter/bin:$PATH"

# プロジェクトルートに移動
cd $CI_WORKSPACE

# APIキーファイルを生成（Xcode Cloud環境変数から）
echo "const String hotpepperApiKey = '$HOTPEPPER_API_KEY';" > lib/secrets.dart

# Flutter依存パッケージを取得
flutter pub get

# CocoaPodsのインストール
cd ios && pod install
