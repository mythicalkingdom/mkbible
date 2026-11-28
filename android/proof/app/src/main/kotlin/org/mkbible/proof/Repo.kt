package org.mkbible.proof

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.zip.GZIPInputStream

class Repo(val name: String, val url: String)

class RepoItem(val id: String, val description: String, val lang: String, val version: String) {
    val language: String get() = langName(lang)
}

/** The Sword repositories the desktop programs offer (same list as mkbiblerepo.pas). */
val DEFAULT_REPOS = listOf(
    Repo("CrossWire (main)", "https://www.crosswire.org/ftpmirror/pub/sword/raw"),
    Repo("CrossWire (beta)", "https://www.crosswire.org/ftpmirror/pub/sword/betaraw"),
    Repo("CrossWire (attic)", "https://www.crosswire.org/ftpmirror/pub/sword/atticraw"),
    Repo("CrossWire (Wycliffe)", "https://www.crosswire.org/ftpmirror/pub/sword/wyclifferaw"),
    Repo("CrossWire (Lockman: NASB, NBLA, LBLA)", "https://www.crosswire.org/ftpmirror/pub/sword/lockmanraw"),
    Repo("eBible.org", "https://ebible.org/sword"),
)

fun langName(code: String): String {
    if (code.isBlank()) return "Unknown"
    val base = code.substringBefore('-')
    val n = Locale.forLanguageTag(base).getDisplayLanguage(Locale.ENGLISH)
    return if (n.isNullOrBlank() || n.equals(base, true)) base.uppercase() else n
}

object RepoClient {
    private fun open(url: String): HttpURLConnection {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 30000
        c.readTimeout = 30000
        c.instanceFollowRedirects = true
        c.setRequestProperty("User-Agent", "mkbible-android")
        return c
    }

    /** Bytes of a URL; throws with a readable message. [onProgress] gets (bytes so far, total or -1). */
    fun get(url: String, onProgress: ((Long, Long) -> Unit)? = null): ByteArray {
        val c = open(url)
        try {
            if (c.responseCode != 200) throw RuntimeException("Server answered ${c.responseCode} for $url")
            val total = c.contentLengthLong
            val out = ByteArrayOutputStream()
            c.inputStream.use { i ->
                val buf = ByteArray(32768)
                var n: Int
                var sum = 0L
                while (i.read(buf).also { n = it } > 0) {
                    out.write(buf, 0, n); sum += n
                    onProgress?.invoke(sum, total)
                }
            }
            return out.toByteArray()
        } catch (e: java.io.IOException) {
            throw RuntimeException("Network problem: ${e.message}")
        } finally {
            c.disconnect()
        }
    }

    /** The Bible modules a repository offers (locked ones, commentaries, dictionaries and so on left out). */
    fun list(r: Repo): List<RepoItem> {
        val tar = GZIPInputStream(get(r.url + "/mods.d.tar.gz").inputStream()).use { it.readBytes() }
        val items = ArrayList<RepoItem>()
        var p = 0
        var longName: String? = null
        while (p + 512 <= tar.size) {
            if (tar[p].toInt() == 0) break
            val name = String(tar, p, 100, Charsets.ISO_8859_1).substringBefore('\u0000')
            val size = String(tar, p + 124, 12, Charsets.ISO_8859_1).trim('\u0000', ' ').ifEmpty { "0" }.toInt(8)
            val type = tar[p + 156].toInt().toChar()
            val data = p + 512
            if ((type == '0' || type == '\u0000') && (longName ?: name).endsWith(".conf")) {
                parseConf(String(tar, data, size, Charsets.UTF_8))?.let { items.add(it) }
            }
            longName = if (type == 'L') String(tar, data, size, Charsets.ISO_8859_1).trimEnd('\u0000') else null
            p = data + (size + 511) / 512 * 512
        }
        return items.sortedBy { it.id.lowercase() }
    }

    private fun parseConf(text: String): RepoItem? {
        var id = ""; var desc = ""; var lang = ""; var ver = ""; var drv = ""; var cat = ""
        var locked = false
        for (line in text.lineSequence()) {
            val l = line.trimEnd('\r')
            when {
                l.startsWith("[") && id.isEmpty() -> id = l.trim('[', ']', ' ')
                l.startsWith("Description=") -> desc = l.substringAfter('=').trim()
                l.startsWith("Lang=") -> lang = l.substringAfter('=').trim()
                l.startsWith("Version=") -> ver = l.substringAfter('=').trim()
                l.startsWith("ModDrv=") -> drv = l.substringAfter('=').trim()
                l.startsWith("Category=") -> cat = l.substringAfter('=').trim()
                l.startsWith("CipherKey=") -> locked = l.substringAfter('=').isBlank()
            }
        }
        if (id.isEmpty() || locked || !drv.contains("Text")) return null
        if (cat.isNotEmpty() && !cat.contains("Bible", true) && !cat.contains("Biblical", true)) return null
        return RepoItem(id, desc.ifEmpty { id }, lang, ver)
    }

    /** Downloads one module (packages/<id>.zip) and returns its bytes. */
    fun download(r: Repo, id: String, onProgress: (Long, Long) -> Unit): ByteArray =
        get(r.url + "/packages/" + id + ".zip", onProgress)
}
