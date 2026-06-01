package org.typecarrier.android

import android.content.Context
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.typecarrier.android.protocol.AndroidBridgeResponseStatus
import org.typecarrier.android.protocol.AndroidPairingCode
import org.typecarrier.android.transport.AndroidCarrierClient
import org.typecarrier.android.transport.MacDiscovery
import org.typecarrier.android.transport.MacService
import java.util.Locale
import java.util.UUID

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TypeCarrierTheme {
                TypeCarrierApp()
            }
        }
    }
}

@Composable
private fun TypeCarrierApp() {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences("typecarrier", Context.MODE_PRIVATE) }
    val deviceID = remember {
        prefs.getString("device_id", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("device_id", it).apply()
        }
    }
    val deviceName = remember { localDeviceName() }

    var services by remember { mutableStateOf(emptyList<MacService>()) }
    var selectedService by remember { mutableStateOf<MacService?>(null) }
    var pairingCode by remember { mutableStateOf("") }
    var manualHost by remember { mutableStateOf(prefs.getString("manual_host", "") ?: "") }
    var manualPort by remember { mutableStateOf(prefs.getString("manual_port", "17641") ?: "17641") }
    var text by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("正在查找 Mac") }
    var client by remember { mutableStateOf<AndroidCarrierClient?>(null) }
    var busy by remember { mutableStateOf(false) }

    val discovery = remember {
        MacDiscovery(
            context = context.applicationContext,
            onServicesChanged = {
                services = it
                selectedService = selectedService?.let { selected ->
                    it.firstOrNull { service -> service.id == selected.id }
                } ?: it.firstOrNull()
                status = if (it.isEmpty()) "未发现 Mac" else "发现 ${it.size} 台 Mac"
            },
            onError = { status = it },
        )
    }

    DisposableEffect(discovery) {
        discovery.start()
        onDispose {
            discovery.stop()
            client?.close()
        }
    }

    LaunchedEffect(selectedService?.id) {
        client?.close()
        client = null
    }

    val manualService = manualService(manualHost, manualPort)
    val effectiveService = selectedService ?: manualService
    val hasSavedTrustToken = effectiveService?.let { prefs.getString("trust_token.${it.name}", null) != null } == true
    val canConnect = effectiveService != null &&
        (AndroidPairingCode.isValid(pairingCode) || hasSavedTrustToken) &&
        !busy
    val canSend = client != null && text.isNotBlank() && !busy

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Header(
                status = status,
                onRefresh = {
                    discovery.stop()
                    discovery.start()
                },
            )

            ConnectionPanel(
                services = services,
                selectedService = selectedService,
                manualHost = manualHost,
                manualPort = manualPort,
                pairingCode = pairingCode,
                canConnect = canConnect,
                busy = busy,
                onSelectService = { service ->
                    selectedService = service
                    manualHost = ""
                    manualPort = ""
                },
                onManualHostChange = {
                    selectedService = null
                    manualHost = it.trim()
                    prefs.edit().putString("manual_host", manualHost).apply()
                },
                onManualPortChange = {
                    selectedService = null
                    manualPort = it.filter(Char::isDigit).take(5)
                    prefs.edit().putString("manual_port", manualPort).apply()
                },
                onPairingCodeChange = { pairingCode = it.filter(Char::isDigit).take(6) },
                onConnect = {
                    val service = effectiveService ?: return@ConnectionPanel
                    scope.launch {
                        busy = true
                        val nextClient = AndroidCarrierClient(service)
                        val savedTrustToken = prefs.getString("trust_token.${service.name}", null)
                        val code = pairingCode.takeIf(AndroidPairingCode::isValid)
                        runCatching {
                            nextClient.pair(
                                deviceID = deviceID,
                                deviceName = deviceName,
                                pairingCode = code,
                                trustToken = savedTrustToken.takeIf { code == null },
                            )
                        }.onSuccess { response ->
                            if (response.status == AndroidBridgeResponseStatus.Accepted) {
                                client?.close()
                                client = nextClient
                                response.trustToken?.let {
                                    prefs.edit().putString("trust_token.${service.name}", it).apply()
                                }
                                status = "已连接到 ${service.name}"
                            } else {
                                status = response.message ?: "连接被拒绝"
                            }
                        }.onFailure {
                            nextClient.close()
                            status = it.localizedMessage ?: "连接失败"
                        }
                        busy = false
                    }
                },
            )

            EditorPanel(
                text = text,
                onTextChange = { text = it },
                onCopy = {
                    if (text.isNotBlank()) {
                        clipboard.setText(AnnotatedString(text))
                        status = "已复制文本"
                    }
                },
                onClear = { text = "" },
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            )

            Footer(
                canSend = canSend,
                busy = busy,
                onSend = {
                    val activeClient = client ?: return@Footer
                    val trimmed = text.trim()
                    scope.launch {
                        busy = true
                        runCatching {
                            activeClient.sendText(trimmed, deviceName)
                        }.onSuccess { receipt ->
                            status = receipt?.detail ?: "已发送"
                            text = ""
                        }.onFailure {
                            activeClient.close()
                            client = null
                            status = it.localizedMessage ?: "发送失败"
                        }
                        busy = false
                    }
                },
            )
        }
    }
}

@Composable
private fun Header(status: String, onRefresh: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("TypeCarrier", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            Text(status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        IconButton(onClick = onRefresh) {
            Icon(Icons.Default.Refresh, contentDescription = "重试连接", tint = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun ConnectionPanel(
    services: List<MacService>,
    selectedService: MacService?,
    manualHost: String,
    manualPort: String,
    pairingCode: String,
    canConnect: Boolean,
    busy: Boolean,
    onSelectService: (MacService) -> Unit,
    onManualHostChange: (String) -> Unit,
    onManualPortChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onConnect: () -> Unit,
) {
    Card(
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.WifiTethering, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("连接 Mac", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }

            MacServiceList(services = services, selectedService = selectedService, onSelect = onSelectService)

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = manualHost,
                    onValueChange = onManualHostChange,
                    label = { Text("Mac 地址") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = manualPort,
                    onValueChange = onManualPortChange,
                    label = { Text("端口") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(0.62f),
                )
            }

            OutlinedTextField(
                value = pairingCode,
                onValueChange = onPairingCodeChange,
                label = { Text("配对码") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Button(onClick = onConnect, enabled = canConnect, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Link, contentDescription = null)
                Text(if (busy) "正在连接" else "连接")
            }
        }
    }
}

@Composable
private fun MacServiceList(
    services: List<MacService>,
    selectedService: MacService?,
    onSelect: (MacService) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 132.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(services, key = { it.id }) { service ->
            val selected = service.id == selectedService?.id
            Card(
                onClick = { onSelect(service) },
                colors = CardDefaults.cardColors(
                    containerColor = if (selected) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else {
                        MaterialTheme.colorScheme.surfaceVariant
                    },
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(service.name, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${service.host}:${service.port}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (selected) {
                        Text("已选", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }

        if (services.isEmpty()) {
            item {
                Text(
                    "未发现可连接的 Mac，可手动输入 Mac 地址和端口。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun EditorPanel(
    text: String,
    onTextChange: (String) -> Unit,
    onCopy: () -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp),
        modifier = modifier,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            OutlinedTextField(
                value = text,
                onValueChange = onTextChange,
                placeholder = { Text("输入或语音输入") },
                modifier = Modifier
                    .fillMaxSize()
                    .padding(14.dp),
                minLines = 8,
            )

            Row(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(24.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilledTonalIconButton(onClick = onCopy, enabled = text.isNotBlank()) {
                    Icon(Icons.Default.ContentCopy, contentDescription = "复制文本")
                }
                FilledTonalIconButton(onClick = onClear, enabled = text.isNotBlank()) {
                    Icon(Icons.Default.Close, contentDescription = "清空文本")
                }
            }
        }
    }
}

@Composable
private fun Footer(canSend: Boolean, busy: Boolean, onSend: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        OutlinedButton(onClick = onSend, enabled = canSend) {
            Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null)
            Text(if (busy) "发送中" else "发送")
        }
    }
}

@Composable
private fun TypeCarrierTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Color(0xFF0F766E),
            secondary = Color(0xFF6D5BD0),
            tertiary = Color(0xFFB45309),
            background = Color(0xFFFBF8FC),
            surface = Color(0xFFFFFBFF),
        ),
        content = content,
    )
}

private fun manualService(host: String, port: String): MacService? {
    val cleanHost = host.trim()
    val cleanPort = port.toIntOrNull()
    if (cleanHost.isBlank() || cleanPort == null || cleanPort !in 1..65_535) {
        return null
    }
    return MacService(name = "手动 Mac", host = cleanHost, port = cleanPort)
}

private fun localDeviceName(): String {
    val manufacturer = Build.MANUFACTURER.orEmpty()
    val model = Build.MODEL.orEmpty()
    val name = if (model.lowercase(Locale.getDefault()).startsWith(manufacturer.lowercase(Locale.getDefault()))) {
        model
    } else {
        "$manufacturer $model"
    }
    return name.trim().ifBlank { "Android" }
}
