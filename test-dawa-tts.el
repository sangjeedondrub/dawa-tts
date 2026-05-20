;;; test-dawa-tts.el --- Tests for dawa-tts -*- lexical-binding: t -*-

;; Copyright (C) 2025 Sangjee Dondrub

;; Author: Sangjee Dondrub
;; Keywords: test

;;; Commentary:

;; ERT tests for dawa-tts.el and dawa-tts-lang.el.
;;
;; Run tests:
;;   emacs -Q --batch -l dawa-tts-lang.el -l dawa-tts-chunk.el -l test-dawa-tts.el -f ert-run-tests-batch-and-exit
;;
;; Interactive multilingual test:
;;   M-x dawa-tts-test-multilingual

;;; Code:

(require 'ert)
(require 'dawa-tts-lang)

;;; Language Detection Tests

;; Script Detection

(ert-deftest test-dawa-tts-lang--detect-script-latin ()
  "Test Latin script detection."
  (should (eq (dawa-tts-lang--detect-script "Hello World") 'latin))
  (should (eq (dawa-tts-lang--detect-script "Bonjour le monde") 'latin))
  (should (eq (dawa-tts-lang--detect-script "Hola mundo") 'latin)))

(ert-deftest test-dawa-tts-lang--detect-script-cyrillic ()
  "Test Cyrillic script detection."
  (should (eq (dawa-tts-lang--detect-script "Привет мир") 'cyrillic))
  (should (eq (dawa-tts-lang--detect-script "Здравствуй мир") 'cyrillic)))

(ert-deftest test-dawa-tts-lang--detect-script-arabic ()
  "Test Arabic script detection."
  (should (eq (dawa-tts-lang--detect-script "مرحبا بالعالم") 'arabic)))

(ert-deftest test-dawa-tts-lang--detect-script-greek ()
  "Test Greek script detection."
  (should (eq (dawa-tts-lang--detect-script "Γεια σου κόσμε") 'greek)))

(ert-deftest test-dawa-tts-lang--detect-script-cjk ()
  "Test CJK script detection."
  (should (eq (dawa-tts-lang--detect-script "안녕하세요") 'cjk))     ; Korean
  (should (eq (dawa-tts-lang--detect-script "こんにちは") 'cjk))     ; Japanese
  (should (eq (dawa-tts-lang--detect-script "你好世界") 'cjk)))      ; Chinese

;; CJK Language Detection

(ert-deftest test-dawa-tts-lang--detect-cjk-korean ()
  "Test Korean (Hangul) detection."
  (should (eq (dawa-tts-lang--detect-cjk-language "안녕하세요") 'ko))
  (should (eq (dawa-tts-lang--detect-cjk-language "한국어") 'ko)))

(ert-deftest test-dawa-tts-lang--detect-cjk-japanese ()
  "Test Japanese detection."
  (should (eq (dawa-tts-lang--detect-cjk-language "こんにちは") 'ja))  ; Hiragana
  (should (eq (dawa-tts-lang--detect-cjk-language "カタカナ") 'ja)))    ; Katakana

(ert-deftest test-dawa-tts-lang--detect-cjk-chinese ()
  "Test Chinese detection (returns 'zh)."
  (should (eq (dawa-tts-lang--detect-cjk-language "你好世界") 'zh)))

;; Cyrillic Language Detection

(ert-deftest test-dawa-tts-lang--detect-cyrillic-russian ()
  "Test Russian detection (default for Cyrillic)."
  (should (eq (dawa-tts-lang--detect-cyrillic-language "Привет") 'ru)))

(ert-deftest test-dawa-tts-lang--detect-cyrillic-ukrainian ()
  "Test Ukrainian detection via specific characters (Є є І і Ї ї)."
  (should (eq (dawa-tts-lang--detect-cyrillic-language "Україно") 'uk)))

;; Full Language Detection

(ert-deftest test-dawa-tts-lang-detect-korean ()
  "Test Korean language detection."
  (let ((dawa-tts-lang-auto-detect t))
    (should (equal (dawa-tts-lang-detect "안녕하세요 세계") "ko"))))

(ert-deftest test-dawa-tts-lang-detect-japanese ()
  "Test Japanese language detection."
  (let ((dawa-tts-lang-auto-detect t))
    (should (equal (dawa-tts-lang-detect "こんにちは世界") "ja"))))

(ert-deftest test-dawa-tts-lang-detect-chinese ()
  "Test Chinese detection (should return 'zh')."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "en"))
    (should (equal (dawa-tts-lang-detect "你好世界") "zh"))))

(ert-deftest test-dawa-tts-lang-detect-russian ()
  "Test Russian language detection."
  (let ((dawa-tts-lang-auto-detect t))
    (should (equal (dawa-tts-lang-detect "Привет мир") "ru"))))

(ert-deftest test-dawa-tts-lang-detect-ukrainian ()
  "Test Ukrainian language detection."
  (let ((dawa-tts-lang-auto-detect t))
    (should (equal (dawa-tts-lang-detect "Україно") "uk"))))

(ert-deftest test-dawa-tts-lang-detect-arabic ()
  "Test Arabic language detection."
  (let ((dawa-tts-lang-auto-detect t))
    (should (equal (dawa-tts-lang-detect "مرحبا") "ar"))))

(ert-deftest test-dawa-tts-lang-detect-greek ()
  "Test Greek language detection."
  (let ((dawa-tts-lang-auto-detect t))
    (should (equal (dawa-tts-lang-detect "Γεια σου") "el"))))

(ert-deftest test-dawa-tts-lang-detect-auto-disabled ()
  "Test that auto-detection respects the disabled flag."
  (let ((dawa-tts-lang-auto-detect nil)
        (dawa-tts-lang-default "en"))
    (should (equal (dawa-tts-lang-detect "안녕하세요") "en"))
    (should (equal (dawa-tts-lang-detect "Привет") "en"))))

(ert-deftest test-dawa-tts-lang-detect-mixed-scripts ()
  "Test detection with mixed scripts (dominant should win)."
  (let ((dawa-tts-lang-auto-detect t))
    ;; Korean with English - Korean should dominate
    (should (equal (dawa-tts-lang-detect "안녕하세요 Hello 세계") "ko"))))

;; English and Chinese Specific Tests

(ert-deftest test-dawa-tts-lang-detect-english-only ()
  "Test pure English text detection."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "en"))
    (should (equal (dawa-tts-lang-detect "The quick brown fox jumps over the lazy dog.") "en"))
    (should (equal (dawa-tts-lang-detect "Hello world!") "en"))))

(ert-deftest test-dawa-tts-lang-detect-chinese-simplified ()
  "Test simplified Chinese detection."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "en"))
    (should (equal (dawa-tts-lang-detect "你好世界") "zh"))
    (should (equal (dawa-tts-lang-detect "这是一个中文测试句子。") "zh"))))

(ert-deftest test-dawa-tts-lang-detect-chinese-traditional ()
  "Test traditional Chinese detection."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "en"))
    (should (equal (dawa-tts-lang-detect "繁體中文測試") "zh"))))

(ert-deftest test-dawa-tts-lang-detect-english-chinese-mixed ()
  "Test mixed English and Chinese text."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "en"))
    ;; Chinese dominant - should detect Chinese
    (should (equal (dawa-tts-lang-detect "你好 Hello 世界 World 中文") "zh"))
    ;; English dominant - should use default
    (should (equal (dawa-tts-lang-detect "Hello 你好 World") "en"))))

;; Configuration Tests

(ert-deftest test-dawa-tts-lang-get-default ()
  "Test language getter with default."
  (let ((dawa-tts-lang-default "en")
        (dawa-tts-lang-override nil))
    (should (equal (dawa-tts-lang-get) "en"))))

(ert-deftest test-dawa-tts-lang-get-override ()
  "Test language getter with buffer-local override."
  (with-temp-buffer
    (let ((dawa-tts-lang-default "en"))
      (setq-local dawa-tts-lang-override "ko")
      (should (equal (dawa-tts-lang-get) "ko")))))

(ert-deftest test-dawa-tts-lang-set ()
  "Test setting buffer-local language override."
  (with-temp-buffer
    (dawa-tts-lang-set "ja")
    (should (equal dawa-tts-lang-override "ja"))))

(ert-deftest test-dawa-tts-lang-clear ()
  "Test clearing buffer-local language override."
  (with-temp-buffer
    (setq-local dawa-tts-lang-override "ko")
    (dawa-tts-lang-clear)
    (should (null dawa-tts-lang-override))))

(ert-deftest test-dawa-tts-lang-supported-languages ()
  "Test that expected languages are in the supported list."
  (should (member "na" dawa-tts-lang--supported-languages))
  (should (member "en" dawa-tts-lang--supported-languages))
  (should (member "ko" dawa-tts-lang--supported-languages))
  (should (member "ja" dawa-tts-lang--supported-languages))
  (should (member "zh" dawa-tts-lang--supported-languages))
  (should (= (length dawa-tts-lang--supported-languages) 33)))

;; Edge Cases

(ert-deftest test-dawa-tts-lang-detect-empty-string ()
  "Test detection with empty string."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "na"))
    (should (equal (dawa-tts-lang-detect "") "na"))))

(ert-deftest test-dawa-tts-lang-detect-numbers-only ()
  "Test detection with numbers only."
  (let ((dawa-tts-lang-auto-detect t)
        (dawa-tts-lang-default "na"))
    (should (equal (dawa-tts-lang-detect "12345") "na"))))

;;; Chunking Tests

(ert-deftest test-dawa-tts-chunk-max-length ()
  "Test chunk max length calculation for different languages."
  (should (= (dawa-tts-chunk--get-max-length "ko") 120))
  (should (= (dawa-tts-chunk--get-max-length "ja") 120))
  (should (= (dawa-tts-chunk--get-max-length "en") 300))
  (should (= (dawa-tts-chunk--get-max-length "es") 300)))

(ert-deftest test-dawa-tts-chunk-estimate-duration ()
  "Test duration estimation for chunks."
  (let ((text-en "Hello world")
        (text-ko "안녕하세요"))
    ;; English: ~12.5 chars/sec
    (should (>= (dawa-tts-chunk-estimate-duration text-en "en") 0.5))
    ;; Korean: ~10 chars/sec
    (should (>= (dawa-tts-chunk-estimate-duration text-ko "ko") 0.5))))

(ert-deftest test-dawa-tts-chunk-text-basic ()
  "Test basic text chunking."
  (with-temp-buffer
    (insert "Hello world. This is a test.")
    (let ((chunks (dawa-tts-chunk-text "Hello world. This is a test."
                                       (point-min) (current-buffer) "en")))
      (should (> (length chunks) 0))
      (should (listp chunks))
      ;; Each chunk should have (start end text) format
      (dolist (chunk chunks)
        (should (= (length chunk) 3))
        (should (numberp (nth 0 chunk)))
        (should (numberp (nth 1 chunk)))
        (should (stringp (nth 2 chunk)))))))

;;; Interactive Multilingual Tests

;;;###autoload
(defun dawa-tts-test-multilingual ()
  "Interactive test for multilingual synthesis.
Tests various languages with sample text."
  (interactive)
  (let ((samples '(("English" "en" "Hello world! This is a test.")
                   ("Korean" "ko" "안녕하세요 세계! 테스트입니다.")
                   ("Japanese" "ja" "こんにちは世界！テストです。")
                   ("Russian" "ru" "Привет мир! Это тест.")
                   ("Arabic" "ar" "مرحبا بالعالم!")
                   ("Spanish" "es" "¡Hola mundo! Esta es una prueba.")
                   ("French" "fr" "Bonjour le monde! Ceci est un test.")
                   ("Auto-detect" "na" "Language-agnostic mode test."))))

    (with-current-buffer (get-buffer-create "*dawa-tts-test*")
      (erase-buffer)
      (insert "# Dawa-TTS Multilingual Test\n\n")
      (insert "Click on a language to test synthesis:\n\n")

      (dolist (sample samples)
        (let ((name (nth 0 sample))
              (lang (nth 1 sample))
              (text (nth 2 sample)))
          (insert-button name
                         'action (lambda (_)
                                   (message "Testing %s..." name)
                                   (condition-case err
                                       (progn
                                         (require 'dawa-tts)
                                         (dawa-tts-speak text lang)
                                         (message "%s: OK" name))
                                     (error (message "%s: FAILED - %s" name
                                                   (error-message-string err)))))
                         'follow-link t)
          (insert (format " - %s\n" text))))

      (insert "\n---\n\nOr select text below and use M-x dawa-tts-speak-region:\n\n")

      (dolist (sample samples)
        (let ((name (nth 0 sample))
              (text (nth 2 sample)))
          (insert (format "%s: %s\n" name text))))

      (goto-char (point-min))
      (switch-to-buffer (current-buffer))
      (help-mode))))

(provide 'test-dawa-tts)
;;; test-dawa-tts.el ends here
