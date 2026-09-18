const String nexusBuildWorkflow = r'''name: Nexus Project Build

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout project
        uses: actions/checkout@v4

      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Install Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Detect, analyze, test and build
        shell: bash
        run: |
          set -euo pipefail

          if [ -f pubspec.yaml ]; then
            echo "Nexus detected a Flutter project."
            flutter pub get
            flutter analyze --no-fatal-infos

            if [ -d test ] && find test -type f -name '*_test.dart' -print -quit | grep -q .; then
              flutter test
            else
              echo "No Flutter tests found; skipping flutter test."
            fi

            flutter build apk --debug --target-platform android-arm64
            exit 0
          fi

          if [ -f gradlew ]; then
            echo "Nexus detected an Android/Gradle project."
            chmod +x gradlew
            ./gradlew test assembleDebug
            exit 0
          fi

          echo "::error::Nexus could not detect a supported build profile."
          echo "Expected pubspec.yaml for Flutter or gradlew for Android/Gradle."
          exit 2

      - name: Upload APK artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nexus-project-apk
          if-no-files-found: warn
          path: |
            build/app/outputs/flutter-apk/*.apk
            **/build/outputs/apk/**/*.apk
''';
