package org.mkbible.proof

import android.content.SharedPreferences
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** One reading tab: a module (its id), a place, and where the text was scrolled to. */
data class Tab(val module: String, val book: Int, val chap: Int, val scroll: Int = 0)

fun saveTabs(p: SharedPreferences, tabs: List<Tab>, active: Int) {
    p.edit().putString("tabs", tabs.joinToString(";") { "${it.module}|${it.book}|${it.chap}|${it.scroll}" })
        .putInt("tabActive", active).apply()
}

/** The saved tabs; a first run (or an older version's single place) gives one tab. */
fun loadTabs(p: SharedPreferences): List<Tab> {
    val saved = p.getString("tabs", "")!!.split(';').mapNotNull { s ->
        val f = s.split('|')
        if (f.size == 4) f[1].toIntOrNull()?.let { b -> f[2].toIntOrNull()?.let { c -> Tab(f[0], b, c, f[3].toIntOrNull() ?: 0) } }
        else null
    }
    return saved.ifEmpty { listOf(Tab(p.getString("module", "engwebu2025eb")!!, p.getInt("book", 43), p.getInt("chap", 3))) }
}

@Composable
fun TabBar(titles: List<String>, active: Int, state: LazyListState, onPick: (Int) -> Unit, onClose: (Int) -> Unit, onNew: () -> Unit) {
    LazyRow(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), state = state,
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        itemsIndexed(titles) { i, t ->
            val on = i == active
            Surface(shape = RoundedCornerShape(16.dp),
                color = if (on) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceVariant) {
                Row(Modifier.clickable { onPick(i) }.padding(start = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(t, fontSize = 14.sp, maxLines = 1, modifier = Modifier.padding(vertical = 7.dp))
                    Text("×", fontSize = 18.sp, modifier = Modifier.clickable { onClose(i) }.padding(horizontal = 8.dp, vertical = 2.dp))
                }
            }
        }
        item {
            Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
                Text("+", fontSize = 18.sp, modifier = Modifier.clickable { onNew() }.padding(horizontal = 14.dp, vertical = 4.dp))
            }
        }
    }
}
