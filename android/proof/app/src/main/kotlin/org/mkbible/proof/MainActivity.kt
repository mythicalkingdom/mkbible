package org.mkbible.proof

import android.os.Bundle
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusRequester
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
        val bible = Bible(Native.open(File(root, "mods.d/engwebu2024eb.conf").path).also {
            check(it != 0L) { "cannot open the module" }
        })
        setContent { MaterialTheme { Surface(Modifier.fillMaxSize()) { Reader(bible) } } }
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
fun Reader(bible: Bible) {
    var book by remember { mutableIntStateOf(43) }          // John
    var chap by remember { mutableIntStateOf(3) }
    var picking by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val b = bible.books[book - 1]
    val text = remember(book, chap) { renderChapter(bible.chapter(book, chap)) }
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
                },
            )
        },
        bottomBar = {
            Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                OutlinedButton({ prev() }) { Text("< Previous", maxLines = 1, softWrap = false) }
                Text(bible.name.take(12), Modifier.weight(1f).align(Alignment.CenterVertically), maxLines = 1,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                OutlinedButton({ next() }) { Text("Next >", maxLines = 1, softWrap = false) }
            }
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize().verticalScroll(scroll).padding(horizontal = 18.dp, vertical = 8.dp)) {
            Text(text, fontFamily = FontFamily.Serif, lineHeight = 28.sp)
        }
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
