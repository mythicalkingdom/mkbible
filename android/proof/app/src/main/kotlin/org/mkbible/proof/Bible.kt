package org.mkbible.proof

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.unit.sp

class Book(val number: Int, val osis: String, val name: String, val abbrev: String, val chapters: Int)

class Hit(val book: Int, val chapter: Int, val verse: Int, val text: String)

/** One opened module. Calls into the native library are serialized, the module object is not thread safe. */
class Bible(val handle: Long) {
    val books: List<Book>
    val name: String
    val description: String

    init {
        val i = Native.info(handle).split('\t')
        name = i.getOrElse(0) { "" }
        description = i.getOrElse(1) { "" }
        books = Native.books(handle).lines().filter { it.isNotBlank() }.mapIndexed { n, l ->
            val f = l.split('\t')
            Book(n + 1, f[0], f[1], f[2], f[3].toInt())
        }
    }

    @Synchronized fun chapter(book: Int, chap: Int): String = Native.chapter(handle, book, chap)

    @Synchronized fun search(text: String, scope: Int, max: Int = 300): List<Hit> =
        Native.search(handle, text, scope, max).lines().filter { it.isNotBlank() }.map {
            val f = it.split('\t')
            Hit(f[0].toInt(), f[1].toInt(), f[2].toInt(), f.getOrElse(3) { "" })
        }

    @Synchronized fun find(ref: String): Triple<Int, Int, Int>? {
        val f = Native.find(handle, ref).split('\t')
        return if (f.size == 3) Triple(f[0].toInt(), f[1].toInt(), f[2].toInt()) else null
    }

    fun bookName(n: Int) = books.getOrNull(n - 1)?.name ?: "?"
}

private val JesusRed = Color(0xFFB3261E)

/** Turns the events of one chapter (see MkpToEvents) into styled text. */
fun renderChapter(src: String, showNotes: Boolean = false): AnnotatedString = buildAnnotatedString {
    var italic = 0; var bold = 0; var jesus = 0; var head = 0; var note = 0
    var atStart = true
    var needGap = false     // a paragraph break is pending
    var pendingNum: String? = null   // verse number waits for the first body text (a Psalm title comes first)
    fun style() = SpanStyle(
        fontStyle = if (italic > 0) FontStyle.Italic else null,
        fontWeight = if (bold > 0 || head > 0) FontWeight.Bold else null,
        color = if (jesus > 0) JesusRed else Color.Unspecified,
        fontSize = if (head > 0) 17.sp else 18.sp,
    )
    fun breakLine(double: Boolean) {
        if (atStart) return
        append(if (double) "\n\n" else "\n")
    }
    for (line in src.lineSequence()) {
        if (line.isEmpty()) continue
        val tab = line.indexOf('\t')
        val code = if (tab < 0) line else line.substring(0, tab)
        val arg = if (tab < 0) "" else line.substring(tab + 1)
        when (code) {
            "S" -> { if (!atStart) append("\n\n"); atStart = true }
            "V" -> {
                if (needGap) { breakLine(true); needGap = false }
                else if (!atStart) append(" ")
                pendingNum = arg
            }
            "T" -> if (note == 0 || showNotes) {
                if (needGap) { breakLine(true); needGap = false }
                if (head == 0 && pendingNum != null) {
                    withStyle(SpanStyle(fontSize = 11.sp, baselineShift = BaselineShift.Superscript,
                        color = Color(0xFF6B5B3E), fontWeight = FontWeight.Bold)) { append(pendingNum!!) }
                    append("\u2009")
                    pendingNum = null
                }
                withStyle(style()) { append(arg) }
                atStart = false
            }
            "P" -> if (!atStart) needGap = true
            "L" -> if (!atStart && note == 0) append("\n")
            "I+" -> italic++
            "I-" -> if (italic > 0) italic--
            "B+" -> bold++
            "B-" -> if (bold > 0) bold--
            "J+" -> jesus++
            "J-" -> if (jesus > 0) jesus--
            "N+" -> note++
            "N-" -> if (note > 0) note--
            "H+" -> { head++; if (!atStart) append("\n\n"); atStart = true }
            "H-" -> { if (head > 0) head--; append("\n"); atStart = true; needGap = false }
        }
    }
}
