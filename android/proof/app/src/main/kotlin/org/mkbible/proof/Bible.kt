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

/** A cross reference inside a note: the text as printed and the first verse it points to (0 = unparsed). */
class RefLink(val label: String, val book: Int, val chapter: Int, val verse: Int)

/** A footnote or cross reference note of a chapter. */
class NoteItem(val verse: Int, val crossRef: Boolean, val text: String, val refs: List<RefLink>)

class ChapterView(val text: AnnotatedString, val notes: List<NoteItem>, val verseOffsets: Map<Int, Int>)

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

    /** "John.3.16", "Gen.1.1-Gen.1.3" or "Ps.23" (first verse) as book / chapter / verse, null if unknown. */
    fun parseOsis(r: String): Triple<Int, Int, Int>? {
        val f = r.substringBefore('-').split('.')
        if (f.size < 2) return null
        val bk = books.firstOrNull { it.osis.equals(f[0], true) } ?: return null
        val ch = f[1].toIntOrNull() ?: return null
        return Triple(bk.number, ch, f.getOrNull(2)?.toIntOrNull() ?: 1)
    }

    @Synchronized fun verseText(book: Int, chap: Int, verse: Int): String = Native.verseText(handle, book, chap, verse)

    fun bookName(n: Int) = books.getOrNull(n - 1)?.name ?: "?"
}


/** Turns the events of one chapter (see MkpToEvents) into styled text, with a tappable marker for each note. */
fun renderChapter(src: String, bible: Bible, showFoot: Boolean, showXref: Boolean, look: Look, dark: Boolean, strongOn: Boolean = true): ChapterView {
    val base = look.fontSize
    val jesusRed = if (dark) Color(0xFFFF8A80) else Color(0xFFB3261E)
    val numColor = if (dark) Color(0xFFC8B88A) else Color(0xFF6B5B3E)
    val xrefColor = if (dark) Color(0xFF7FB8E6) else Color(0xFF2E6F9E)
    val footColor = if (dark) Color(0xFFE0B050) else Color(0xFF8A5A00)
    val notes = ArrayList<NoteItem>()
    val offsets = HashMap<Int, Int>()
    val text = buildAnnotatedString {
        var italic = 0; var bold = 0; var jesus = 0; var head = 0
        var inNote = false; var noteX = false; var nb = StringBuilder(); var nrefs = ArrayList<RefLink>()
        var refOsis: String? = null; var refLabel = StringBuilder()
        var strong = 0   // number of annotations pushed for the current word (0 or 1)
        var verse = 0
        var atStart = true
        var needGap = false
        var pendingNum: String? = null
        fun style() = SpanStyle(
            fontStyle = if (italic > 0) FontStyle.Italic else null,
            fontWeight = if (bold > 0 || head > 0) FontWeight.Bold else null,
            color = if (jesus > 0 && look.redLetters) jesusRed else Color.Unspecified,
            fontSize = (if (head > 0) base - 1f else base).sp,
        )
        fun gap() { if (needGap) { if (!atStart) append("\n\n"); needGap = false } }
        for (line in src.lineSequence()) {
            if (line.isEmpty()) continue
            val tab = line.indexOf('\t')
            val code = if (tab < 0) line else line.substring(0, tab)
            val arg = if (tab < 0) "" else line.substring(tab + 1)
            if (inNote) {
                when (code) {
                    "T" -> { nb.append(arg); if (refOsis != null) refLabel.append(arg) }
                    "X+" -> { refOsis = arg; refLabel = StringBuilder() }
                    "X-" -> {
                        val o = refOsis
                        if (o != null) {
                            val p = bible.parseOsis(o)
                            nrefs.add(RefLink(refLabel.toString().trim().ifEmpty { o }, p?.first ?: 0, p?.second ?: 0, p?.third ?: 0))
                        }
                        refOsis = null
                    }
                    "N-" -> {
                        inNote = false
                        if (if (noteX) showXref else showFoot) {
                            val id = notes.size
                            notes.add(NoteItem(verse, noteX, nb.toString().trim(), nrefs))
                            pushStringAnnotation("note", id.toString())
                            withStyle(SpanStyle(fontSize = (base * 0.67f).sp, baselineShift = BaselineShift.Superscript,
                                color = if (noteX) xrefColor else footColor, fontWeight = FontWeight.Bold)) {
                                append(if (noteX) "\u2009*\u2009" else "\u2009\u2020\u2009")
                            }
                            pop()
                        }
                    }
                }
                continue
            }
            when (code) {
                "S" -> { if (!atStart) append("\n\n"); atStart = true }
                "V" -> {
                    gap()
                    if (!atStart) append(" ")
                    pendingNum = arg
                    verse = arg.toIntOrNull() ?: verse
                    offsets[verse] = length
                }
                "T" -> {
                    gap()
                    if (head == 0 && pendingNum != null) {
                        withStyle(SpanStyle(fontSize = (base * 0.62f).sp, baselineShift = BaselineShift.Superscript,
                            color = numColor, fontWeight = FontWeight.Bold)) { append(pendingNum!!) }
                        append("\u2009")
                        pendingNum = null
                    }
                    withStyle(style()) { append(arg) }
                    atStart = false
                }
                "P" -> if (!atStart) needGap = true
                "L" -> if (!atStart) append("\n")
                "W+" -> if (arg.isNotBlank() && strongOn) { pushStringAnnotation("strong", arg); strong = 1 }
                "W-" -> if (strong > 0) { pop(); strong = 0 }
                "I+" -> italic++
                "I-" -> if (italic > 0) italic--
                "B+" -> bold++
                "B-" -> if (bold > 0) bold--
                "J+" -> jesus++
                "J-" -> if (jesus > 0) jesus--
                "N+" -> { inNote = true; noteX = arg == "1"; nb = StringBuilder(); nrefs = ArrayList(); refOsis = null }
                "H+" -> { head++; if (!atStart) append("\n\n"); atStart = true }
                "H-" -> { if (head > 0) head--; append("\n"); atStart = true; needGap = false }
            }
        }
    }
    return ChapterView(text, notes, offsets)
}
