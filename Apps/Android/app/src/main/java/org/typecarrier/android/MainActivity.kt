package org.typecarrier.android

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.typecarrier.android.diagnostics.AndroidDiagnosticLogStore
import org.typecarrier.android.storage.AndroidRecordStore
import org.typecarrier.android.transport.AndroidCarrierRepositoryImpl
import org.typecarrier.android.ui.TypeCarrierApp
import org.typecarrier.android.ui.TypeCarrierTheme
import org.typecarrier.android.viewmodel.AndroidComposerViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(
                scrim = android.graphics.Color.TRANSPARENT,
                darkScrim = android.graphics.Color.TRANSPARENT,
            ),
            navigationBarStyle = SystemBarStyle.light(
                scrim = android.graphics.Color.TRANSPARENT,
                darkScrim = android.graphics.Color.TRANSPARENT,
            ),
        )
        setContent {
            val context = LocalContext.current.applicationContext
            val viewModel = remember {
                AndroidComposerViewModel(
                    repository = AndroidCarrierRepositoryImpl(context),
                    recordStore = AndroidRecordStore(file = File(context.filesDir, "android-records.json")),
                    diagnosticLogStore = AndroidDiagnosticLogStore(file = File(context.filesDir, "android-debug-events.jsonl")),
                    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
                )
            }

            DisposableEffect(viewModel) {
                viewModel.start()
                onDispose {
                    viewModel.close()
                }
            }

            TypeCarrierTheme {
                TypeCarrierApp(viewModel = viewModel)
            }
        }
    }
}
