package __PKG__

import com.jojo.study_companion.blocker.BlockerChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BlockerChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
