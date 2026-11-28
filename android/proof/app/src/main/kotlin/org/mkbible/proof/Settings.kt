package org.mkbible.proof

import android.content.SharedPreferences

/** How the text looks. theme: 0 follow the system, 1 light, 2 dark. */
data class Look(
    val fontSize: Float = 18f,
    val lineFactor: Float = 1.55f,
    val serif: Boolean = true,
    val theme: Int = 0,
    val redLetters: Boolean = true,
)

fun loadLook(p: SharedPreferences) = Look(
    fontSize = p.getFloat("fontSize", 18f),
    lineFactor = p.getFloat("lineFactor", 1.55f),
    serif = p.getBoolean("serif", true),
    theme = p.getInt("theme", 0),
    redLetters = p.getBoolean("redLetters", true),
)

fun saveLook(p: SharedPreferences, l: Look) {
    p.edit().putFloat("fontSize", l.fontSize).putFloat("lineFactor", l.lineFactor).putBoolean("serif", l.serif)
        .putInt("theme", l.theme).putBoolean("redLetters", l.redLetters).apply()
}
