// Translation modes
export const TranslationMode = {
  OFF: 'off',
  TRANSLATION_ONLY: 'translation-only',
  ORIGINAL_ONLY: 'original-only',
  BILINGUAL: 'bilingual'
}

// Make TranslationMode globally available for debugging
if (typeof window !== 'undefined') {
  window.TranslationMode = TranslationMode
}

const _queueTranslateBlocks = async (blocks) => {
  try {
    // fire-and-forget queueing; results are pushed back via JS eval from Flutter.
    await window.flutter_inappwebview.callHandler('translateBlocks', blocks)
  } catch (error) {
    console.warn('translateBlocks failed:', error)
  }
}

export class Translator {
  #translationMode = TranslationMode.OFF

  observedElements = new Set()
  #translatedElements = new WeakMap()

  #observer = null

  // id -> element (for fast apply)
  #idToElement = new Map()
  // id -> originalText (stable even if original nodes get hidden)
  #idToOriginalText = new Map()
  #idCounter = 0

  // throttle viewport requests
  #requestTimer = null

  constructor() {
    this.#initializeObserver()
  }

  #initializeObserver() {
    this.#observer = new IntersectionObserver(
      (entries) => {
        if (this.#translationMode === TranslationMode.OFF) return
        if (entries.some((e) => e.isIntersecting)) {
          this.requestTranslateForViewport()
        }
      },
      {
        // Only translate current viewport + the next viewport.
        rootMargin: '0px 0px 100% 0px',
        threshold: 0
      }
    )
  }

  async setTranslationMode(mode) {
    if (!Object.values(TranslationMode).includes(mode)) {
      console.warn(`Invalid translation mode: ${mode}`)
      return
    }

    const oldMode = this.#translationMode
    this.#translationMode = mode

    if (oldMode !== mode) {
      if (mode === TranslationMode.OFF) {
        this.#updateTranslationDisplay()
      } else if (oldMode === TranslationMode.OFF) {
        // first enable: request translate for current + next viewport
        this.requestTranslateForViewport({ immediate: true })
      } else {
        this.#updateTranslationDisplay()
      }
    }

    // Re-render annotations after translation mode change
    if (window.reader && window.reader.annotationsByValue) {
      const existingAnnotations = Array.from(window.reader.annotationsByValue.values())
      if (existingAnnotations.length > 0) {
        window.renderAnnotations(existingAnnotations)
      }
    }
  }

  getTranslationMode() {
    return this.#translationMode
  }

  observeDocument(doc) {
    if (!doc) {
      console.warn('No document provided to observeDocument')
      return
    }

    const textElements = this.#walkTranslationBlocks(doc.body || doc.documentElement)

    textElements.forEach((element) => {
      if (!this.observedElements.has(element)) {
        this.#observer.observe(element)
        this.observedElements.add(element)
      }
    })
  }

  clearTranslations() {
    this.observedElements.forEach((element) => {
      const translationElements = element.querySelectorAll('.translated-text')
      translationElements.forEach((trans) => trans.remove())
      this.#restoreOriginalText(element)
    })

    this.#translatedElements = new WeakMap()
    this.#idToElement.clear()
    this.#idToOriginalText.clear()

    this.#observer.disconnect()
    this.observedElements.clear()
    this.#initializeObserver()
  }

  // Called by view.js on relocate (back/forward/page-turn)
  requestTranslateForViewport({ immediate = false } = {}) {
    if (this.#translationMode === TranslationMode.OFF) return

    if (this.#requestTimer) {
      clearTimeout(this.#requestTimer)
      this.#requestTimer = null
    }

    const run = () => {
      const blocks = this.#collectBlocksForViewport()
      if (blocks.length > 0) {
        _queueTranslateBlocks(blocks)
      }
    }

    if (immediate) {
      run()
    } else {
      // debounce a bit to avoid storms when scrolling
      this.#requestTimer = setTimeout(run, 120)
    }
  }

  // Called from Flutter via JS: reader.view.applyFullTextTranslation(id, text)
  applyTranslationById(id, translatedText) {
    const element = this.#idToElement.get(id) || document.querySelector(`[data-anx-translate-id="${id}"]`)
    if (!element) return false

    const originalText = this.#idToOriginalText.get(id) || element.innerText?.trim() || ''

    this.#translatedElements.set(element, {
      originalText,
      translatedText
    })

    this.#applyTranslation(element, translatedText)
    return true
  }

  #walkTranslationBlocks(root, rejectTags = ['pre', 'code', 'math', 'style', 'script']) {
    // EPUB: use block-level elements to avoid partial translation inside a paragraph.
    if (!root || !root.querySelectorAll) return []

    const blockSelectors = [
      'p',
      'li',
      'blockquote',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'figcaption',
      'dd', 'dt',
    ]

    const candidates = Array.from(root.querySelectorAll(blockSelectors.join(',')))

    const elements = []
    for (const el of candidates) {
      if (!el) continue
      const name = el.tagName.toLowerCase()
      if (rejectTags.includes(name)) continue
      if (el.classList && el.classList.contains('translated-text')) continue
      if (el.closest && el.closest('.translated-text')) continue

      // Skip list items that already contain paragraphs: let <p> be the unit.
      if (name === 'li' && el.querySelector('p')) continue

      const text = el.innerText?.trim() || el.textContent?.trim()
      if (!text) continue

      elements.push(el)
    }

    return elements
  }

  #collectBlocksForViewport() {
    const prefetchBottom = window.innerHeight * 2
    const blocks = []

    this.observedElements.forEach((element) => {
      if (!element || !element.getBoundingClientRect) return

      const rect = element.getBoundingClientRect()
      const isVisible = rect.top < prefetchBottom && rect.bottom > 0
      if (!isVisible) return

      // Already translated: just ensure display matches mode.
      if (this.#translatedElements.has(element)) {
        const translationWrapper = element.querySelector('.translated-text')
        if (translationWrapper) {
          this.#updateElementDisplay(element, translationWrapper)
        }
        return
      }

      const text = element.innerText?.trim()
      if (!text) return

      const id = element.getAttribute('data-anx-translate-id') || this.#assignId(element)
      this.#idToElement.set(id, element)
      this.#idToOriginalText.set(id, text)

      blocks.push({ id, text })
    })

    return blocks
  }

  #assignId(element) {
    const id = `b${++this.#idCounter}`
    element.setAttribute('data-anx-translate-id', id)
    return id
  }

  #applyTranslation(element, translatedText) {
    const existingTranslation = element.querySelector('.translated-text')
    if (existingTranslation) {
      existingTranslation.remove()
    }

    const wrapper = document.createElement('span')
    wrapper.className = 'translated-text'
    wrapper.setAttribute('data-translation-mark', '1')
    wrapper.style.display = 'block'
    wrapper.style.marginTop = '0.2em'
    wrapper.textContent = translatedText

    this.#updateElementDisplay(element, wrapper)
    element.appendChild(wrapper)
  }

  #updateElementDisplay(element, translationWrapper) {
    switch (this.#translationMode) {
      case TranslationMode.TRANSLATION_ONLY:
        this.#hideOriginalText(element)
        translationWrapper.style.display = 'block'
        break

      case TranslationMode.ORIGINAL_ONLY:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'none'
        break

      case TranslationMode.BILINGUAL:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'block'
        break

      case TranslationMode.OFF:
      default:
        this.#restoreOriginalText(element)
        translationWrapper.style.display = 'none'
        break
    }
  }

  #hideOriginalText(element) {
    if (!element.hasAttribute('data-original-visibility')) {
      element.setAttribute('data-original-visibility', 'hidden')

      Array.from(element.childNodes).forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const el = node
          if (!el.classList || !el.classList.contains('translated-text')) {
            if (!el.hasAttribute('data-original-display')) {
              el.setAttribute('data-original-display', el.style.display || 'initial')
              el.style.display = 'none'
            }
          }
        } else if (node.nodeType === Node.TEXT_NODE) {
          if (!node.__originalContent) {
            node.__originalContent = node.textContent
            node.textContent = ''
          }
        }
      })
    }

    element.classList.add('translation-source-hidden')
  }

  #restoreOriginalText(element) {
    if (element.hasAttribute('data-original-visibility')) {
      Array.from(element.childNodes).forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const el = node
          if (!el.classList || !el.classList.contains('translated-text')) {
            if (el.hasAttribute('data-original-display')) {
              const originalDisplay = el.getAttribute('data-original-display')
              el.style.display = originalDisplay === 'initial' ? '' : originalDisplay
              el.removeAttribute('data-original-display')
            }
          }
        } else if (node.nodeType === Node.TEXT_NODE) {
          if (node.__originalContent !== undefined) {
            node.textContent = node.__originalContent
            delete node.__originalContent
          }
        }
      })

      element.removeAttribute('data-original-visibility')
    }

    element.classList.remove('translation-source-hidden')
  }

  #updateTranslationDisplay() {
    this.observedElements.forEach((element) => {
      const translationWrapper = element.querySelector('.translated-text')
      if (translationWrapper) {
        this.#updateElementDisplay(element, translationWrapper)
      }
    })
  }

  destroy() {
    this.clearTranslations()
    this.#observer = null
  }
}
