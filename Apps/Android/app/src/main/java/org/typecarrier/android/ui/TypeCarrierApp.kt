@file:Suppress("DEPRECATION")

package org.typecarrier.android.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardReturn
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
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
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.PopupProperties
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import java.io.File
import org.typecarrier.android.R
import org.typecarrier.android.domain.AndroidCarrierRecord
import org.typecarrier.android.domain.AndroidRecordKind
import org.typecarrier.android.domain.AndroidRecordStatus
import org.typecarrier.android.transport.MacService
import org.typecarrier.android.viewmodel.AndroidComposerUiState
import org.typecarrier.android.viewmodel.AndroidConnectionSelfCheck
import org.typecarrier.android.viewmodel.AndroidConnectionStatus
import org.typecarrier.android.viewmodel.AndroidSelfCheckFinding
import org.typecarrier.android.viewmodel.AndroidSelfCheckSeverity
import org.typecarrier.android.viewmodel.AndroidSendState
import org.typecarrier.android.viewmodel.AndroidComposerViewModel

private object AppRoutes {
    const val Home = "home"
    const val History = "history"
    const val Settings = "settings"
    const val About = "about"
    const val Debug = "debug"
    const val Detail = "detail/{recordId}"

    fun detail(recordId: String): String = "detail/$recordId"
}

private enum class HistoryTab {
    Drafts,
    History,
}

private const val NavigationEnterDurationMillis = 320
private const val NavigationExitDurationMillis = 160
private const val TypeCarrierAppStorePlaceholderUrl = "https://apps.apple.com/app/typecarrier"
private const val TypeCarrierLatestReleaseUrl = "https://github.com/AK22AK/TypeCarrier/releases/latest"

@Composable
fun TypeCarrierApp(viewModel: AndroidComposerViewModel) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val clipboard = LocalClipboardManager.current
    val navController = rememberNavController()
    var shouldApplyLaunchFocus by remember { mutableStateOf(true) }

    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) {
                viewModel.handleAppBecameActive()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        NavHost(
            navController = navController,
            startDestination = AppRoutes.Home,
            enterTransition = {
                fadeIn(
                    animationSpec = tween(
                        durationMillis = NavigationEnterDurationMillis,
                        easing = FastOutSlowInEasing,
                    ),
                ) + slideInHorizontally(
                    animationSpec = tween(
                        durationMillis = NavigationEnterDurationMillis,
                        easing = FastOutSlowInEasing,
                    ),
                    initialOffsetX = { it / 12 },
                )
            },
            exitTransition = {
                fadeOut(animationSpec = tween(durationMillis = NavigationExitDurationMillis))
            },
            popEnterTransition = {
                fadeIn(
                    animationSpec = tween(
                        durationMillis = NavigationEnterDurationMillis,
                        easing = FastOutSlowInEasing,
                    ),
                ) + slideInHorizontally(
                    animationSpec = tween(
                        durationMillis = NavigationEnterDurationMillis,
                        easing = FastOutSlowInEasing,
                    ),
                    initialOffsetX = { -it / 12 },
                )
            },
            popExitTransition = {
                fadeOut(animationSpec = tween(durationMillis = NavigationExitDurationMillis))
            },
        ) {
            composable(AppRoutes.Home) {
                HomeScreen(
                state = state,
                    shouldAutoFocusEditor = state.launchesIntoInputMode && shouldApplyLaunchFocus,
                    onEditorAutoFocusConsumed = { shouldApplyLaunchFocus = false },
                onRefresh = viewModel::refreshDiscovery,
                    onOpenHistory = { navController.navigate(AppRoutes.History) },
                    onOpenSettings = { navController.navigate(AppRoutes.Settings) },
                    onOpenAbout = { navController.navigate(AppRoutes.About) },
                    onOpenDebug = { navController.navigate(AppRoutes.Debug) },
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
                onSendReturnModeChange = viewModel::updateSendsReturnAfterPaste,
                )
            }

            composable(AppRoutes.History) {
                HistoryScreen(
                state = state,
                    onBack = { navController.popBackStack() },
                onOpenRecord = {
                        navController.navigate(AppRoutes.detail(it.id))
                },
                onDelete = viewModel::delete,
                onClearDrafts = viewModel::deleteAllDrafts,
                onClearHistory = viewModel::deleteAllOutgoingHistory,
                )
            }

            composable(AppRoutes.Settings) {
                SettingsScreen(
                state = state,
                    onBack = { navController.popBackStack() },
                onSenderDisplayNameChange = viewModel::updateSenderDisplayName,
                onLaunchesIntoInputModeChange = viewModel::updateLaunchesIntoInputMode,
                onEnablesSendReturnGestureChange = viewModel::updateEnablesSendReturnGesture,
                )
            }

            composable(AppRoutes.About) {
                AboutScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            composable(AppRoutes.Debug) {
                DebugScreen(
                state = state,
                diagnosticsText = viewModel.exportDiagnosticsText(),
                    onBack = { navController.popBackStack() },
                onCopyDiagnostics = {
                    clipboard.setText(AnnotatedString(viewModel.exportDiagnosticsText()))
                    Toast.makeText(context, "日志文本已复制到剪贴板", Toast.LENGTH_SHORT).show()
                },
                onExportDiagnostics = {
                    shareDiagnosticsFile(context, viewModel.exportDiagnosticsFile(File(context.cacheDir, "diagnostics")))
                },
                )
            }

            composable(
                route = AppRoutes.Detail,
                arguments = listOf(navArgument("recordId") { type = NavType.StringType }),
            ) { backStackEntry ->
                val recordID = backStackEntry.arguments?.getString("recordId")
                val record = state.records.firstOrNull { it.id == recordID }
                if (record == null) {
                    LaunchedEffect(recordID) {
                        navController.popBackStack()
                    }
                } else {
                    RecordDetailScreen(
                        record = record,
                        onBack = { navController.popBackStack() },
                        onLoadIntoEditor = {
                            viewModel.updateText(forRecord = record, text = it)
                            viewModel.loadIntoEditor(record.copy(text = it))
                            navController.popBackStack(AppRoutes.Home, inclusive = false)
                        },
                        onSendAgain = {
                            viewModel.updateText(forRecord = record, text = it)
                            viewModel.send(record.copy(text = it))
                            navController.popBackStack(AppRoutes.Home, inclusive = false)
                        },
                        onCopy = { clipboard.setText(AnnotatedString(it)) },
                        onDelete = {
                            viewModel.delete(record)
                            navController.popBackStack()
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
    shouldAutoFocusEditor: Boolean,
    onEditorAutoFocusConsumed: () -> Unit,
    onRefresh: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenAbout: () -> Unit,
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
    onSendReturnModeChange: (Boolean) -> Unit,
) {
    var showsConnectionDialog by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val focusManager = LocalFocusManager.current
    val isKeyboardVisible = WindowInsets.ime.getBottom(density) > 0
    val leaveInputMode = {
        focusManager.clearFocus(force = true)
    }

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
            isCompact = isKeyboardVisible,
            onRetry = {
                if (state.canConnect) {
                    onConnect()
                } else {
                    onRefresh()
                }
            },
            onOpenHistory = {
                leaveInputMode()
                onOpenHistory()
            },
            onOpenConnection = {
                leaveInputMode()
                showsConnectionDialog = true
            },
            onOpenSettings = {
                leaveInputMode()
                onOpenSettings()
            },
            onOpenAbout = {
                leaveInputMode()
                onOpenAbout()
            },
            onOpenDebug = {
                leaveInputMode()
                onOpenDebug()
            },
        )

        ConnectionFailureNotice(state.connectionFailureMessage)

        EditorPanel(
            state = state,
            onTextChange = onTextChange,
            onUndo = onUndo,
            onRedo = onRedo,
            onCopy = onCopy,
            onClear = onClear,
            shouldAutoFocus = shouldAutoFocusEditor,
            onAutoFocusConsumed = onEditorAutoFocusConsumed,
            onFocusChanged = {},
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )

        Footer(
            state = state,
            onSaveDraft = onSaveDraft,
            onSend = onSend,
            onSendReturnModeChange = onSendReturnModeChange,
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
    onOpenAbout: () -> Unit,
    onOpenDebug: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var keepCompactForMenu by remember { mutableStateOf(false) }
    val effectiveCompact = isCompact || keepCompactForMenu
    val openMenu = {
        keepCompactForMenu = isCompact
        menuOpen = true
    }
    val dismissMenu = {
        menuOpen = false
        keepCompactForMenu = false
    }

    if (!effectiveCompact) {
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                HeaderActions(
                    state = state,
                    menuOpen = menuOpen,
                    onOpenMenu = openMenu,
                    onDismissMenu = dismissMenu,
                    onRetry = onRetry,
                    onOpenHistory = onOpenHistory,
                    onOpenConnection = onOpenConnection,
                    onOpenSettings = onOpenSettings,
                    onOpenAbout = onOpenAbout,
                    onOpenDebug = onOpenDebug,
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                LogoMark(size = 58.dp, iconSize = 42.dp)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                    Text(
                        "TypeCarrier",
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ConnectionStatusMark(state.connectionStatus)
                        Text(
                            connectionDisplayText(state),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
        return
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    "TypeCarrier",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    ConnectionStatusMark(state.connectionStatus)
                    Text(
                        connectionDisplayText(state),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        HeaderActions(
            state = state,
            menuOpen = menuOpen,
            onOpenMenu = openMenu,
            onDismissMenu = dismissMenu,
            onRetry = onRetry,
            onOpenHistory = onOpenHistory,
            onOpenConnection = onOpenConnection,
            onOpenSettings = onOpenSettings,
            onOpenAbout = onOpenAbout,
            onOpenDebug = onOpenDebug,
        )
    }
}

@Composable
private fun HeaderActions(
    state: AndroidComposerUiState,
    menuOpen: Boolean,
    onOpenMenu: () -> Unit,
    onDismissMenu: () -> Unit,
    onRetry: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenConnection: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenAbout: () -> Unit,
    onOpenDebug: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        HeaderActionButton(onClick = onRetry) {
            Icon(
                Icons.Default.Refresh,
                contentDescription = if (state.canConnect) "重试连接" else "刷新查找",
            )
        }

        HeaderBadgeActionButton(onClick = onOpenHistory) {
            BadgedBox(
                badge = {
                    if (state.draftCount > 0) {
                        Badge { Text(state.draftCount.coerceAtMost(99).toString()) }
                    }
                },
            ) {
                Icon(Icons.Default.History, contentDescription = "历史和草稿")
            }
        }

        Box {
            HeaderActionButton(onClick = onOpenMenu) {
                Icon(Icons.Default.MoreVert, contentDescription = "更多")
            }
            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = onDismissMenu,
                modifier = Modifier.widthIn(min = 164.dp),
                properties = PopupProperties(focusable = false),
            ) {
                CompactMenuItem(
                    icon = Icons.Default.Link,
                    text = "连接 Mac",
                    onClick = {
                        onDismissMenu()
                        onOpenConnection()
                    },
                )
                CompactMenuItem(
                    icon = Icons.Default.Info,
                    text = "关于",
                    onClick = {
                        onDismissMenu()
                        onOpenAbout()
                    },
                )
                CompactMenuItem(
                    icon = Icons.Default.Settings,
                    text = "设置",
                    onClick = {
                        onDismissMenu()
                        onOpenSettings()
                    },
                )
                CompactMenuItem(
                    icon = Icons.Default.BugReport,
                    text = "调试功能",
                    onClick = {
                        onDismissMenu()
                        onOpenDebug()
                    },
                )
            }
        }
    }
}

@Composable
private fun CompactMenuItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(text, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp)) },
        onClick = onClick,
    )
}

@Composable
private fun LogoMark(size: Dp, iconSize: Dp) {
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 4.dp,
        shadowElevation = 8.dp,
        modifier = Modifier.size(size),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Image(
                painter = painterResource(id = R.drawable.typecarrier_logo_mark),
                contentDescription = null,
                modifier = Modifier.size(iconSize),
            )
        }
    }
}

internal fun connectionDisplayText(state: AndroidComposerUiState): String =
    when (state.connectionStatus) {
        AndroidConnectionStatus.Connected -> state.selectedMac?.name ?: "Mac 已连接"
        AndroidConnectionStatus.Connecting -> state.headerStatusText
        AndroidConnectionStatus.Searching -> state.headerStatusText
        AndroidConnectionStatus.Idle -> if (state.connectionFailureMessage != null) "连接失败" else state.selectedMac?.name ?: "未连接"
    }

@Composable
private fun HeaderActionButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(44.dp)) {
        content()
    }
}

@Composable
private fun HeaderBadgeActionButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier.size(48.dp),
        contentAlignment = Alignment.Center,
    ) {
        IconButton(onClick = onClick, modifier = Modifier.size(44.dp)) {
            content()
        }
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
        confirmButton = {
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
private fun ConnectionStatusMark(status: AndroidConnectionStatus) {
    if (status == AndroidConnectionStatus.Connected) {
        Surface(
            shape = CircleShape,
            color = Color(0xFF22C55E),
            modifier = Modifier.size(18.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Default.Check,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(12.dp),
                )
            }
        }
        return
    }

    val color = when (status) {
        AndroidConnectionStatus.Connecting -> Color(0xFFD97706)
        AndroidConnectionStatus.Searching -> Color(0xFF2563EB)
        AndroidConnectionStatus.Idle -> MaterialTheme.colorScheme.onSurfaceVariant
        AndroidConnectionStatus.Connected -> Color(0xFF22C55E)
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
    val connectedMac = state.selectedMac.takeIf { state.connectionStatus == AndroidConnectionStatus.Connected }
    val visibleServices = remember(state.services, connectedMac) {
        if (connectedMac == null || state.services.any { it.id == connectedMac.id }) {
            state.services
        } else {
            listOf(connectedMac) + state.services
        }
    }
    val selectedHasTrust = state.selectedMac?.let { selected ->
        state.trustedMacs.any { it.matchesReceiver(selected) }
    } == true

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.WifiTethering, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("连接 Mac", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    when {
                        connectedMac != null -> "已连接"
                        visibleServices.isEmpty() -> "未发现设备"
                        else -> "${visibleServices.size} 台"
                    },
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

            if (visibleServices.isNotEmpty()) {
                Text(if (connectedMac != null) "当前 Mac" else "发现的 Mac", style = MaterialTheme.typography.labelLarge)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 112.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(visibleServices, key = { it.id }) { service ->
                        val isConnectedService = connectedMac?.id == service.id
                        MacServiceRow(
                            service = service,
                            selected = service.id == state.selectedMac?.id,
                            subtitle = when {
                                isConnectedService -> "已连接"
                                state.trustedMacs.any { it.matchesReceiver(service) } -> "已配对，可免配对连接"
                                else -> "首次连接需要配对码"
                            },
                            onClick = { onSelectMac(service) },
                        )
                    }
                }
            } else {
                Text(
                    "未发现当前网络中的 Mac。正常情况下这里会直接显示 Mac 名称；只有自动发现失败时，才需要展开高级连接使用地址兜底。",
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
                Icon(
                    if (showAdvanced) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                )
                Text("高级连接")
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
                    "这是自动发现失败时的本次兜底入口。正常连接不需要手动查看或输入 IP/端口；换网络或换 Mac 后不要沿用旧地址。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (state.manualHost.isNotBlank()) {
                    TextButton(onClick = { onManualHostChange("") }) {
                        Text("清除手动地址")
                    }
                }
            }

            Button(
                onClick = onConnect,
                enabled = state.connectionStatus != AndroidConnectionStatus.Connected && state.canConnect,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.Link, contentDescription = null)
                Text(
                    when {
                        state.connectionStatus == AndroidConnectionStatus.Connected -> "已连接"
                        state.isBusy && state.connectionStatus == AndroidConnectionStatus.Connecting -> "正在连接"
                        state.selectedMac == null && state.manualHost.isNotBlank() -> "用手动地址连接"
                        selectedHasTrust -> "免配对连接"
                        else -> "配对并连接"
                    },
                )
            }
    }
}

@Composable
private fun MacServiceRow(
    service: MacService,
    selected: Boolean,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
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
    shouldAutoFocus: Boolean,
    onAutoFocusConsumed: () -> Unit,
    onFocusChanged: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusRequester = remember { FocusRequester() }
    val editorScrollState = rememberScrollState()
    var previousTextLength by remember { mutableStateOf(state.text.length) }
    var isFocused by remember { mutableStateOf(false) }
    LaunchedEffect(shouldAutoFocus) {
        if (shouldAutoFocus) {
            focusRequester.requestFocus()
            onAutoFocusConsumed()
        }
    }
    LaunchedEffect(state.text) {
        val isAppending = state.text.length > previousTextLength
        previousTextLength = state.text.length
        if (isAppending) {
            editorScrollState.animateScrollTo(editorScrollState.maxValue)
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
private fun Footer(
    state: AndroidComposerUiState,
    onSaveDraft: () -> Unit,
    onSend: () -> Unit,
    onSendReturnModeChange: (Boolean) -> Unit,
) {
    var sendModeMenuOpen by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilledTonalIconButton(onClick = onSaveDraft, enabled = state.canSaveDraft) {
            Icon(Icons.Default.Save, contentDescription = "保存草稿")
        }
        Spacer(modifier = Modifier.widthIn(min = 12.dp))
        if (!state.enablesSendReturnGesture) {
            OutlinedButton(onClick = onSend, enabled = state.canSend) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null)
                Text(sendButtonText(state.sendState, state.text, sendsReturnAfterPaste = false))
            }
        } else {
            Box {
                val shape = RoundedCornerShape(50)
                val contentColor = if (state.canSend) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                }
                Surface(
                    shape = shape,
                    color = MaterialTheme.colorScheme.surface,
                    contentColor = contentColor,
                    border = BorderStroke(
                        width = 1.dp,
                        color = if (state.canSend) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.outline.copy(alpha = 0.38f),
                    ),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Row(
                            modifier = Modifier
                                .heightIn(min = 40.dp)
                                .clip(RoundedCornerShape(topStartPercent = 50, bottomStartPercent = 50))
                                .clickable(enabled = state.canSend, onClick = onSend)
                                .padding(start = 18.dp, end = 14.dp, top = 10.dp, bottom = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                if (state.sendsReturnAfterPaste) Icons.AutoMirrored.Filled.KeyboardReturn else Icons.AutoMirrored.Filled.Send,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp),
                            )
                            Text(sendButtonText(state.sendState, state.text, state.sendsReturnAfterPaste))
                        }
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(24.dp)
                                .background(MaterialTheme.colorScheme.outlineVariant),
                        )
                        Box(
                            modifier = Modifier
                                .size(width = 44.dp, height = 40.dp)
                                .clip(RoundedCornerShape(topEndPercent = 50, bottomEndPercent = 50))
                                .clickable(enabled = state.canSend) { sendModeMenuOpen = true },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Default.ExpandMore, contentDescription = "发送方式")
                        }
                    }
                }
                DropdownMenu(
                    expanded = sendModeMenuOpen,
                    onDismissRequest = { sendModeMenuOpen = false },
                    modifier = Modifier.widthIn(min = 176.dp),
                    properties = PopupProperties(focusable = false),
                ) {
                    SendModeMenuItem(
                        text = "发送",
                        selected = !state.sendsReturnAfterPaste,
                        onClick = {
                            sendModeMenuOpen = false
                            onSendReturnModeChange(false)
                        },
                    )
                    SendModeMenuItem(
                        text = "发送+回车",
                        selected = state.sendsReturnAfterPaste,
                        onClick = {
                            sendModeMenuOpen = false
                            onSendReturnModeChange(true)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun SendModeMenuItem(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(text, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = {
            if (selected) {
                Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(22.dp))
            } else {
                Spacer(modifier = Modifier.size(22.dp))
            }
        },
        onClick = onClick,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
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
    val scrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()

    Scaffold(
        modifier = Modifier
            .fillMaxSize()
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TypeCarrierTopAppBar(
                title = if (selectedTab == HistoryTab.Drafts) "草稿" else "历史",
                onBack = onBack,
                scrollBehavior = scrollBehavior,
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .navigationBarsPadding(),
            contentPadding = PaddingValues(start = 20.dp, top = 10.dp, end = 20.dp, bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                TabRow(selectedTabIndex = if (selectedTab == HistoryTab.Drafts) 0 else 1) {
                    Tab(selected = selectedTab == HistoryTab.Drafts, onClick = { selectedTab = HistoryTab.Drafts }, text = { Text("草稿") })
                    Tab(selected = selectedTab == HistoryTab.History, onClick = { selectedTab = HistoryTab.History }, text = { Text("历史") })
                }
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        if (selectedTab == HistoryTab.Drafts) "${state.draftCount} 条草稿" else "${state.outgoingHistory.size} 条发送记录",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(onClick = { confirmClear = true }, enabled = records.isNotEmpty()) {
                        Text(if (selectedTab == HistoryTab.Drafts) "清空草稿" else "清空历史")
                    }
                }
            }

            if (records.isEmpty()) {
                item {
                    EmptyState(
                        icon = if (selectedTab == HistoryTab.Drafts) Icons.Default.Save else Icons.Default.History,
                        title = if (selectedTab == HistoryTab.Drafts) "暂无草稿" else "暂无发送记录",
                    )
                }
            } else {
                items(records, key = { it.id }) { record ->
                    RecordRow(
                        record = record,
                        onOpen = { onOpenRecord(record) },
                        onDelete = { onDelete(record) },
                    )
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
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen),
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 1.dp,
    ) {
        ListItem(
            headlineContent = {
                Text(record.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            },
            supportingContent = {
                Text(
                    "${record.status.localizedText()} · ${record.updatedAt.toDisplayTime()}",
                )
            },
            trailingContent = {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = "删除")
                }
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

@Composable
private fun SectionCard(content: @Composable ColumnScope.() -> Unit) {
    ElevatedCard(
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

@Composable
private fun SettingsListItem(
    headline: String,
    supporting: String? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(headline) },
        supportingContent = supporting?.let { { Text(it) } },
        trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
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
        SectionCard {
            OutlinedTextField(
                value = editedText,
                onValueChange = { editedText = it },
                label = { Text("文本") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(240.dp),
            )
        }

        SectionCard {
            SettingsListItem("类型", record.kind.localizedText())
            HorizontalDivider()
            SettingsListItem("状态", record.status.localizedText())
            HorizontalDivider()
            SettingsListItem("更新时间", record.updatedAt.toDisplayTime())
            record.detail?.let {
                HorizontalDivider()
                SettingsListItem("详情", it)
            }
        }

        SectionCard {
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
}

@Composable
private fun SettingsScreen(
    state: AndroidComposerUiState,
    onBack: () -> Unit,
    onSenderDisplayNameChange: (String) -> Unit,
    onLaunchesIntoInputModeChange: (Boolean) -> Unit,
    onEnablesSendReturnGestureChange: (Boolean) -> Unit,
) {
    var draftName by remember(state.senderDisplayName) { mutableStateOf(state.senderDisplayName) }

    ScreenScaffold(title = "设置", onBack = onBack) {
        SectionCard {
            Text("发送端", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            OutlinedTextField(
                value = draftName,
                onValueChange = { draftName = it },
                label = { Text("设备显示名称") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                "Mac 会显示为 ${state.senderDisplayName.ifBlank { state.deviceName }}。留空时使用系统提供的设备名称。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(
                onClick = { onSenderDisplayNameChange(draftName) },
                enabled = draftName.trim() != state.senderDisplayName,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("保存名称")
            }
        }

        SectionCard {
            SettingsListItem(
                headline = "启动时进入输入状态",
                supporting = "打开应用后自动聚焦主输入框。",
                trailing = {
                    Switch(checked = state.launchesIntoInputMode, onCheckedChange = onLaunchesIntoInputModeChange)
                },
            )
            HorizontalDivider()
            SettingsListItem(
                headline = "发送方式选择",
                supporting = "打开后，发送按钮旁会显示发送方式菜单；选择只改变按钮行为，不会立即发送。",
                trailing = {
                    Switch(
                        checked = state.enablesSendReturnGesture,
                        onCheckedChange = onEnablesSendReturnGestureChange,
                    )
                },
            )
        }
    }
}

@Composable
private fun AboutScreen(
    onBack: () -> Unit,
) {
    val context = LocalContext.current

    ScreenScaffold(title = "关于", onBack = onBack) {
        SectionCard {
            Text("TypeCarrier", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            SettingsListItem("应用", "TypeCarrier")
            HorizontalDivider()
            SettingsListItem("版本", currentAppVersionText(context))
        }

        SectionCard {
            Text("更多平台", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            PlatformDownloadItem(
                title = "iOS",
                supporting = "前往 App Store 下载。App Store 页面尚未上架，当前链接是占位位置；正式上架后替换为真实商店地址。",
                onOpen = { openExternalUrl(context, TypeCarrierAppStorePlaceholderUrl) },
            )
            HorizontalDivider()
            PlatformDownloadItem(
                title = "Android",
                supporting = "在 GitHub 最新 Release 下载 APK 侧载包。",
                onOpen = { openExternalUrl(context, TypeCarrierLatestReleaseUrl) },
            )
            HorizontalDivider()
            PlatformDownloadItem(
                title = "macOS",
                supporting = "在 GitHub 最新 Release 下载 Mac 侧载包。",
                onOpen = { openExternalUrl(context, TypeCarrierLatestReleaseUrl) },
            )
        }
    }
}

@Composable
private fun PlatformDownloadItem(
    title: String,
    supporting: String,
    onOpen: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(supporting) },
        trailingContent = {
            TextButton(onClick = onOpen) {
                Text("打开")
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DebugScreen(
    state: AndroidComposerUiState,
    diagnosticsText: String,
    onBack: () -> Unit,
    onCopyDiagnostics: () -> Unit,
    onExportDiagnostics: () -> Unit,
) {
    Scaffold(
        topBar = {
            TypeCarrierTopAppBar(title = "调试日志", onBack = onBack)
        },
        containerColor = MaterialTheme.colorScheme.background,
        modifier = Modifier.fillMaxSize(),
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .navigationBarsPadding(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                SectionCard {
                    Text("连接自检", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    AndroidConnectionSelfCheck.findings(state).forEachIndexed { index, finding ->
                        if (index > 0) {
                            HorizontalDivider()
                        }
                        AndroidSelfCheckFindingRow(finding)
                    }
                }
            }

            item {
                SectionCard {
                    Text("连接", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    SettingsListItem("状态", state.connectionStatus.name)
                    HorizontalDivider()
                    SettingsListItem("本机设备", state.deviceName)
                    HorizontalDivider()
                    SettingsListItem("目标 Mac", state.selectedMac?.name ?: "无")
                    HorizontalDivider()
                    SettingsListItem("发现设备", if (state.services.isEmpty()) "无" else state.services.joinToString { it.name })
                    state.connectionFailureMessage?.let {
                        HorizontalDivider()
                        SettingsListItem("最近错误", it)
                    }
                }
            }

            item {
                SectionCard {
                    Text("日志", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Button(onClick = onExportDiagnostics, enabled = diagnosticsText.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Default.Share, contentDescription = null)
                        Text("导出日志文件")
                    }
                    OutlinedButton(onClick = onCopyDiagnostics, enabled = diagnosticsText.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Default.ContentCopy, contentDescription = null)
                        Text("复制日志文本")
                    }
                }
            }

            item {
                Text("最近调试事件", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }

            if (state.diagnostics.isEmpty()) {
                item {
                    EmptyState(icon = Icons.Default.BugReport, title = "暂无调试事件")
                }
            } else {
                items(state.diagnostics, key = { it.id }) { event ->
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = MaterialTheme.colorScheme.surface,
                        tonalElevation = 1.dp,
                    ) {
                        ListItem(
                            headlineContent = { Text(event.name, fontWeight = FontWeight.SemiBold) },
                            supportingContent = {
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(event.message)
                                    Text(event.timestamp.toDisplayTime())
                                }
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AndroidSelfCheckFindingRow(finding: AndroidSelfCheckFinding) {
    ListItem(
        headlineContent = {
            Text(finding.title, fontWeight = FontWeight.SemiBold)
        },
        supportingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(finding.detail)
                finding.actionTitle?.let {
                    Text(it, fontWeight = FontWeight.Medium)
                }
            }
        },
        leadingContent = {
            Icon(
                imageVector = when (finding.severity) {
                    AndroidSelfCheckSeverity.Ok -> Icons.Default.CheckCircle
                    AndroidSelfCheckSeverity.Warning -> Icons.Default.Info
                    AndroidSelfCheckSeverity.Blocking -> Icons.Default.Close
                    AndroidSelfCheckSeverity.Unknown -> Icons.Default.Info
                },
                contentDescription = null,
                tint = when (finding.severity) {
                    AndroidSelfCheckSeverity.Ok -> Color(0xFF16A34A)
                    AndroidSelfCheckSeverity.Warning -> Color(0xFFD97706)
                    AndroidSelfCheckSeverity.Blocking -> Color(0xFFDC2626)
                    AndroidSelfCheckSeverity.Unknown -> MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TypeCarrierTopAppBar(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    scrollBehavior: TopAppBarScrollBehavior? = null,
) {
    TopAppBar(
        title = {
            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
        },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.background,
            scrolledContainerColor = MaterialTheme.colorScheme.background,
        ),
        modifier = modifier,
        scrollBehavior = scrollBehavior,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScreenScaffold(title: String, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Scaffold(
        topBar = {
            TypeCarrierTopAppBar(title = title, onBack = onBack)
        },
        containerColor = MaterialTheme.colorScheme.background,
        modifier = Modifier.fillMaxSize(),
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 12.dp, bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
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

private fun sendButtonText(sendState: AndroidSendState, text: String, sendsReturnAfterPaste: Boolean): String =
    when (sendState) {
        AndroidSendState.Sending -> "发送中"
        AndroidSendState.Sent -> if (text.isBlank()) "已发送" else sendModeTitle(sendsReturnAfterPaste)
        else -> sendModeTitle(sendsReturnAfterPaste)
    }

private fun sendModeTitle(sendsReturnAfterPaste: Boolean): String =
    if (sendsReturnAfterPaste) "发送+回车" else "发送"

private fun MacService.matchesReceiver(other: MacService): Boolean {
    val macID = macID?.takeIf { it.isNotBlank() }
    val otherMacID = other.macID?.takeIf { it.isNotBlank() }
    return when {
        macID != null && otherMacID != null -> macID == otherMacID
        else -> host == other.host && port == other.port
    }
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

private fun openExternalUrl(context: Context, url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, "没有可用的浏览器", Toast.LENGTH_SHORT).show()
    }
}

private fun currentAppVersionText(context: Context): String =
    try {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        packageInfo.versionName ?: "未知"
    } catch (_: Exception) {
        "未知"
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
