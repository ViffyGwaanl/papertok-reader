// length for context in excerpts
const CONTEXT_LENGTH = 50

const normalizeWhitespace = str => str.replace(/\s+/g, ' ')

// Zero-width and invisible characters
const ZERO_WIDTH_RE = /[\u200B\u200C\u200D\uFEFF\u00AD\u2060\u180E]/g
const ZERO_WIDTH_TEST = /[\u200B\u200C\u200D\uFEFF\u00AD\u2060\u180E]/

// Full-width → half-width punctuation mapping (CJK common)
const FW_TO_HW = {
    '，': ',', '。': '.', '！': '!', '？': '?', '；': ';', '：': ':',
    '\u201C': '"', '\u201D': '"', '\u2018': "'", '\u2019': "'", '（': '(', '）': ')',
    '【': '[', '】': ']', '｛': '{', '｝': '}', '《': '<', '》': '>',
    '、': ',', '～': '~', '…': '...', '—': '-', '－': '-',
    '\u3000': ' ',
}
const FW_CHARS_RE = new RegExp('[' + Object.keys(FW_TO_HW).join('') + ']', 'g')

/**
 * Normalize a query string before searching.
 * - Strip zero-width / invisible chars
 * - Convert full-width CJK punctuation → half-width
 * - Collapse whitespace
 */
const normalizeQuery = str => str
    .replace(ZERO_WIDTH_RE, '')
    .replace(FW_CHARS_RE, ch => FW_TO_HW[ch] || ch)
    .replace(/\s+/g, ' ')
    .trim()

/**
 * Normalize a haystack string for matching:
 * - Strip zero-width / invisible characters
 * - Convert full-width CJK punctuation → half-width (same as query normalization)
 * Returns { text, posMap } where posMap[cleanIndex] = originalIndex
 */
const normalizeHaystack = (str) => {
    const chars = []
    const posMap = []
    for (let i = 0; i < str.length; i++) {
        const ch = str[i]
        // Skip zero-width chars
        if (ZERO_WIDTH_TEST.test(ch)) continue
        // Map full-width → half-width
        const mapped = FW_TO_HW[ch]
        if (mapped) {
            for (let k = 0; k < mapped.length; k++) {
                chars.push(mapped[k])
                posMap.push(i)
            }
        } else {
            chars.push(ch)
            posMap.push(i)
        }
    }
    return { text: chars.join(''), posMap }
}

const makeExcerpt = (strs, { startIndex, startOffset, endIndex, endOffset }) => {
    const start = strs[startIndex]
    const end = strs[endIndex]
    if (!start || !end) return { pre: '', match: '', post: '' }
    const match = start === end
        ? start.slice(startOffset, endOffset)
        : start.slice(startOffset)
            + strs.slice(startIndex + 1, endIndex).join('')
            + end.slice(0, endOffset)
    const trimmedStart = normalizeWhitespace(start.slice(0, startOffset)).trimStart()
    const trimmedEnd = normalizeWhitespace(end.slice(endOffset)).trimEnd()
    const ellipsisPre = trimmedStart.length < CONTEXT_LENGTH ? '' : '…'
    const ellipsisPost = trimmedEnd.length < CONTEXT_LENGTH ? '' : '…'
    const pre = `${ellipsisPre}${trimmedStart.slice(-CONTEXT_LENGTH)}`
    const post = `${trimmedEnd.slice(0, CONTEXT_LENGTH)}${ellipsisPost}`
    return { pre, match, post }
}

// ── Build cumulative length map for strs → original position tracking ────────

const buildCumLengths = (strs) => {
    const cumLengths = []
    let cum = 0
    for (const s of strs) {
        cum += s.length
        cumLengths.push(cum)
    }
    return cumLengths
}

/**
 * Map a flat character index in the joined haystack back to
 * { strIndex, offset } within the strs array.
 */
const findStrPosition = (cumLengths, strs, originalIndex) => {
    let idx = 0
    while (idx < cumLengths.length && cumLengths[idx] <= originalIndex) idx++
    // Clamp to last string if at exact boundary
    if (idx >= strs.length) idx = strs.length - 1
    const prevCum = idx > 0 ? cumLengths[idx - 1] : 0
    return { strIndex: idx, offset: originalIndex - prevCum }
}

// ── Primary search: fuzzySimpleSearch ─────────────────────────────────────────
//
// Enhanced version of the original simpleSearch:
// 1. Strips zero-width chars from haystack so "学\u200B院" matches "学院"
// 2. Uses indexOf for matching — naturally tolerant of CJK text
// 3. Maps clean positions back to original positions via posMap

const fuzzySimpleSearch = function* (strs, query, options = {}) {
    const { locales = 'en', sensitivity } = options
    const matchCase = sensitivity === 'variant'

    const originalHaystack = strs.join('')
    const { text: cleanHaystack, posMap } = normalizeHaystack(originalHaystack)

    const cleanQuery = query.replace(ZERO_WIDTH_RE, '')
    if (cleanQuery.length === 0) return

    const lowerHaystack = matchCase ? cleanHaystack : cleanHaystack.toLocaleLowerCase(locales)
    const needle = matchCase ? cleanQuery : cleanQuery.toLocaleLowerCase(locales)
    const needleLength = needle.length

    const cumLengths = buildCumLengths(strs)

    let index = -1
    do {
        index = lowerHaystack.indexOf(needle, index + 1)
        if (index > -1) {
            // Map clean position back to original position via posMap
            const origStart = posMap[index]
            const endCleanIdx = index + needleLength - 1
            const origEnd = (endCleanIdx < posMap.length ? posMap[endCleanIdx] : posMap[posMap.length - 1]) + 1

            const startPos = findStrPosition(cumLengths, strs, origStart)
            const endPos = findStrPosition(cumLengths, strs, origEnd)

            const range = {
                startIndex: startPos.strIndex,
                startOffset: startPos.offset,
                endIndex: endPos.strIndex,
                endOffset: endPos.offset,
            }
            yield { range, excerpt: makeExcerpt(strs, range) }
        }
    } while (index > -1)
}

// ── Segmenter search (kept for matchWholeWords only) ─────────────────────────

const segmenterSearch = function* (strs, query, options = {}) {
    const { locales = 'en', granularity = 'word', sensitivity = 'base' } = options
    let segmenter, collator
    try {
        segmenter = new Intl.Segmenter(locales, { usage: 'search', granularity })
        collator = new Intl.Collator(locales, { sensitivity })
    } catch (e) {
        console.warn(e)
        segmenter = new Intl.Segmenter('en', { usage: 'search', granularity })
        collator = new Intl.Collator('en', { sensitivity })
    }
    const queryLength = Array.from(segmenter.segment(query)).length

    const substrArr = []
    let strIndex = 0
    let segments = segmenter.segment(strs[strIndex])[Symbol.iterator]()
    main: while (strIndex < strs.length) {
        while (substrArr.length < queryLength) {
            const { done, value } = segments.next()
            if (done) {
                strIndex++
                if (strIndex < strs.length) {
                    segments = segmenter.segment(strs[strIndex])[Symbol.iterator]()
                    continue
                } else break main
            }
            const { index, segment } = value
            if (!/[^\p{Format}]/u.test(segment)) continue
            if (ZERO_WIDTH_TEST.test(segment)) continue
            if (/\s/u.test(segment)) {
                if (!/\s/u.test(substrArr[substrArr.length - 1]?.segment))
                    substrArr.push({ strIndex, index, segment: ' ' })
                continue
            }
            value.strIndex = strIndex
            substrArr.push(value)
        }
        const substr = substrArr.map(x => x.segment).join('')
        if (collator.compare(query, substr) === 0) {
            const endIndex = strIndex
            const lastSeg = substrArr[substrArr.length - 1]
            const endOffset = lastSeg.index + lastSeg.segment.length
            const startIndex = substrArr[0].strIndex
            const startOffset = substrArr[0].index
            const range = { startIndex, startOffset, endIndex, endOffset }
            yield { range, excerpt: makeExcerpt(strs, range) }
        }
        substrArr.shift()
    }
}

// ── Multi-term AND search ────────────────────────────────────────────────────
//
// Splits query by whitespace into individual terms.
// For each term, runs fuzzySimpleSearch independently.
// Only yields results from terms that ALL match (AND logic).
// De-duplicates by CFI range to avoid showing the same passage twice.

const multiTermSearch = function* (strs, query, options = {}) {
    const terms = query.split(/\s+/).filter(t => t.length > 0)
    if (terms.length < 2) return

    // Collect results for each term
    const allResults = []
    for (const term of terms) {
        const termResults = Array.from(fuzzySimpleSearch(strs, term, options))
        if (termResults.length === 0) return // AND: if any term has 0 results, bail
        allResults.push(termResults)
    }

    // Yield results from all terms, de-duplicated by startIndex+startOffset
    const seen = new Set()
    for (const termResults of allResults) {
        for (const result of termResults) {
            const key = `${result.range.startIndex}:${result.range.startOffset}`
            if (!seen.has(key)) {
                seen.add(key)
                yield result
            }
        }
    }
}

// ── Main search entry point with 3-level fallback ────────────────────────────
//
// Level 1: fuzzySimpleSearch (phrase match with zero-width stripping)
// Level 2: strip spaces from query and retry (handles "学院 大裂谷" → "学院大裂谷")
// Level 3: multi-term AND search (split into individual terms)
//
// matchWholeWords → segmenterSearch with fuzzySimpleSearch fallback

export const search = function* (strs, query, options) {
    const normalizedQuery = normalizeQuery(query)
    if (!normalizedQuery) return

    const { granularity = 'grapheme' } = options

    // matchWholeWords: use segmenterSearch first, fall back to fuzzy
    if (granularity === 'word' && Intl?.Segmenter) {
        let found = false
        for (const result of segmenterSearch(strs, normalizedQuery, options)) {
            found = true
            yield result
        }
        if (found) return
        // Fall through to fuzzy search below
    }

    // Level 1: direct phrase search
    let found = false
    for (const result of fuzzySimpleSearch(strs, normalizedQuery, options)) {
        found = true
        yield result
    }
    if (found) return

    // Level 2: strip ALL whitespace and retry (CJK phrase tolerance)
    const noSpaceQuery = normalizedQuery.replace(/\s+/g, '')
    if (noSpaceQuery !== normalizedQuery && noSpaceQuery.length > 0) {
        for (const result of fuzzySimpleSearch(strs, noSpaceQuery, options)) {
            found = true
            yield result
        }
        if (found) return
    }

    // Level 3: multi-term AND search (split by spaces, find sections with ALL terms)
    const terms = normalizedQuery.split(/\s+/).filter(t => t.length > 0)
    if (terms.length >= 2) {
        for (const result of multiTermSearch(strs, normalizedQuery, options)) {
            yield result
        }
    }
}

export const searchMatcher = (textWalker, opts) => {
    const { defalutLocale, matchCase, matchDiacritics, matchWholeWords } = opts
    return function* (doc, query) {
        const iter = textWalker(doc, function* (strs, makeRange) {
            for (const result of search(strs, query, {
                locales: doc.body.lang || doc.documentElement.lang || defalutLocale || 'en',
                granularity: matchWholeWords ? 'word' : 'grapheme',
                sensitivity: matchDiacritics && matchCase ? 'variant'
                : matchDiacritics && !matchCase ? 'accent'
                : !matchDiacritics && matchCase ? 'case'
                : 'base',
            })) {
                const { startIndex, startOffset, endIndex, endOffset } = result.range
                result.range = makeRange(startIndex, startOffset, endIndex, endOffset)
                yield result
            }
        })
        for (const result of iter) yield result
    }
}
