package eu.kanade.tachiyomi.source.model

/**
 * What one round of `getMangaUpdate` came back with.
 *
 * extensions-lib 1.6 folded `getMangaDetails` and `getChapterList` into a
 * single call, because most sources answer both from the same response and
 * asking twice meant scraping the same page twice. Extensions built against it
 * implement only the combined call and no longer declare `mangaDetailsParse` or
 * `chapterListParse` at all — which is why a source could browse and search
 * perfectly and then open to a blank page with no chapters.
 */
@Suppress("UNUSED")
class SMangaUpdate(val manga: SManga, val chapters: List<SChapter>)
