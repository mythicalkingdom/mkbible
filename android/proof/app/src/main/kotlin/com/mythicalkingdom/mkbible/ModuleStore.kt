package com.mythicalkingdom.mkbible

import android.content.ContentResolver
import android.net.Uri
import java.io.File
import java.util.zip.ZipInputStream

/** [name] is the module id (the conf section); [label] is what the app shows: the Abbreviation from the conf when it has one. */
class ModInfo(val name: String, val description: String, val conf: String, val label: String = name)

/** The Sword module folder inside the app's own storage (filesDir/sword: mods.d + modules). */
class ModuleStore(private val root: File) {
    val confDir get() = File(root, "mods.d")

    /** Installed Bible modules, sorted by name. Commentaries, dictionaries and the like are not supported yet. */
    fun list(): List<ModInfo> =
        (confDir.listFiles { f -> f.name.endsWith(".conf") } ?: emptyArray()).mapNotNull { f ->
            var name = ""; var desc = ""; var drv = ""; var abbr = ""
            for (line in f.readLines()) {
                if (line.startsWith("[")) name = line.trim('[', ']', ' ', '\r')
                else if (line.startsWith("Description=")) desc = line.substringAfter('=').trim()
                else if (line.startsWith("Abbreviation=")) abbr = line.substringAfter('=').trim()
                else if (line.startsWith("ModDrv=")) drv = line.substringAfter('=').trim()
            }
            if (name.isNotEmpty() && drv.contains("Text")) ModInfo(name, desc.ifEmpty { name }, f.path, abbr.ifEmpty { name }) else null
        }.sortedBy { it.name.lowercase() }

    /** Unpacks a Sword module zip (mods.d/x.conf and modules/...). Returns an error message or null. */
    fun importZip(cr: ContentResolver, uri: Uri): String? {
        val raw = try { cr.openInputStream(uri) } catch (e: Exception) { null } ?: return "Cannot read that file"
        return importStream(raw)
    }

    fun isInstalled(id: String) = File(confDir, id.lowercase() + ".conf").exists() || File(confDir, "$id.conf").exists()

    fun importStream(raw: java.io.InputStream): String? {
        var files = 0
        try {
            raw.use { raw ->
                ZipInputStream(raw).use { z ->
                    while (true) {
                        val e = z.nextEntry ?: break
                        val n = e.name.replace('\\', '/').trimStart('/')
                        if (e.isDirectory || !(n.startsWith("mods.d/") || n.startsWith("modules/"))) continue
                        val dest = File(root, n)
                        if (!dest.canonicalPath.startsWith(root.canonicalPath + File.separator)) return "Unsafe path in zip: $n"
                        dest.parentFile?.mkdirs()
                        dest.outputStream().use { o -> z.copyTo(o) }
                        files++
                    }
                }
            }
        } catch (e: Exception) {
            return "Import failed: ${e.message}"
        }
        return if (files == 0) "No Sword module found in that zip (it needs mods.d/ and modules/)" else null
    }

    /** The .conf of an installed dictionary with Feature=GreekDef or HebrewDef (StrongsGreek / StrongsHebrew first). */
    fun lexiconConf(feature: String): String? {
        val confs = (confDir.listFiles { f -> f.name.endsWith(".conf") } ?: emptyArray())
            .filter { f -> f.readText().replace(" ", "").contains("Feature=$feature", true) }
        val wanted = if (feature == "GreekDef") "strongsgreek" else "strongshebrew"
        return (confs.firstOrNull { it.name.lowercase() == "$wanted.conf" } ?: confs.firstOrNull())?.path
    }
}

/** Strong's dictionaries, opened when first needed. A key like "G26" goes to the Greek one, "H7225" to the Hebrew one. */
class Lexicons(private val store: ModuleStore) {
    private val handles = HashMap<String, Long>()

    @Synchronized fun reset() { handles.values.forEach { if (it != 0L) Native.dictClose(it) }; handles.clear() }

    /** Entry text, or null when no dictionary is installed for that language. Empty string: not in the dictionary. */
    @Synchronized fun entry(key: String): String? {
        val feature = if (key.firstOrNull()?.uppercaseChar() == 'G') "GreekDef" else "HebrewDef"
        val h = handles.getOrPut(feature) { store.lexiconConf(feature)?.let { Native.dictOpen(it) } ?: 0L }
        return if (h == 0L) null else Native.dictEntry(h, key)
    }
}
