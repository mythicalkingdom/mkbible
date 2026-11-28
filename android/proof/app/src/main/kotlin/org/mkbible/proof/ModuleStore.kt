package org.mkbible.proof

import android.content.ContentResolver
import android.net.Uri
import java.io.File
import java.util.zip.ZipInputStream

class ModInfo(val name: String, val description: String, val conf: String)

/** The Sword module folder inside the app's own storage (filesDir/sword: mods.d + modules). */
class ModuleStore(private val root: File) {
    val confDir get() = File(root, "mods.d")

    /** Installed Bible modules, sorted by name. Commentaries, dictionaries and the like are not supported yet. */
    fun list(): List<ModInfo> =
        (confDir.listFiles { f -> f.name.endsWith(".conf") } ?: emptyArray()).mapNotNull { f ->
            var name = ""; var desc = ""; var drv = ""
            for (line in f.readLines()) {
                if (line.startsWith("[")) name = line.trim('[', ']', ' ', '\r')
                else if (line.startsWith("Description=")) desc = line.substringAfter('=').trim()
                else if (line.startsWith("ModDrv=")) drv = line.substringAfter('=').trim()
            }
            if (name.isNotEmpty() && drv.contains("Text")) ModInfo(name, desc.ifEmpty { name }, f.path) else null
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
}
