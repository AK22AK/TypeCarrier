@file:Suppress("DEPRECATION")

package org.typecarrier.android.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Redo
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import java.io.File
import org.typecarrier.android.domain.AndroidCarrierRecord
import org.typecarrier.android.domain.AndroidRecordKind
import org.typecarrier.android.domain.AndroidRecordStatus
import org.typecarrier.android.transport.MacService
import org.typecarrier.android.viewmodel.AndroidComposerUiState
import org.typecarrier.android.viewmodel.AndroidConnectionStatus
import org.typecarrier.android.viewmodel.AndroidSendState
import org.typecarrier.android.viewmodel.AndroidComposerViewModel

private enum class AppScreen {
    Home,
    History,
    Settings,
    Debug,
    Detail,
}

private enum class HistoryTab {
    Drafts,
    History,
}

@Composable
fun TypeCarrierApp(viewModel: AndroidComposerViewModel) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var screen by remember { mutableStateOf(AppScreen.Home) }
    var selectedRecordID by remember { mutableStateOf<String?>(null) }

    BackHandler(screen != AppScreen.Home) {
        screen = AppScreen.Home
        selectedRecordID = null
    }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when (screen) {
            AppScreen.Home -> HomeScreen(
                state = state,
                onRefresh = viewModel::refreshDiscovery,
                onOpenHistory = { screen = AppScreen.History },
                onOpenSettings = { screen = AppScreen.Settings },
                onOpenDebug = { screen = AppScreen.Debug },
                onSelectMac = viewModel::selectMac,
                onManualHostChange = viewModel::updateManualHost,
                onManualPortChange = viewModel::updateManualPort,
                onPairingCodeChange = viewModel::updatePairingCode,
                onConnect = { viewModel.connect() },
                onTextChange = viewModel::updateText,
                onUndo = viewModel::undoTextChange,
                onRedo = viewModel::redoTextChange,
                onCopy = {
                    if (state.text.isNotBlank()) {
                        clipboard.setText(AnnotatedString(state.text))
                        viewModel.copyText()
                    }
                },
                onClear = { viewModel.clearText() },
                onSaveDraft = { viewModel.saveDraft() },
                onSend = { viewModel.send() },
            )

            AppScreen.History -> HistoryScreen(
                state = state,
                onBack = { screen = AppScreen.Home },
                onOpenRecord = {
                    selectedRecordID = it.id
                    screen = AppScreen.Detail
                },
                onDelete = viewModel::delete,
                onClearDrafts = viewModel::deleteAllDrafts,
                onClearHistory = viewModel::deleteAllOutgoingHistory,
            )

            AppScreen.Settings -> SettingsScreen(
                state = state,
                onBack = { screen = AppScreen.Home },
                onSenderDisplayNameChange = viewModel::updateSenderDisplayName,
                onLaunchesIntoInputModeChange = viewModel::updateLaunchesIntoInputMode,
            )

            AppScreen.Debug -> DebugScreen(
                state = state,
                diagnosticsText = viewModel.exportDiagnosticsText(),
                onBack = { screen = AppScreen.Home },
                onCopyDiagnostics = {
                    clipboard.setText(AnnotatedString(viewModel.exportDiagnosticsText()))
                    Toast.makeText(context, "日志文本已复制到剪贴板", Toast.LENGTH_SHORT).show()
                },
                onExportDiagnostics = {
                    shareDiagnosticsFile(context, viewModel.exportDiagnosticsFile(File(context.cacheDir, "diagnostics")))
                },
            )

            AppScreen.Detail -> {
                val record = state.records.firstOrNull { it.id == selectedRecordID }
                if (record == null) {
                    screen = AppScreen.History
                } else {
                    RecordDetailScreen(
                        record = record,
                        onBack = { screen = AppScreen.History },
                        onLoadIntoEditor = {
                            viewModel.updateText(forRecord = record, text = it)
                            viewModel.loadIntoEditor(record.copy(text = it))
                            screen = AppScreen.Home
                        },
                        onSendAgain = {
                            viewModel.updateText(forRecord = record, text = it)
                            viewModel.send(record.copy(text = it))
                            screen = AppScreen.Home
                        },
                        onCopy = { clipboard.setText(AnnotatedString(it)) },
                        onDelete = {
                            viewModel.delete(record)
                            screen = AppScreen.History
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(
    state: AndroidComposerUiState,
    onRefresh: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenDebug: () -> Unit,
    onSelectMac: (MacService) -> Unit,
    onManualHostChange: (String) -> Unit,
    onManualPortChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onConnect: () -> Unit,
    onTextChange: (String) -> Unit,
    onUndo: () -> Unit,
    onRedo: () -> Unit,
    onCopy: () -> Unit,
    onClear: () -> Unit,
    onSaveDraft: () -> Unit,
    onSend: () -> Unit,
) {
    var isEditorFocused by remember { mutableStateOf(false) }
    var showsConnectionDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
            .padding(horizontal = 20.dp)
            .padding(top = 14.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Header(
            state = state,
            isCompact = isEditorFocused,
            onRetry = {
                if (state.canConnect) {
                    onConnect()
                } else {
                    onRefresh()
                }
            },
            onOpenHistory = onOpenHistory,
            onOpenConnection = { showsConnectionDialog = true },
            onOpenSettings = onOpenSettings,
            onOpenDebug = onOpenDebug,
        )

        ConnectionFailureNotice(state.connectionFailureMessage)

        EditorPanel(
            state = state,
            onTextChange = onTextChange,
            onUndo = onUndo,
            onRedo = onRedo,
            onCopy = onCopy,
            onClear = onClear,
            onFocusChanged = { isEditorFocused = it },
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )

        Footer(
            state = state,
            onSaveDraft = onSaveDraft,
            onSend = onSend,
        )
    }

    if (showsConnectionDialog) {
        ConnectionDialog(
            state = state,
            onDismiss = { showsConnectionDialog = false },
            onSelectMac = onSelectMac,
            onManualHostChange = onManualHostChange,
            onManualPortChange = onManualPortChange,
            onPairingCodeChange = onPairingCodeChange,
            onConnect = {
                onConnect()
                showsConnectionDialog = false
            },
        )
    }
}

@Composable
private fun Header(
    state: AndroidComposerUiState,
    isCompact: Boolean,
    onRetry: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenConnection: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenDebug: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = if (isCompact) Alignment.CenterVertically else Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(if (isCompact) 8.dp else 10.dp),
        ) {
            if (!isCompact) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.size(36.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            Icons.Default.Keyboard,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(21.dp),
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(if (isCompact) 1.dp else 3.dp)) {
                Text(
                    "TypeCarrier",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    ConnectionDot(state.connectionStatus)
                    Text(
                        state.headerStatusText,
                        style = if (isCompact) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        HeaderActionButton(onClick = onRetry) {
            Icon(
                Icons.Default.Refresh,
                contentDescription = if (state.canConnect) "重试连接" else "刷新查找",
                modifier = Modifier.size(25.dp),
            )
        }

        HeaderActionButton(onClick = onOpenHistory) {
            BadgedBox(
                badge = {
                    if (state.draftCount > 0) {
                        Badge { Text(state.draftCount.coerceAtMost(99).toString()) }
                    }
                },
            ) {
                Icon(Icons.Default.History, contentDescription = "历史和草稿", modifier = Modifier.size(25.dp))
            }
        }

        Box {
            HeaderActionButton(onClick = { menuOpen = true }) {
                Icon(Icons.Default.MoreVert, contentDescription = "更多", modifier = Modifier.size(25.dp))
            }
            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = { menuOpen = false },
                modifier = Modifier.widthIn(min = 176.dp),
            ) {
                DropdownMenuItem(
                    text = { Text("连接 Mac", style = MaterialTheme.typography.bodyLarge) },
                    leadingIcon = { Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(21.dp)) },
                    onClick = {
                        menuOpen = false
                        onOpenConnection()
                    },
                )
                DropdownMenuItem(
                    text = { Text("设置", style = MaterialTheme.typography.bodyLarge) },
                    leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null, modifier = Modifier.size(21.dp)) },
                    onClick = {
                        menuOpen = false
                        onOpenSettings()
                    },
                )
                DropdownMenuItem(
                    text = { Text("调试功能", style = MaterialTheme.typography.bodyLarge) },
                    leadingIcon = { Icon(Icons.Default.BugReport, contentDescription = null, modifier = Modifier.size(21.dp)) },
                    onClick = {
                        menuOpen = false
                        onOpenDebug()
                    },
                )
            }
        }
    }
}

@Composable
private fun HeaderActionButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

@Composable
private fun ConnectionDialog(
    state: AndroidComposerUiState,
    onDismiss: () -> Unit,
    onSelectMac: (MacService) -> Unit,
    onManualHostChange: (String) -> Unit,
    onManualPortChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onConnect: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("关闭")
            }
        },
        title = { Text("连接 Mac") },
        text = {
            ConnectionPanel(
                state = state,
                onSelectMac = onSelectMac,
                onManualHostChange = onManualHostChange,
                onManualPortChange = onManualPortChange,
                onPairingCodeChange = onPairingCodeChange,
                onConnect = onConnect,
            )
        },
    )
}

@Composable
private fun ConnectionDot(status: AndroidConnectionStatus) {
    val color = when (status) {
        AndroidConnectionStatus.Connected -> Color(0xFF18845F)
        AndroidConnectionStatus.Connecting -> Color(0xFFD97706)
        AndroidConnectionStatus.Searching -> Color(0xFF2563EB)
        AndroidConnectionStatus.Idle -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Box(
        modifier = Modifier
            .size(9.dp)
            .clip(CircleShape),
    ) {
        Surface(color = color, modifier = Modifier.fillMaxSize()) {}
    }
}

@Composable
private fun ConnectionFailureNotice(message: String?) {
    if (message == null) {
        return
    }
    Card(
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF4F2)),
        shape = RoundedCornerShape(16.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(9.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                Icons.Default.Info,
                contentDescription = null,
                tint = Color(0xFFC2410C),
                modifier = Modifier.size(20.dp),
            )
            Text(
                message,
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xFF7C2D12),
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun ConnectionPanel(
    state: AndroidComposerUiState,
    onSelectMac: (MacService) -> Unit,
    onManualHostChange: (String) -> Unit,
    onManualPortChange: (String) -> Unit,
    onPairingCodeChange: (String) -> Unit,
    onConnect: () -> Unit,
) {
    var showAdvanced by remember { mutableStateOf(false) }
    val selectedHasTrust = state.selectedMac?.let { selected ->
        state.trustedMacs.any { it.id == selected.id }
    } == true

    Card(
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.WifiTethering, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("连接 Mac", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    if (state.services.isEmpty()) "手动连接可用" else "${state.services.size} 台",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("本机匹配码", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        state.localPairingCode,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            if (state.services.isNotEmpty()) {
                Text("发现的 Mac", style = MaterialTheme.typography.labelLarge)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 112.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.services, key = { it.id }) { service ->
                        MacServiceRow(
                            service = service,
                            selected = service.id == state.selectedMac?.id,
                            subtitle = if (state.trustedMacs.any { it.id == service.id }) "已配对，可免配对连接" else "首次连接需要配对码",
                            onClick = { onSelectMac(service) },
                        )
                    }
                }
            } else {
                Text(
                    "未发现当前网络中的 Mac。请确认 Mac 和 Android 在同一局域网或同一热点；自动发现失败时可展开高级连接输入 Mac 地址。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (!selectedHasTrust) {
                OutlinedTextField(
                    value = state.pairingCode,
                    onValueChange = onPairingCodeChange,
                    label = { Text("Mac 匹配码") },
                    supportingText = { Text("输入 Mac 上显示的匹配码；Mac 也可以输入本机匹配码来关联。") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                    shape = RoundedCornerShape(16.dp),
                ) {
                    Text(
                        "这台 Mac 已配对，连接时不需要再次输入匹配码。",
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            TextButton(onClick = { showAdvanced = !showAdvanced }) {
                Text(if (showAdvanced) "收起高级连接" else "高级连接")
            }

            if (showAdvanced) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedTextField(
                        value = state.manualHost,
                        onValueChange = onManualHostChange,
                        label = { Text("Mac 地址") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = state.manualPort,
                        onValueChange = onManualPortChange,
                        label = { Text("端口") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                        modifier = Modifier.weight(0.58f),
                    )
                }
                Text(
                    "仅用于自动发现失败时兜底。输入地址后仍会使用已保存的信任信息或匹配码完成连接。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Button(onClick = onConnect, enabled = state.canConnect, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Link, contentDescription = null)
                Text(
                    when {
                        state.isBusy && state.connectionStatus == AndroidConnectionStatus.Connecting -> "正在连接"
                        selectedHasTrust -> "免配对连接"
                        else -> "配对并连接"
                    },
                )
            }
        }
    }
}

@Composable
private fun MacServiceRow(service: MacService, selected: Boolean, subtitle: String? = null, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                if (selected) Icons.Default.CheckCircle else Icons.Default.WifiTethering,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(service.name, fontWeight = FontWeight.SemiBold)
                Text(
                    subtitle ?: "可连接",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun EditorPanel(
    state: AndroidComposerUiState,
    onTextChange: (String) -> Unit,
    onUndo: () -> Unit,
    onRedo: () -> Unit,
    onCopy: () -> Unit,
    onClear: () -> Unit,
    onFocusChanged: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusRequester = remember { FocusRequester() }
    val editorScrollState = rememberScrollState()
    var isFocused by remember { mutableStateOf(false) }
    LaunchedEffect(state.launchesIntoInputMode) {
        if (state.launchesIntoInputMode) {
            focusRequester.requestFocus()
        }
    }

    Surface(
        shape = RoundedCornerShape(26.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = if (isFocused) 2.dp else 1.dp,
        shadowElevation = 1.dp,
        border = BorderStroke(
            width = if (isFocused) 2.dp else 1.dp,
            color = if (isFocused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        ),
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp, vertical = 16.dp),
        ) {
            BasicTextField(
                value = state.text,
                onValueChange = onTextChange,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(editorScrollState)
                    .focusRequester(focusRequester)
                    .onFocusChanged {
                        isFocused = it.isFocused
                        onFocusChanged(it.isFocused)
                    },
                decorationBox = { innerTextField ->
                    Box(modifier = Modifier.fillMaxSize()) {
                        if (state.text.isEmpty()) {
                            Text(
                                "输入或语音输入",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        innerTextField()
                    }
                },
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                EditorActionButton(onClick = onUndo, enabled = state.canUndo) {
                    Icon(Icons.Default.Undo, contentDescription = "撤销文本编辑", modifier = Modifier.size(20.dp))
                }
                Spacer(modifier = Modifier.width(8.dp))
                EditorActionButton(onClick = onRedo, enabled = state.canRedo) {
                    Icon(Icons.Default.Redo, contentDescription = "重做文本编辑", modifier = Modifier.size(20.dp))
                }
                Spacer(modifier = Modifier.weight(1f))
                EditorActionButton(onClick = onCopy, enabled = state.text.isNotBlank()) {
                    Icon(Icons.Default.ContentCopy, contentDescription = "复制文本", modifier = Modifier.size(20.dp))
                }
                Spacer(modifier = Modifier.width(8.dp))
                EditorActionButton(onClick = onClear, enabled = state.text.isNotBlank()) {
                    Icon(Icons.Default.Close, contentDescription = "清空文本", modifier = Modifier.size(20.dp))
                }
            }
        }
    }
}

@Composable
private fun EditorActionButton(
    onClick: () -> Unit,
    enabled: Boolean,
    content: @Composable () -> Unit,
) {
    FilledTonalIconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(40.dp),
        content = content,
    )
}

@Composable
private fun Footer(state: AndroidComposerUiState, onSaveDraft: () -> Unit, onSend: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilledTonalIconButton(onClick = onSaveDraft, enabled = state.canSaveDraft) {
            Icon(Icons.Default.Save, contentDescription = "保存草稿")
        }
        Spacer(modifier = Modifier.widthIn(min = 12.dp))
        OutlinedButton(onClick = onSend, enabled = state.canSend) {
            Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null)
            Text(sendButtonText(state.sendState, state.text))
        }
    }
}

@Composable
private fun HistoryScreen(
    state: AndroidComposerUiState,
    onBack: () -> Unit,
    onOpenRecord: (AndroidCarrierRecord) -> Unit,
    onDelete: (AndroidCarrierRecord) -> Unit,
    onClearDrafts: () -> Unit,
    onClearHistory: () -> Unit,
) {
    var selectedTab by remember { mutableStateOf(if (state.drafts.isEmpty()) HistoryTab.History else HistoryTab.Drafts) }
    var confirmClear by remember { mutableStateOf(false) }
    val records = if (selectedTab == HistoryTab.Drafts) state.drafts else state.outgoingHistory

    ScreenScaffold(title = if (selectedTab == HistoryTab.Drafts) "草稿" else "历史", onBack = onBack) {
        TabRow(selectedTabIndex = if (selectedTab == HistoryTab.Drafts) 0 else 1) {
            Tab(selected = selectedTab == HistoryTab.Drafts, onClick = { selectedTab = HistoryTab.Drafts }, text = { Text("草稿") })
            Tab(selected = selectedTab == HistoryTab.History, onClick = { selectedTab = HistoryTab.History }, text = { Text("历史") })
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (selectedTab == HistoryTab.Drafts) "${state.draftCount} 条草稿" else "${state.outgoingHistory.size} 条发送记录",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(onClick = { confirmClear = true }, enabled = records.isNotEmpty()) {
                Text(if (selectedTab == HistoryTab.Drafts) "清空草稿" else "清空历史")
            }
        }

        if (records.isEmpty()) {
            EmptyState(
                icon = if (selectedTab == HistoryTab.Drafts) Icons.Default.Save else Icons.Default.History,
                title = if (selectedTab == HistoryTab.Drafts) "暂无草稿" else "暂无发送记录",
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(records, key = { it.id }) { record ->
                    RecordRow(record = record, onOpen = { onOpenRecord(record) }, onDelete = { onDelete(record) })
                }
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            confirmButton = {
                TextButton(onClick = {
                    if (selectedTab == HistoryTab.Drafts) onClearDrafts() else onClearHistory()
                    confirmClear = false
                }) { Text("清空") }
            },
            dismissButton = {
                TextButton(onClick = { confirmClear = false }) { Text("取消") }
            },
            title = { Text(if (selectedTab == HistoryTab.Drafts) "清空草稿箱？" else "清空历史记录？") },
            text = { Text("删除后无法撤销。") },
        )
    }
}

@Composable
private fun RecordRow(record: AndroidCarrierRecord, onOpen: () -> Unit, onDelete: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(record.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    "${record.status.localizedText()} · ${record.updatedAt.toDisplayTime()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "删除")
            }
        }
    }
}

@Composable
private fun RecordDetailScreen(
    record: AndroidCarrierRecord,
    onBack: () -> Unit,
    onLoadIntoEditor: (String) -> Unit,
    onSendAgain: (String) -> Unit,
    onCopy: (String) -> Unit,
    onDelete: () -> Unit,
) {
    var editedText by remember(record.id) { mutableStateOf(record.text) }

    ScreenScaffold(title = if (record.kind == AndroidRecordKind.Draft) "草稿" else "已发送文本", onBack = onBack) {
        OutlinedTextField(
            value = editedText,
            onValueChange = { editedText = it },
            label = { Text("文本") },
            modifier = Modifier
                .fillMaxWidth()
                .height(240.dp),
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text("类型：${record.kind.localizedText()}")
                Text("状态：${record.status.localizedText()}")
                Text("更新时间：${record.updatedAt.toDisplayTime()}")
                record.detail?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
        Button(onClick = { onLoadIntoEditor(editedText) }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.Edit, contentDescription = null)
            Text("载入编辑器")
        }
        Button(onClick = { onSendAgain(editedText) }, enabled = editedText.trim().isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null)
            Text("再次发送")
        }
        OutlinedButton(onClick = { onCopy(editedText) }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.ContentCopy, contentDescription = null)
            Text("复制")
        }
        OutlinedButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.Delete, contentDescription = null)
            Text("删除")
        }
    }
}

@Composable
private fun SettingsScreen(
    state: AndroidComposerUiState,
    onBack: () -> Unit,
    onSenderDisplayNameChange: (String) -> Unit,
    onLaunchesIntoInputModeChange: (Boolean) -> Unit,
) {
    var draftName by remember(state.senderDisplayName) { mutableStateOf(state.senderDisplayName) }

    ScreenScaffold(title = "设置", onBack = onBack) {
        OutlinedTextField(
            value = draftName,
            onValueChange = { draftName = it },
            label = { Text("设备显示名称") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Button(
            onClick = { onSenderDisplayNameChange(draftName) },
            enabled = draftName.trim() != state.senderDisplayName,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("保存名称")
        }
        Text(
            "Mac 会显示为 ${state.senderDisplayName.ifBlank { state.deviceName }}。留空时使用系统提供的设备名称。",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("启动时进入输入状态", modifier = Modifier.weight(1f))
            Switch(checked = state.launchesIntoInputMode, onCheckedChange = onLaunchesIntoInputModeChange)
        }
    }
}

@Composable
private fun DebugScreen(
    state: AndroidComposerUiState,
    diagnosticsText: String,
    onBack: () -> Unit,
    onCopyDiagnostics: () -> Unit,
    onExportDiagnostics: () -> Unit,
) {
    ScreenScaffold(title = "调试日志", onBack = onBack) {
        DebugRow("状态", state.connectionStatus.name)
        DebugRow("本机设备", state.deviceName)
        DebugRow("目标 Mac", state.selectedMac?.name ?: "无")
        DebugRow("发现设备", if (state.services.isEmpty()) "无" else state.services.joinToString { it.name })
        state.connectionFailureMessage?.let { DebugRow("最近错误", it) }
        Button(onClick = onExportDiagnostics, enabled = diagnosticsText.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.Share, contentDescription = null)
            Text("导出日志文件")
        }
        OutlinedButton(onClick = onCopyDiagnostics, enabled = diagnosticsText.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.ContentCopy, contentDescription = null)
            Text("复制日志文本")
        }
        Text("最近调试事件", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(state.diagnostics, key = { it.id }) { event ->
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(event.name, fontWeight = FontWeight.SemiBold)
                        Text(event.message, style = MaterialTheme.typography.bodySmall)
                        Text(event.timestamp.toDisplayTime(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun DebugRow(title: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, modifier = Modifier.widthIn(max = 220.dp), maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun ScreenScaffold(title: String, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 20.dp)
            .padding(top = 14.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("返回") }
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

@Composable
private fun EmptyState(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun sendButtonText(sendState: AndroidSendState, text: String): String =
    when (sendState) {
        AndroidSendState.Sending -> "发送中"
        AndroidSendState.Sent -> if (text.isBlank()) "已发送" else "发送"
        else -> "发送"
    }

private fun AndroidRecordKind.localizedText(): String =
    when (this) {
        AndroidRecordKind.Draft -> "草稿"
        AndroidRecordKind.Outgoing -> "已发送"
        AndroidRecordKind.Incoming -> "已接收"
    }

private fun AndroidRecordStatus.localizedText(): String =
    when (this) {
        AndroidRecordStatus.Draft -> "草稿"
        AndroidRecordStatus.Queued -> "排队中"
        AndroidRecordStatus.Sent -> "已发送"
        AndroidRecordStatus.Received,
        AndroidRecordStatus.PastePosted,
        AndroidRecordStatus.PasteUnverified,
        AndroidRecordStatus.PasteFailed,
        -> "已接收"
        AndroidRecordStatus.Failed -> "失败"
    }

private fun String.toDisplayTime(): String = replace("T", " ").removeSuffix("Z").take(16)

private fun shareDiagnosticsFile(context: Context, file: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "application/json"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "TypeCarrier Android diagnostics")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    try {
        context.startActivity(Intent.createChooser(sendIntent, "导出 TypeCarrier 日志").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, "没有可用的导出应用", Toast.LENGTH_SHORT).show()
    }
}

@Composable
fun TypeCarrierTheme(content: @Composable () -> Unit) {
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
