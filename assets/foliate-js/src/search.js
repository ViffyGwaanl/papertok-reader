// length for context in excerpts
const CONTEXT_LENGTH = 50

const normalizeWhitespace = str => str.replace(/\s+/g, ' ')

// Zero-width and invisible characters to strip
const ZERO_WIDTH_RE = /[\u200B\u200C\u200D\uFEFF\u00AD\u2060\u180E]/g

// Full-width → half-width punctuation mapping (CJK common)
const FW_TO_HW = {
    '，': ',', '。': '.', '！': '!', '？': '?', '；': ';', '：': ':',
    '"': '"', '"': '"', ''': "'", ''': "'", '（': '(', '）': ')',
    '【': '[', '】': ']', '｛': '{', '｝': '}', '《': '<', '》': '>',
    '、': ',', '～': '~', '…': '...', '—': '-', '－': '-',
    '　': ' ', // ideographic space → ASCII space
}
const FW_CHARS_RE = new RegExp('[' + Object.keys(FW_TO_HW).join('') + ']', 'g')

/**
 * Normalize text for search matching.
 * - Collapse consecutive whitespace into a single space
 * - Remove zero-width / invisible characters
 * - Convert full-width CJK punctuation to half-width equivalents
 */
const normalizeForSearch = str => str
    .replace(ZERO_WIDTH_RE, '')
    .replace(FW_CHARS_RE, ch => FW_TO_HW[ch] || ch)
    .replace(/\s+/g, ' ')

/**
 * Build an offset map from normalized positions back to original positions.
 * Returns { normalized, offsets } where offsets[i] gives the original index
 * corresponding to normalized character i.
 */
const buildNormalizedMap = (original) => {
    const offsets = []
    let ni = 0
    let lastWasSpace = false
    const parts = []

    for (let oi = 0; oi < original.length; oi++) {
        const ch = original[oi]
        // Skip zero-width chars
        if (ZERO_WIDTH_RE.test(ch)) {
            ZERO_WIDTH_RE.lastIndex = 0
            continue
        }
        // Map full-width → half-width
        const mapped = FW_TO_HW[ch] || ch
        // Collapse whitespace
        if (/\s/.test(mapped)) {
            if (!lastWasSpace) {
                parts.push(' ')
                offsets.push(oi)
                lastWasSpace = true
            }
            continue
        }
        // Handle multi-char replacements (e.g., '…' → '...')
        for (let k = 0; k < mapped.length; k++) {
            parts.push(mapped[k])
            offsets.push(oi)
        }
        lastWasSpace = false
    }
    return { normalized: parts.join(''), offsets }
}

const makeExcerpt = (strs, { startIndex, startOffset, endIndex, endOffset }) => {
    const start = strs[startIndex]
    const end = strs[endIndex]
    const match = start === end
        ? start.slice(startOffset, endOffset)
        : start.slice(startOffset)
            + strs.slice(start + 1, end).join('')
            + end.slice(0, endOffset)
    const trimmedStart = normalizeWhitespace(start.slice(0, startOffset)).trimStart()
    const trimmedEnd = normalizeWhitespace(end.slice(endOffset)).trimEnd()
    const ellipsisPre = trimmedStart.length < CONTEXT_LENGTH ? '' : '…'
    const ellipsisPost = trimmedEnd.length < CONTEXT_LENGTH ? '' : '…'
    const pre = `${ellipsisPre}${trimmedStart.slice(-CONTEXT_LENGTH)}`
    const post = `${trimmedEnd.slice(0, CONTEXT_LENGTH)}${ellipsisPost}`
    return { pre, match, post }
}

const simpleSearch = function* (strs, query, options = {}) {
    const { locales = 'en', sensitivity } = options
    const matchCase = sensitivity === 'variant'

    // Build the haystack from original strings
    const originalHaystack = strs.join('')

    // Normalize both haystack and needle for matching
    const { normalized: normHaystack, offsets: normOffsets } = buildNormalizedMap(originalHaystack)
    const normNeedle = matchCase
        ? normalizeForSearch(query)
        : normalizeForSearch(query).toLocaleLowerCase(locales)
    const searchHaystack = matchCase ? normHaystack : normHaystack.toLocaleLowerCase(locales)
    const needleLength = normNeedle.length

    if (needleLength === 0) return

    // Build cumulative lengths for mapping back to strs indices
    const cumLengths = []
    let cum = 0
    for (const s of strs) {
        cum += s.length
        cumLengths.push(cum)
    }

    const findStrPosition = (originalIndex) => {
        let strIndex = 0
        while (strIndex < cumLengths.length && cumLengths[strIndex] <= originalIndex) {
            strIndex++
        }
        const prevCum = strIndex > 0 ? cumLengths[strIndex - 1] : 0
        return { strIndex, offset: originalIndex - prevCum }
    }

    let index = -1
    do {
        index = searchHaystack.indexOf(normNeedle, index + 1)
        if (index > -1) {
            // Map normalized positions back to original positions
            const origStart = normOffsets[index] ?? 0
            const origEnd = (normOffsets[index + needleLength - 1] ?? origStart) + 1

            const startPos = findStrPosition(origStart)
            const endPos = findStrPosition(origEnd)

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
    // Normalize query before segmenting
    const normQuery = normalizeForSearch(query)
    const queryLength = Array.from(segmenter.segment(normQuery)).length

    const substrArr = []
    let strIndex = 0
    let segments = segmenter.segment(strs[strIndex])[Symbol.iterator]()
    main: while (strIndex < strs.length) {
        while (substrArr.length < queryLength) {
            const { done, value } = segments.next()
            if (done) {
                // the current string is exhausted
                // move on to the next string
                strIndex++
                if (strIndex < strs.length) {
                    segments = segmenter.segment(strs[strIndex])[Symbol.iterator]()
                    continue
                } else break main
            }
            const { index, segment } = value
            // ignore formatting characters and zero-width chars
            if (!/[^\p{Format}]/u.test(segment)) continue
            if (ZERO_WIDTH_RE.test(segment)) {
                ZERO_WIDTH_RE.lastIndex = 0
                continue
            }
            // normalize whitespace
            if (/\s/u.test(segment)) {
                if (!/\s/u.test(substrArr[substrArr.length - 1]?.segment))
                    substrArr.push({ strIndex, index, segment: ' ' })
                continue
            }
            // Normalize segment (full-width → half-width)
            const normSegment = normalizeForSearch(segment)
            value.strIndex = strIndex
            value.normSegment = normSegment
            substrArr.push(value)
        }
        const substr = substrArr.map(x => x.normSegment || x.segment).join('')
        if (collator.compare(normQuery, substr) === 0) {
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

export const search = (strs, query, options) => {
    const { granularity = 'grapheme', sensitivity = 'base' } = options
    if (!Intl?.Segmenter || granularity === 'grapheme'
    && (sensitivity === 'variant' || sensitivity === 'accent'))
        return simpleSearch(strs, query, options)
    return segmenterSearch(strs, query, options)
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
