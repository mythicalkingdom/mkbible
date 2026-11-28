package org.mkbible.proof

/** The Pascal Bible core (libmkbibjni.so).  See android/proof/native/mkbibjni.pas for what each call returns. */
object Native {
    init { System.loadLibrary("mkbibjni") }
    external fun open(conf: String): Long
    external fun close(h: Long)
    external fun info(h: Long): String
    external fun books(h: Long): String
    external fun chapter(h: Long, book: Int, chap: Int): String
    external fun search(h: Long, text: String, scope: Int, max: Int): String
    external fun find(h: Long, ref: String): String
    external fun dictOpen(conf: String): Long
    external fun dictClose(h: Long)
    external fun dictEntry(h: Long, key: String): String
    external fun verseText(h: Long, book: Int, chap: Int, verse: Int): String
}
