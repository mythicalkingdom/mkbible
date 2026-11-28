package org.mkbible.proof

import android.content.SharedPreferences
import android.os.Bundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.Composable
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
        copyAssets("sword", root)
        val store = ModuleStore(root)
        val prefs = getSharedPreferences("mkbible", MODE_PRIVATE)
        setContent { MaterialTheme { Surface(Modifier.fillMaxSize()) { Reader(store, prefs) } } }
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
fun Reader(store: ModuleStore, prefs: SharedPreferences) {
    val context = LocalContext.current
    var mods by remember { mutableStateOf(store.list()) }
    var curBible by remember { mutableStateOf<Bible?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var book by remember { mutableIntStateOf(prefs.getInt("book", 43)) }          // John
    var chap by remember { mutableIntStateOf(prefs.getInt("chap", 3)) }
    var modPicker by remember { mutableStateOf(false) }
    var showFoot by remember { mutableStateOf(prefs.getBoolean("foot", true)) }
    var showXref by remember { mutableStateOf(prefs.getBoolean("xref", true)) }
    var viewMenu by remember { mutableStateOf(false) }
    var openNote by remember { mutableStateOf<NoteItem?>(null) }
    var downloading by remember { mutableStateOf(false) }

    fun openModule(m: ModInfo) {
        val h = Native.open(m.conf)
        if (h == 0L) { message = "Cannot open ${m.name}"; return }
        curBible?.let { Native.close(it.handle) }
        val nb = Bible(h)
        if (book > nb.books.size) { book = 1; chap = 1 }
        curBible = nb
        prefs.edit().putString("module", m.name).apply()
    }
    if (curBible == null) {
        val want = prefs.getString("module", null)
        (mods.firstOrNull { it.name == want } ?: mods.firstOrNull())?.let { openModule(it) }
    }
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
    LaunchedEffect(book, chap) { prefs.edit().putInt("book", book).putInt("chap", chap).apply() }
    var picking by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val b = bible.books[book - 1]
    val view = remember(bible, book, chap, showFoot, showXref) { renderChapter(bible.chapter(book, chap), bible, showFoot, showXref) }
    LaunchedEffect(book, chap) { scroll.scrollTo(0) }

    fun go(bk: Int, ch: Int) { book = bk; chap = ch }
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
                        }
                    }
                },
            )
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
            var layout by remember { mutableStateOf<androidx.compose.ui.text.TextLayoutResult?>(null) }
            Text(view.text, fontFamily = FontFamily.Serif, lineHeight = 28.sp,
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
                    }
                })
        }
    }
    if (downloading) DownloadScreen(store, { downloading = false }) { mods = store.list() }
    openNote?.let { n ->
        NoteDialog(bible, n, { openNote = null }) { bk, ch -> openNote = null; go(bk, ch) }
    }
    if (modPicker) ModulePicker(mods, bible.name, { modPicker = false }, { modPicker = false; downloading = true },
        { modPicker = false; importer.launch(arrayOf("application/zip", "application/octet-stream")) }) {
        modPicker = false; openModule(it)
    }
    message?.let { m ->
        androidx.compose.material3.AlertDialog(onDismissRequest = { message = null },
            confirmButton = { TextButton({ message = null }) { Text("OK") } }, text = { Text(m) })
    }
    if (picking) Picker(bible, { picking = false }) { bk, ch -> go(bk, ch); picking = false }
    if (searching) SearchScreen(bible, { searching = false }) { bk, ch -> go(bk, ch); searching = false }
}

@Composable
fun Picker(bible: Bible, onClose: () -> Unit, onPick: (Int, Int) -> Unit) {
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
                            bible.find(ref)?.let { (bk, ch, _) -> onPick(bk, ch) }
                        }))
                    LazyColumn(Modifier.weight(1f)) {
                        items(bible.books) { k ->
                            Text(k.name, Modifier.fillMaxWidth().clickable {
                                if (k.chapters == 1) onPick(k.number, 1) else chosen = k
                            }.padding(vertical = 12.dp), fontSize = 18.sp)
                            HorizontalDivider()
                        }
                    }
                } else {
                    Text(c.name, fontSize = 20.sp, modifier = Modifier.padding(bottom = 8.dp))
                    LazyVerticalGrid(GridCells.Adaptive(56.dp), Modifier.weight(1f),
                        contentPadding = PaddingValues(4.dp)) {
                        items((1..c.chapters).toList()) { n ->
                            Box(Modifier.clickable { onPick(c.number, n) }.padding(vertical = 14.dp).fillMaxWidth(),
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

@Composable
fun SearchScreen(bible: Bible, onClose: () -> Unit, onPick: (Int, Int) -> Unit) {
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
                            Column(Modifier.fillMaxWidth().clickable { onPick(x.book, x.chapter) }.padding(vertical = 8.dp)) {
                                Text("${bible.bookName(x.book)} ${x.chapter}:${x.verse}",
                                    fontSize = 14.sp, color = MaterialTheme.colorScheme.primary)
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
                            Text(m.name + if (m.name == current) "  (open)" else "", fontSize = 18.sp,
                                color = if (m.name == current) MaterialTheme.colorScheme.primary else Color.Unspecified)
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
fun NoteDialog(bible: Bible, note: NoteItem, onClose: () -> Unit, onGo: (Int, Int) -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onClose,
        confirmButton = { TextButton(onClose) { Text("Close") } },
        title = { Text(if (note.crossRef) "Cross references, verse ${note.verse}" else "Note, verse ${note.verse}", fontSize = 18.sp) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (!note.crossRef && note.text.isNotEmpty()) Text(note.text, fontSize = 16.sp)
                for (r in note.refs) {
                    Column(Modifier.fillMaxWidth().clickable(enabled = r.book > 0) { onGo(r.book, r.chapter) }.padding(vertical = 8.dp)) {
                        Text(r.label, fontSize = 15.sp, color = MaterialTheme.colorScheme.primary)
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
                                Text(m.description + " · " + m.language, fontSize = 13.sp, maxLines = 2)
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
