;;; dawa-tts-lang.el --- Language detection for dawa-tts -*- lexical-binding: t -*-

;; Copyright (C) 2025 Sangjee Dondrub

;; Author: Sangjee Dondrub
;; Keywords: multimedia, tts, i18n
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))

;;; Commentary:

;; Language detection for dawa-tts multilingual support.
;; Supports 31 languages via Supertonic v3 models.
;;
;; Supported languages:
;; Arabic (ar), Bulgarian (bg), Croatian (hr), Czech (cs), Danish (da),
;; Dutch (nl), English (en), Estonian (et), Finnish (fi), French (fr),
;; German (de), Greek (el), Hindi (hi), Hungarian (hu), Indonesian (id),
;; Italian (it), Japanese (ja), Korean (ko), Latvian (lv), Lithuanian (lt),
;; Polish (pl), Portuguese (pt), Romanian (ro), Russian (ru), Slovak (sk),
;; Slovenian (sl), Spanish (es), Swedish (sv), Turkish (tr), Ukrainian (uk),
;; Vietnamese (vi)

;;; Code:

(defgroup dawa-tts-lang nil
  "Language detection for dawa-tts."
  :group 'dawa-tts
  :prefix "dawa-tts-lang-")

(defcustom dawa-tts-lang-default "en"
  "Default language for TTS synthesis.
\"na\" = language-agnostic mode (Supertonic auto-detects).
\"en\" = English (recommended for English/Chinese users).
\"zh\" = Chinese (internally mapped to \"na\").
Set to specific language code to force a language."
  :type '(choice (const :tag "English (default)" "en")
                 (const :tag "Auto-detect (language-agnostic)" "na")
                 (const :tag "Chinese (mapped to 'na')" "zh")
                 (const :tag "Korean" "ko")
                 (const :tag "Japanese" "ja")
                 (const :tag "Arabic" "ar")
                 (const :tag "Bulgarian" "bg")
                 (const :tag "Croatian" "hr")
                 (const :tag "Czech" "cs")
                 (const :tag "Danish" "da")
                 (const :tag "Dutch" "nl")
                 (const :tag "Estonian" "et")
                 (const :tag "Finnish" "fi")
                 (const :tag "French" "fr")
                 (const :tag "German" "de")
                 (const :tag "Greek" "el")
                 (const :tag "Hindi" "hi")
                 (const :tag "Hungarian" "hu")
                 (const :tag "Indonesian" "id")
                 (const :tag "Italian" "it")
                 (const :tag "Latvian" "lv")
                 (const :tag "Lithuanian" "lt")
                 (const :tag "Polish" "pl")
                 (const :tag "Portuguese" "pt")
                 (const :tag "Romanian" "ro")
                 (const :tag "Russian" "ru")
                 (const :tag "Slovak" "sk")
                 (const :tag "Slovenian" "sl")
                 (const :tag "Spanish" "es")
                 (const :tag "Swedish" "sv")
                 (const :tag "Turkish" "tr")
                 (const :tag "Ukrainian" "uk")
                 (const :tag "Vietnamese" "vi"))
  :group 'dawa-tts-lang)

(defcustom dawa-tts-lang-auto-detect t
  "Automatically detect text language using Emacs-side heuristics.
When nil, always use `dawa-tts-lang-default'.
When t, detect script and map to language code.
Note: Setting `dawa-tts-lang-default' to \"na\" lets Supertonic
handle detection internally, which may be more accurate."
  :type 'boolean
  :group 'dawa-tts-lang)

(defvar-local dawa-tts-lang-override nil
  "Buffer-local language override.
When set, this language is used instead of auto-detection.")

(defconst dawa-tts-lang--supported-languages
  '("na" "ar" "bg" "hr" "cs" "da" "nl" "en" "et" "fi" "fr" "de" "el" "hi" "hu"
    "id" "it" "ja" "ko" "lv" "lt" "pl" "pt" "ro" "ru" "sk" "sl" "es" "sv"
    "tr" "uk" "vi" "zh")
  "List of languages supported by Supertonic v3.
\"na\" = language-agnostic mode (auto-detection by Supertonic).
\"zh\" = Chinese (internally mapped to \"na\" for Supertonic).")

;;; Language Detection

(defun dawa-tts-lang--char-in-range-p (char ranges)
  "Check if CHAR is in any of RANGES.
RANGES is a list of (start . end) cons cells."
  (cl-some (lambda (range)
             (and (>= char (car range))
                  (<= char (cdr range))))
           ranges))

(defun dawa-tts-lang--detect-script (text)
  "Detect the primary script used in TEXT.
Returns one of: cjk, cyrillic, arabic, greek, latin, or nil."
  (let ((cjk-count 0)
        (cyrillic-count 0)
        (arabic-count 0)
        (greek-count 0)
        (latin-count 0)
        (total-alpha 0))
    (dolist (char (string-to-list text))
      (cond
       ;; CJK Unified Ideographs
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x4E00 . #x9FFF)    ; CJK Unified
                                          (#x3400 . #x4DBF)    ; CJK Extension A
                                          (#x20000 . #x2A6DF)  ; CJK Extension B
                                          (#xF900 . #xFAFF)))  ; CJK Compatibility
        (cl-incf cjk-count)
        (cl-incf total-alpha))
       ;; Hangul (Korean)
       ((dawa-tts-lang--char-in-range-p char
                                        '((#xAC00 . #xD7AF)    ; Hangul Syllables
                                          (#x1100 . #x11FF)    ; Hangul Jamo
                                          (#x3130 . #x318F)    ; Hangul Compatibility Jamo
                                          (#xA960 . #xA97F)))  ; Hangul Jamo Extended-A
        (cl-incf cjk-count)
        (cl-incf total-alpha))
       ;; Hiragana and Katakana (Japanese)
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x3040 . #x309F)    ; Hiragana
                                          (#x30A0 . #x30FF)))  ; Katakana
        (cl-incf cjk-count)
        (cl-incf total-alpha))
       ;; Cyrillic
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x0400 . #x04FF)    ; Cyrillic
                                          (#x0500 . #x052F)))  ; Cyrillic Supplement
        (cl-incf cyrillic-count)
        (cl-incf total-alpha))
       ;; Arabic
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x0600 . #x06FF)    ; Arabic
                                          (#x0750 . #x077F)    ; Arabic Supplement
                                          (#x08A0 . #x08FF)))  ; Arabic Extended-A
        (cl-incf arabic-count)
        (cl-incf total-alpha))
       ;; Greek
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x0370 . #x03FF)    ; Greek and Coptic
                                          (#x1F00 . #x1FFF)))  ; Greek Extended
        (cl-incf greek-count)
        (cl-incf total-alpha))
       ;; Latin (including extended)
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x0041 . #x005A)    ; A-Z
                                          (#x0061 . #x007A)    ; a-z
                                          (#x00C0 . #x00FF)    ; Latin-1 Supplement
                                          (#x0100 . #x017F)    ; Latin Extended-A
                                          (#x0180 . #x024F)))  ; Latin Extended-B
        (cl-incf latin-count)
        (cl-incf total-alpha))))

    ;; Determine dominant script (need at least 10% of text to be alphabetic)
    (when (> total-alpha (* 0.1 (length text)))
      (let ((threshold (* 0.3 total-alpha)))  ; Script must be >30% of alphabetic chars
        (cond
         ((> cjk-count threshold) 'cjk)
         ((> cyrillic-count threshold) 'cyrillic)
         ((> arabic-count threshold) 'arabic)
         ((> greek-count threshold) 'greek)
         ((> latin-count threshold) 'latin)
         (t nil))))))

(defun dawa-tts-lang--detect-cjk-language (text)
  "Detect specific CJK language (ko, ja, or zh) from TEXT.
Returns 'ko for Korean, 'ja for Japanese, 'zh for Chinese, or nil for unknown."
  (let ((hangul-count 0)
        (hiragana-count 0)
        (katakana-count 0)
        (han-count 0))
    (dolist (char (string-to-list text))
      (cond
       ;; Hangul (Korean)
       ((dawa-tts-lang--char-in-range-p char
                                        '((#xAC00 . #xD7AF)
                                          (#x1100 . #x11FF)
                                          (#x3130 . #x318F)
                                          (#xA960 . #xA97F)))
        (cl-incf hangul-count))
       ;; Hiragana (Japanese)
       ((dawa-tts-lang--char-in-range-p char '((#x3040 . #x309F)))
        (cl-incf hiragana-count))
       ;; Katakana (Japanese)
       ((dawa-tts-lang--char-in-range-p char '((#x30A0 . #x30FF)))
        (cl-incf katakana-count))
       ;; Han characters (Chinese/Japanese Kanji)
       ((dawa-tts-lang--char-in-range-p char
                                        '((#x4E00 . #x9FFF)    ; CJK Unified
                                          (#x3400 . #x4DBF)    ; CJK Extension A
                                          (#x20000 . #x2A6DF)  ; CJK Extension B
                                          (#xF900 . #xFAFF)))  ; CJK Compatibility
        (cl-incf han-count))))

    (cond
     ;; Korean: has Hangul
     ((> hangul-count 0) 'ko)
     ;; Japanese: has Hiragana or Katakana
     ((or (> hiragana-count 0) (> katakana-count 0)) 'ja)
     ;; Chinese: has Han characters but no Japanese kana
     ((> han-count 0) 'zh)
     ;; Unknown
     (t nil))))

(defun dawa-tts-lang--detect-cyrillic-language (text)
  "Detect specific Cyrillic language from TEXT.
Returns 'ru for Russian, 'uk for Ukrainian, 'bg for Bulgarian, or nil."
  ;; Simple heuristic: look for language-specific characters
  (let ((has-ukrainian-chars nil)
        (has-bulgarian-chars nil))
    (dolist (char (string-to-list text))
      (cond
       ;; Ukrainian-specific: Ґ ґ Є є І і Ї ї
       ((memq char '(#x0490 #x0491 #x0404 #x0454 #x0406 #x0456 #x0407 #x0457))
        (setq has-ukrainian-chars t))
       ;; Bulgarian-specific: Ъ ъ (used differently than Russian)
       ((memq char '(#x042A #x044A))
        (setq has-bulgarian-chars t))))

    (cond
     (has-ukrainian-chars 'uk)
     (has-bulgarian-chars 'bg)
     (t 'ru))))  ; Default to Russian for Cyrillic

(defun dawa-tts-lang-detect (text)
  "Detect language of TEXT.
Returns ISO 639-1 language code (e.g., \"en\", \"ko\", \"ja\", \"zh\").
Falls back to `dawa-tts-lang-default' if detection fails.
Note: \"zh\" (Chinese) is mapped to \"na\" for Supertonic compatibility."
  (if (not dawa-tts-lang-auto-detect)
      dawa-tts-lang-default
    (let ((script (dawa-tts-lang--detect-script text)))
      (pcase script
        ('cjk
         (let ((lang (dawa-tts-lang--detect-cjk-language text)))
           (pcase lang
             ('ko "ko")
             ('ja "ja")
             ('zh "zh")  ; Will be mapped to "na" when passed to TTS
             (_ "na"))))  ; Unknown CJK, use language-agnostic
        ('cyrillic
         (let ((lang (dawa-tts-lang--detect-cyrillic-language text)))
           (pcase lang
             ('ru "ru")
             ('uk "uk")
             ('bg "bg")
             (_ "ru"))))
        ('arabic "ar")
        ('greek "el")
        ('latin dawa-tts-lang-default)  ; Could be many languages, use default
        (_ dawa-tts-lang-default)))))

;;;###autoload
(defun dawa-tts-lang-get ()
  "Get the language to use for TTS synthesis.
Checks in order:
1. Buffer-local override (`dawa-tts-lang-override')
2. Auto-detection (if enabled)
3. Default language (`dawa-tts-lang-default')"
  (or dawa-tts-lang-override
      dawa-tts-lang-default))

;;;###autoload
(defun dawa-tts-lang-set (lang)
  "Set buffer-local language override to LANG.
LANG should be an ISO 639-1 code (e.g., \"en\", \"ko\", \"ja\")."
  (interactive
   (list (completing-read "Language: "
                          dawa-tts-lang--supported-languages
                          nil t nil nil dawa-tts-lang-default)))
  (setq-local dawa-tts-lang-override lang)
  (message "TTS language set to: %s" lang))

;;;###autoload
(defun dawa-tts-lang-clear ()
  "Clear buffer-local language override.
TTS will use auto-detection or default language."
  (interactive)
  (setq-local dawa-tts-lang-override nil)
  (message "TTS language override cleared"))

;;;###autoload
(defun dawa-tts-lang-toggle-auto-detect ()
  "Toggle automatic language detection."
  (interactive)
  (setq dawa-tts-lang-auto-detect (not dawa-tts-lang-auto-detect))
  (message "Auto language detection %s"
           (if dawa-tts-lang-auto-detect "enabled" "disabled")))

(provide 'dawa-tts-lang)
;;; dawa-tts-lang.el ends here
