#!/usr/bin/env bash
set -euo pipefail

MAIN_ACTIVITY="$(find android/app/src/main -type f -name MainActivity.kt | head -n 1)"
if [ -z "$MAIN_ACTIVITY" ]; then
  echo "Could not find generated Kotlin MainActivity." >&2
  exit 1
fi

PACKAGE_NAME="$(sed -n 's/^package[[:space:]]\+//p' "$MAIN_ACTIVITY" | head -n 1)"
if [ -z "$PACKAGE_NAME" ]; then
  echo "Could not determine Android package from $MAIN_ACTIVITY." >&2
  exit 1
fi

SOURCE_DIR="$(dirname "$MAIN_ACTIVITY")"

cat > "$MAIN_ACTIVITY" <<EOF
package $PACKAGE_NAME

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance()
            .get(NexusApplication.ENGINE_ID)
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
EOF

cat > "$SOURCE_DIR/NexusApplication.kt" <<EOF
package $PACKAGE_NAME

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class NexusApplication : Application() {
    private lateinit var nexusEngine: FlutterEngine

    override fun onCreate() {
        super.onCreate()

        nexusEngine = FlutterEngine(this)
        nexusEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, nexusEngine)
    }

    companion object {
        const val ENGINE_ID = "nexus_engine"
    }
}
EOF

python3 - "$PACKAGE_NAME" <<'PY'
from pathlib import Path
import sys

package_name = sys.argv[1]
manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()

replacement = f'android:name="{package_name}.NexusApplication"'
if 'android:name="${applicationName}"' in text:
    text = text.replace('android:name="${applicationName}"', replacement, 1)
elif "<application" in text and "NexusApplication" not in text:
    text = text.replace("<application", f"<application\n        {replacement}", 1)

manifest.write_text(text)
PY

echo "Configured retained Nexus FlutterEngine for $PACKAGE_NAME"
