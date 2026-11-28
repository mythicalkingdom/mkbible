package org.mkbible.proof

import android.content.SharedPreferences
import android.os.Bundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import kotlinx.coroutines.launch
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = File(filesDir, "sword")
        if (assets.list("")?.contains("sword") == true) copyAssets("sword", root)
        val store = ModuleStore(root)
        val prefs = getSharedPreferences("mkbible", MODE_PRIVATE)
        setContent {
            var look by remember { mutableStateOf(loadLook(prefs)) }
            val dark = look.theme == 2 || (look.theme == 0 && isSystemInDarkTheme())
            val view = LocalView.current
            SideEffect {
                androidx.core.view.WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !dark
            }
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) {
                    Reader(store, prefs, look, dark) { look = it; saveLook(prefs, it) }
                }
            }
        }
    }

    private fun copyAssets(path: String, dest: File) {
        val kids = assets.list(path) ?: return
        if (kids.isEmpty()) {
            if (!dest.exists()) {
                dest.parentFile?.mkdirs()
                assets.open(path).use { i -> dest.outputStream().use { o -> i.copyTo(o) } }
            }
        } else {
            dest.mkdirs()
            for (k in kids) copyAssets("$path/$k", File(dest, k))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Reader(store: ModuleStore, prefs: SharedPreferences, look: Look, dark: Boolean, onLook: (Look) -> Unit) {
    val context = LocalContext.current
    var mods by remember { mutableStateOf(store.list()) }
    val tabs = remember { mutableStateListOf<Tab>().also { it.addAll(loadTabs(prefs)) } }
    var active by remember { mutableIntStateOf(prefs.getInt("tabActive", 0).coerceIn(0, tabs.size - 1)) }
    val closedTabs = remember { ArrayList<Tab>() }
    val bibles = remember { HashMap<String, Bible>() }     // opened modules, shared by all tabs
    var curBible by remember { mutableStateOf<Bible?>(null) }
    var curModule by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var book by remember { mutableIntStateOf(tabs[active].book) }
    var chap by remember { mutableIntStateOf(tabs[active].chap) }
    var modPicker by remember { mutableStateOf(false) }
    var showFoot by remember { mutableStateOf(prefs.getBoolean("foot", true)) }
    var showXref by remember { mutableStateOf(prefs.getBoolean("xref", true)) }
    var viewMenu by remember { mutableStateOf(false) }
    var openNote by remember { mutableStateOf<NoteItem?>(null) }
    var downloading by remember { mutableStateOf(false) }
    var settings by remember { mutableStateOf(false) }
    val lexicons = remember { Lexicons(store) }
    var strongOn by remember { mutableStateOf(prefs.getBoolean("strong", true)) }
    var openStrong by remember { mutableStateOf<Pair<String, String>?>(null) }
    var targetVerse by remember { mutableIntStateOf(0) }
    var pendingScroll by remember { mutableIntStateOf(-1) }          // scroll position to restore after a tab switch
    var layout by remember { mutableStateOf<androidx.compose.ui.text.TextLayoutResult?>(null) }
    var picking by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val tabBarState = androidx.compose.foundation.lazy.rememberLazyListState()

    fun bibleFor(id: String): Bible? {
        bibles[id]?.let { return it }
        val m = mods.firstOrNull { it.name == id } ?: return null
        val h = Native.open(m.conf)
        if (h == 0L) return null
        return Bible(h, m.label).also { bibles[id] = it }
    }
    // the module of a tab if it is still installed, otherwise the first one
    fun resolve(id: String): String? = if (mods.any { it.name == id }) id else mods.firstOrNull()?.name

    fun openModule(m: ModInfo) {
        val nb = bibleFor(m.name)
        if (nb == null) { message = "Cannot open ${m.label}"; return }
        if (book > nb.books.size) { book = 1; chap = 1 }
        curBible = nb
        curModule = m.name
    }
    if (curBible == null) {
        val id = resolve(tabs[active].module)
        val nb = id?.let { bibleFor(it) }
        if (nb != null && id != null) { curBible = nb; curModule = id; if (book > nb.books.size) { book = 1; chap = 1 } }
    }

    fun saveActive() {
        if (active in tabs.indices && curModule.isNotEmpty()) tabs[active] = Tab(curModule, book, chap, scroll.value)
    }
    fun loadTab(t: Tab, verse: Int = 0) {
        val id = resolve(t.module) ?: return
        val nb = bibleFor(id) ?: return
        curBible = nb; curModule = id
        book = t.book.coerceIn(1, nb.books.size); chap = t.chap
        targetVerse = verse
        pendingScroll = if (verse > 0) -1 else t.scroll
    }
    fun activate(i: Int) { saveActive(); active = i; loadTab(tabs[i]) }
    fun newTab(bk: Int, ch: Int, v: Int = 0, module: String = curModule) {
        saveActive()
        tabs.add(Tab(module, bk, ch, 0)); active = tabs.size - 1
        loadTab(tabs[active], v)
    }
    fun closeTab(i: Int) {
        if (tabs.size <= 1) return
        if (i == active) saveActive()
        closedTabs.add(tabs[i]); if (closedTabs.size > 10) closedTabs.removeAt(0)
        tabs.removeAt(i)
        if (i < active) active--
        else if (i == active) { active = minOf(i, tabs.size - 1); loadTab(tabs[active]) }
    }
    fun reopenTab() {
        if (closedTabs.isEmpty()) return
        saveActive()
        tabs.add(closedTabs.removeAt(closedTabs.size - 1)); active = tabs.size - 1
        loadTab(tabs[active])
    }
    // the tab set is remembered between runs (the scroll position of a tab only survives a switch, not a restart)
    LaunchedEffect(tabs.toList(), active, book, chap, curModule) {
        val snapshot = tabs.toMutableList()
        if (active in snapshot.indices && curModule.isNotEmpty()) snapshot[active] = Tab(curModule, book, chap, 0)
        saveTabs(prefs, snapshot, active)
        prefs.edit().putString("module", curModule).apply()
    }
    LaunchedEffect(active, tabs.size) { if (tabs.size > 1) tabBarState.animateScrollToItem(active.coerceIn(0, tabs.size - 1)) }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val err = store.importZip(context.contentResolver, uri)
            mods = store.list()
            message = err ?: "Module imported"
        }
    }
    val bb = curBible
    if (bb == null) {
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
            Text("No Bible module yet.", fontSize = 20.sp)
            Button({ importer.launch(arrayOf("application/zip", "application/octet-stream")) },
                Modifier.padding(top = 16.dp)) { Text("Import a Sword module (.zip)") }
            message?.let { Text(it, Modifier.padding(top = 12.dp)) }
        }
        return
    }
    val bible = bb
    val b = bible.books[book - 1]
    val view = remember(bible, book, chap, showFoot, showXref, look, dark, strongOn) { renderChapter(bible.chapter(book, chap), bible, showFoot, showXref, look, dark, strongOn) }
    LaunchedEffect(book, chap) { scroll.scrollTo(0) }
    // a jump to a verse: once this chapter's text has been laid out, scroll the verse to the top
    LaunchedEffect(view, layout, targetVerse) {
        val l = layout
        if (targetVerse > 0 && l != null && l.layoutInput.text.text == view.text.text) {
            val off = view.verseOffsets[targetVerse]
            if (off != null) {
                val o = off.coerceAtMost(view.text.length)
                val line = l.getLineForOffset(o)
                scroll.scrollTo(l.getLineTop(line).toInt())
            }
            targetVerse = 0
        }
    }
    // coming back to a tab: restore where it was scrolled to
    LaunchedEffect(view, layout, pendingScroll) {
        val l = layout
        if (pendingScroll >= 0 && l != null && l.layoutInput.text.text == view.text.text) {
            scroll.scrollTo(pendingScroll)
            pendingScroll = -1
        }
    }
    fun tabTitle(i: Int): String {
        val t = if (i == active) Tab(curModule, book, chap) else tabs[i]
        val label = mods.firstOrNull { it.name == t.module }?.label ?: t.module
        val ab = bibleFor(t.module)?.books?.getOrNull(t.book - 1)?.abbrev ?: "?"
        return "$label $ab ${t.chap}"
    }

    fun go(bk: Int, ch: Int, v: Int = 0) { book = bk; chap = ch; targetVerse = v }
    fun next() {
        if (chap < b.chapters) chap++
        else if (book < bible.books.size) { book++; chap = 1 }
    }
    fun prev() {
        if (chap > 1) chap--
        else if (book > 1) { book--; chap = bible.books[book - 1].chapters }
    }

    Scaffold(
        topBar = {
          Column {
            TopAppBar(
                title = { Text("${b.name} $chap", Modifier.clickable { picking = true }) },
                actions = {
                    TextButton({ searching = true }) { Text("Search") }
                    Box {
                        TextButton({ viewMenu = true }) { Text("View") }
                        androidx.compose.material3.DropdownMenu(viewMenu, { viewMenu = false }) {
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text((if (showFoot) "\u2713 " else "    ") + "Footnotes") },
                                onClick = { showFoot = !showFoot; prefs.edit().putBoolean("foot", showFoot).apply() })
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text((if (showXref) "\u2713 " else "    ") + "Cross references") },
                                onClick = { showXref = !showXref; prefs.edit().putBoolean("xref", showXref).apply() })
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text((if (strongOn) "\u2713 " else "    ") + "Strong's (tap a word)") },
                                onClick = { strongOn = !strongOn; prefs.edit().putBoolean("strong", strongOn).apply() })
                            HorizontalDivider()
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text("New tab") }, onClick = { viewMenu = false; newTab(book, chap) })
                            if (closedTabs.isNotEmpty()) androidx.compose.material3.DropdownMenuItem(
                                text = { Text("Reopen closed tab") }, onClick = { viewMenu = false; reopenTab() })
                            HorizontalDivider()
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text("Settings…") }, onClick = { viewMenu = false; settings = true })
                        }
                    }
                },
            )
            if (tabs.size > 1) TabBar(tabs.indices.map { tabTitle(it) }, active, tabBarState,
                { activate(it) }, { closeTab(it) }, { newTab(book, chap) })
          }
        },
        bottomBar = {
            Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                OutlinedButton({ prev() }) { Text("< Previous", maxLines = 1, softWrap = false) }
                TextButton({ modPicker = true }, Modifier.weight(1f)) {
                    Text(bible.name.take(12), maxLines = 1)
                }
                OutlinedButton({ next() }) { Text("Next >", maxLines = 1, softWrap = false) }
            }
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(scroll).padding(horizontal = 18.dp, vertical = 8.dp)) {
            Text(view.text, fontFamily = if (look.serif) FontFamily.Serif else FontFamily.SansSerif, lineHeight = (look.fontSize * look.lineFactor).sp,
                onTextLayout = { layout = it },
                modifier = Modifier.pointerInput(view) {
                    detectTapGestures { pos ->
                        val l = layout ?: return@detectTapGestures
                        val off = l.getOffsetForPosition(pos)
                        // the marker is small: accept a tap on it or right next to it
                        val hit = (off - 2..off + 1).firstNotNullOfOrNull { o ->
                            view.text.getStringAnnotations("note", o.coerceAtLeast(0), (o + 1).coerceAtMost(view.text.length)).firstOrNull()
                        }
                        if (hit != null) openNote = view.notes[hit.item.toInt()]
                        else {
                            val w = view.text.getStringAnnotations("strong", off, (off + 1).coerceAtMost(view.text.length)).firstOrNull()
                            if (w != null) openStrong = w.item to view.text.text.substring(w.start, w.end).trim()
                        }
                    }
                })
        }
    }
    openStrong?.let { (nums, word) -> StrongsDialog(lexicons, store, nums, word) { openStrong = null } }
    if (settings) SettingsDialog(look, dark, onLook) { settings = false }
    if (downloading) DownloadScreen(store, { downloading = false }) { mods = store.list(); lexicons.reset() }
    openNote?.let { n ->
        NoteDialog(bible, n, { openNote = null }) { bk, ch, v, nt -> openNote = null; if (nt) newTab(bk, ch, v) else go(bk, ch, v) }
    }
    if (modPicker) ModulePicker(mods, bible.name, { modPicker = false }, { modPicker = false; downloading = true },
        { modPicker = false; importer.launch(arrayOf("application/zip", "application/octet-stream")) }) {
        modPicker = false; openModule(it)
    }
    message?.let { m ->
        androidx.compose.material3.AlertDialog(onDismissRequest = { message = null },
            confirmButton = { TextButton({ message = null }) { Text("OK") } }, text = { Text(m) })
    }
    if (picking) Picker(bible, { picking = false }) { bk, ch, v -> go(bk, ch, v); picking = false }
    if (searching) SearchScreen(bible, { searching = false }) { bk, ch, v, nt -> searching = false; if (nt) newTab(bk, ch, v) else go(bk, ch, v) }
}

@Composable
fun Picker(bible: Bible, onClose: () -> Unit, onPick: (Int, Int, Int) -> Unit) {
    var chosen by remember { mutableStateOf<Book?>(null) }
    var ref by remember { mutableStateOf("") }
    androidx.compose.ui.window.Dialog(onClose, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp)) {
                val c = chosen
                if (c == null) {
                    OutlinedTextField(ref, { ref = it }, Modifier.fillMaxWidth(), label = { Text("Go to (John 3:16)") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = {
                            bible.find(ref)?.let { (bk, ch, v) -> onPick(bk, ch, if (ref.contains(':') || ref.contains('.')) v else 0) }
                        }))
                    LazyVerticalGrid(GridCells.Fixed(4), Modifier.weight(1f)) {
                        items(bible.books) { k ->
                            Box(Modifier.fillMaxWidth().clickable {
                                if (k.chapters == 1) onPick(k.number, 1, 0) else chosen = k
                            }.padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                                Text(k.abbrev.ifBlank { k.name }, fontSize = 16.sp, maxLines = 1)
                            }
                        }
                    }
                } else {
                    Text(c.name, fontSize = 20.sp, modifier = Modifier.padding(bottom = 8.dp))
                    LazyVerticalGrid(GridCells.Adaptive(56.dp), Modifier.weight(1f),
                        contentPadding = PaddingValues(4.dp)) {
                        items((1..c.chapters).toList()) { n ->
                            Box(Modifier.clickable { onPick(c.number, n, 0) }.padding(vertical = 14.dp).fillMaxWidth(),
                                contentAlignment = Alignment.Center) { Text("$n", fontSize = 20.sp) }
                        }
                    }
                    TextButton({ chosen = null }) { Text("Back to books") }
                }
                TextButton(onClose) { Text("Cancel") }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SearchScreen(bible: Bible, onClose: () -> Unit, onPick: (Int, Int, Int, Boolean) -> Unit) {
    var query by remember { mutableStateOf("") }
    var scope by remember { mutableIntStateOf(0) }
    var hits by remember { mutableStateOf<List<Hit>?>(null) }
    var run by remember { mutableIntStateOf(0) }
    LaunchedEffect(run) {
        if (run > 0 && query.isNotBlank()) {
            hits = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                bible.search(query.trim(), scope)
            }
        }
    }
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.compose.ui.window.Dialog(onClose, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        LaunchedEffect(Unit) { focus.requestFocus() }
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp)) {
                OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().focusRequester(focus), label = { Text("Search") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { hits = null; run++ }))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 8.dp)) {
                    listOf("Whole Bible", "OT", "NT").forEachIndexed { i, s ->
                        if (i == scope) Button({ scope = i }) { Text(s) } else OutlinedButton({ scope = i }) { Text(s) }
                    }
                }
                val h = hits
                if (run > 0 && h == null) Text("Searching…")
                if (h != null) {
                    Text("${h.size}${if (h.size >= 300) "+" else ""} verses")
                    LazyColumn(Modifier.weight(1f)) {
                        items(h) { x ->
                            Column(Modifier.fillMaxWidth().combinedClickable(
                                onClick = { onPick(x.book, x.chapter, x.verse, false) },
                                onLongClick = { onPick(x.book, x.chapter, x.verse, true) }).padding(vertical = 8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text("${bible.bookName(x.book)} ${x.chapter}:${x.verse}", Modifier.weight(1f),
                                        fontSize = 14.sp, color = MaterialTheme.colorScheme.primary)
                                    TextButton({ onPick(x.book, x.chapter, x.verse, true) }) { Text("New tab", fontSize = 13.sp) }
                                }
                                Text(x.text, fontSize = 16.sp, maxLines = 3)
                            }
                            HorizontalDivider()
                        }
                    }
                } else Box(Modifier.weight(1f))
                TextButton(onClose) { Text("Close") }
            }
        }
    }
}

@Composable
fun ModulePicker(mods: List<ModInfo>, current: String, onClose: () -> Unit, onDownload: () -> Unit, onImport: () -> Unit, onPick: (ModInfo) -> Unit) {
    androidx.compose.ui.window.Dialog(onClose, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp)) {
                Text("Bible modules", fontSize = 20.sp, modifier = Modifier.padding(bottom = 8.dp))
                LazyColumn(Modifier.weight(1f)) {
                    items(mods) { m ->
                        Column(Modifier.fillMaxWidth().clickable { onPick(m) }.padding(vertical = 10.dp)) {
                            Text(m.label + if (m.label == current) "  (open)" else "", fontSize = 18.sp,
                                color = if (m.label == current) MaterialTheme.colorScheme.primary else Color.Unspecified)
                            Text(m.description, fontSize = 14.sp, maxLines = 2)
                        }
                        HorizontalDivider()
                    }
                }
                Button(onDownload, Modifier.fillMaxWidth().padding(top = 8.dp)) { Text("Download modules…") }
                OutlinedButton(onImport, Modifier.fillMaxWidth()) { Text("Import a Sword module (.zip)") }
                TextButton(onClose) { Text("Close") }
            }
        }
    }
}

@Composable
fun NoteDialog(bible: Bible, note: NoteItem, onClose: () -> Unit, onGo: (Int, Int, Int, Boolean) -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onClose,
        confirmButton = { TextButton(onClose) { Text("Close") } },
        title = { Text(if (note.crossRef) "Cross references, verse ${note.verse}" else "Note, verse ${note.verse}", fontSize = 18.sp) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (!note.crossRef && note.text.isNotEmpty()) Text(note.text, fontSize = 16.sp)
                for (r in note.refs) {
                    Column(Modifier.fillMaxWidth().clickable(enabled = r.book > 0) { onGo(r.book, r.chapter, r.verse, false) }.padding(vertical = 8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(r.label, Modifier.weight(1f), fontSize = 15.sp, color = MaterialTheme.colorScheme.primary)
                            if (r.book > 0) TextButton({ onGo(r.book, r.chapter, r.verse, true) }) { Text("New tab", fontSize = 13.sp) }
                        }
                        if (r.book > 0) Text(bible.verseText(r.book, r.chapter, r.verse), fontSize = 14.sp, maxLines = 4)
                    }
                    HorizontalDivider()
                }
                if (note.crossRef && note.refs.isEmpty()) Text(note.text)
            }
        },
    )
}

@Composable
fun DownloadScreen(store: ModuleStore, onClose: () -> Unit, onInstalled: () -> Unit) {
    var repo by remember { mutableStateOf(DEFAULT_REPOS[0]) }
    var items by remember { mutableStateOf<List<RepoItem>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var lang by remember { mutableStateOf("") }          // "" = all languages
    var repoMenu by remember { mutableStateOf(false) }
    var langMenu by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf<String?>(null) }
    var installedTick by remember { mutableIntStateOf(0) }
    var status by remember { mutableStateOf<String?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    LaunchedEffect(repo) {
        items = null; error = null
        try {
            items = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { RepoClient.list(repo) }
        } catch (e: Exception) { error = e.message ?: "Cannot read the repository" }
    }
    fun install(it: RepoItem) {
        scope.launch {
            busy = "Downloading ${it.id}…"; status = null
            try {
                val err = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    val zip = RepoClient.download(repo, it.id) { n, t ->
                        busy = "Downloading ${it.id}… " + (if (t > 0) "${n * 100 / t}%" else "${n / 1024} KB")
                    }
                    store.importStream(zip.inputStream())
                }
                status = err ?: "${it.id} installed"
                if (err == null) { installedTick++; onInstalled() }
            } catch (e: Exception) { status = e.message ?: "Download failed" }
            busy = null
        }
    }

    androidx.compose.ui.window.Dialog(onClose, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp)) {
                Text("Download modules", fontSize = 20.sp)
                Box {
                    OutlinedButton({ repoMenu = true }, Modifier.fillMaxWidth()) { Text(repo.name, maxLines = 1) }
                    androidx.compose.material3.DropdownMenu(repoMenu, { repoMenu = false }) {
                        DEFAULT_REPOS.forEach { r ->
                            androidx.compose.material3.DropdownMenuItem(text = { Text(r.name) },
                                onClick = { repo = r; repoMenu = false; lang = "" })
                        }
                    }
                }
                val all = items
                if (all != null) {
                    val langs = remember(all) { all.map { it.language }.distinct().sorted() }
                    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.weight(1f)) {
                            OutlinedButton({ langMenu = true }, Modifier.fillMaxWidth()) { Text(if (lang.isEmpty()) "All languages" else lang, maxLines = 1) }
                            androidx.compose.material3.DropdownMenu(langMenu, { langMenu = false }) {
                                androidx.compose.material3.DropdownMenuItem(text = { Text("All languages") }, onClick = { lang = ""; langMenu = false })
                                langs.forEach { l ->
                                    androidx.compose.material3.DropdownMenuItem(text = { Text(l) }, onClick = { lang = l; langMenu = false })
                                }
                            }
                        }
                    }
                    OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(top = 4.dp),
                        label = { Text("Filter by name") }, singleLine = true)
                    val shown = all.filter { (lang.isEmpty() || it.language == lang) &&
                        (query.isBlank() || it.id.contains(query, true) || it.description.contains(query, true)) }
                    Text("${shown.size} of ${all.size} modules", fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                    LazyColumn(Modifier.weight(1f)) {
                        items(shown) { m ->
                            val inst = remember(installedTick, m) { store.isInstalled(m.id) }
                            Column(Modifier.fillMaxWidth().clickable(enabled = busy == null && !inst) { install(m) }.padding(vertical = 8.dp)) {
                                Text(m.id + (if (inst) "  (installed)" else ""), fontSize = 17.sp,
                                    color = if (inst) MaterialTheme.colorScheme.primary else Color.Unspecified)
                                Text(m.description + " · " + (if (m.lexicon) "Strong's / lexicon" else m.language), fontSize = 13.sp, maxLines = 2)
                            }
                            HorizontalDivider()
                        }
                    }
                } else {
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Text(error ?: "Loading the list…", color = if (error != null) MaterialTheme.colorScheme.error else Color.Unspecified)
                    }
                }
                busy?.let { Text(it, Modifier.padding(vertical = 4.dp)) }
                status?.let { Text(it, Modifier.padding(vertical = 4.dp)) }
                Text("Tap a module to install it.", fontSize = 12.sp)
                TextButton(onClose) { Text("Close") }
            }
        }
    }
}

@Composable
fun SettingsDialog(look: Look, dark: Boolean, onLook: (Look) -> Unit, onClose: () -> Unit) {
    androidx.compose.ui.window.Dialog(onClose, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp).verticalScroll(rememberScrollState())) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Settings", fontSize = 20.sp, modifier = Modifier.weight(1f))
                    TextButton(onClose) { Text("Done") }
                }
                Text("Text size  ${look.fontSize.toInt()}", Modifier.padding(top = 12.dp))
                androidx.compose.material3.Slider(look.fontSize, { onLook(look.copy(fontSize = Math.round(it).toFloat())) },
                    valueRange = 12f..32f)
                Text("Line spacing  ${"%.2f".format(look.lineFactor)}")
                androidx.compose.material3.Slider(look.lineFactor, { onLook(look.copy(lineFactor = Math.round(it * 20f) / 20f)) },
                    valueRange = 1.1f..2.1f)
                Text("Font", Modifier.padding(top = 4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("Serif" to true, "Sans" to false).forEach { (n, v) ->
                        if (look.serif == v) Button({ }) { Text(n) } else OutlinedButton({ onLook(look.copy(serif = v)) }) { Text(n) }
                    }
                }
                Text("Theme", Modifier.padding(top = 12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("System" to 0, "Light" to 1, "Dark" to 2).forEach { (n, v) ->
                        if (look.theme == v) Button({ }) { Text(n) } else OutlinedButton({ onLook(look.copy(theme = v)) }) { Text(n) }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Words of Jesus in red", Modifier.weight(1f))
                    androidx.compose.material3.Switch(look.redLetters, { onLook(look.copy(redLetters = it)) })
                }
                HorizontalDivider(Modifier.padding(vertical = 12.dp))
                Text(buildAnnotatedString {
                    withStyle(SpanStyle(fontSize = (look.fontSize * 0.62f).sp, baselineShift = androidx.compose.ui.text.style.BaselineShift.Superscript)) { append("16") }
                    append("\u2009For God so loved the world, that he gave his only Son, ")
                    withStyle(SpanStyle(color = if (look.redLetters) (if (dark) Color(0xFFFF8A80) else Color(0xFFB3261E)) else Color.Unspecified)) {
                        append("that whoever believes in him should not perish but have eternal life.")
                    }
                }, fontSize = look.fontSize.sp, lineHeight = (look.fontSize * look.lineFactor).sp,
                    fontFamily = if (look.serif) FontFamily.Serif else FontFamily.SansSerif)
            }
        }
    }
}

@Composable
fun StrongsDialog(lex: Lexicons, store: ModuleStore, numbers: String, word: String, onClose: () -> Unit) {
    var tick by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf<String?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val keys = numbers.split(' ').filter { it.isNotBlank() }
    val entries = remember(numbers, tick) { keys.map { it to lex.entry(it) } }
    val missing = entries.any { it.second == null }

    fun fetch() {
        scope.launch {
            try {
                for (id in listOf("StrongsGreek", "StrongsHebrew")) {
                    if (store.lexiconConf(if (id.endsWith("Greek")) "GreekDef" else "HebrewDef") != null) continue
                    busy = "Downloading $id…"
                    val err = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        store.importStream(RepoClient.download(DEFAULT_REPOS[0], id) { _, _ -> }.inputStream())
                    }
                    if (err != null) { busy = err; return@launch }
                }
                lex.reset(); tick++; busy = null
            } catch (e: Exception) { busy = e.message ?: "Download failed" }
        }
    }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onClose,
        confirmButton = { TextButton(onClose) { Text("Close") } },
        title = { Text("$numbers   $word", fontSize = 18.sp) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                for ((k, e) in entries) {
                    if (keys.size > 1) Text(k, color = MaterialTheme.colorScheme.primary, fontSize = 15.sp)
                    when {
                        e == null -> Text("No Strong's ${if (k.firstOrNull()?.uppercaseChar() == 'G') "Greek" else "Hebrew"} dictionary is installed.")
                        e.isEmpty() -> Text("No entry for $k in this dictionary.")
                        else -> Text(e, fontSize = 15.sp)
                    }
                    HorizontalDivider(Modifier.padding(vertical = 8.dp))
                }
                if (missing) {
                    Button({ fetch() }, enabled = busy == null || busy!!.startsWith("Cannot") || busy!!.contains("fail", true),
                        modifier = Modifier.fillMaxWidth()) { Text("Download Strong's dictionaries") }
                }
                busy?.let { Text(it, Modifier.padding(top = 8.dp)) }
            }
        },
    )
}
