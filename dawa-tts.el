;;; dawa-tts.el --- Text-to-speech using Supertonic TTS -*- lexical-binding: t -*-

;; Copyright (C) 2025 Sangjee Dondrub

;; Author: Sangjee Dondrub
;; Keywords: multimedia, tts, speech
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))

;;; Commentary:

;; dawa-tts provides text-to-speech synthesis using the Supertonic TTS engine.
;; Supertonic is a lightning-fast, on-device TTS system powered by ONNX Runtime
;; that can generate speech up to 167× faster than real-time.
;;
;; Features:
;; - Ultra-fast TTS synthesis (< 2 seconds for typical sentences)
;; - Multiple voice styles (10 voices: M1-M5, F1-F5)
;; - On-device processing (no cloud, complete privacy)
;; - Natural text handling (numbers, dates, currency, etc.)
;; - Automatic audio playback

;; Usage:
;;
;;   (require 'dawa-tts)
;;   (dawa-tts-speak "Hello from Emacs")
;;   (dawa-tts-speak-region (point-min) (point-max))
;;
;; Issues:
;;
;; Module could not be opened: "/Users/sangjee/.emacs.d/etc/lisp/dawa-tts/dawa-tts-module.dylib"
;; FIXED:
;; brew reinstall re2

;;; Code:

;;; Module Auto-compilation

(defvar dawa-tts--module-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing dawa-tts files.")

(defvar dawa-tts--module-file
  (expand-file-name
   (concat "dawa-tts-module" module-file-suffix)
   dawa-tts--module-dir)
  "Path to compiled dynamic module.")

(defun dawa-tts--module-needs-compilation-p ()
  "Check if the module needs to be compiled.
Returns t if:
- Module doesn't exist
- Module is older than source files
- CMakeLists.txt is newer than module"
  (or (not (file-exists-p dawa-tts--module-file))
      (let ((module-time (float-time (file-attribute-modification-time
                                      (file-attributes dawa-tts--module-file))))
            (source-files (list
                          (expand-file-name "dawa-tts-module.cpp" dawa-tts--module-dir)
                          (expand-file-name "lib/supertonic.cpp" dawa-tts--module-dir)
                          (expand-file-name "lib/supertonic.h" dawa-tts--module-dir)
                          (expand-file-name "CMakeLists.txt" dawa-tts--module-dir))))
        (cl-some (lambda (source)
                   (when (file-exists-p source)
                     (> (float-time (file-attribute-modification-time
                                    (file-attributes source)))
                        module-time)))
                 source-files))))

(defun dawa-tts--compile-module ()
  "Compile the dawa-tts module using CMake.
This is called automatically when the module is missing or out of date."
  (message "dawa-tts: Compiling module...")
  (let* ((default-directory dawa-tts--module-dir)
         (build-dir (expand-file-name "build" dawa-tts--module-dir))
         (compile-commands
          (format "mkdir -p %s && cd %s && cmake .. && cmake --build . --config Release"
                  (shell-quote-argument build-dir)
                  (shell-quote-argument build-dir))))
    (with-temp-buffer
      (let ((exit-code (call-process-shell-command compile-commands nil (current-buffer))))
        (if (= exit-code 0)
            (progn
              (message "dawa-tts: Module compiled successfully")
              (when (file-exists-p dawa-tts--module-file)
                t))
          (error "dawa-tts: Module compilation failed:\n%s" (buffer-string)))))))

(defun dawa-tts--ensure-module-compiled ()
  "Ensure the dawa-tts module is compiled before loading."
  (when (dawa-tts--module-needs-compilation-p)
    (if (yes-or-no-p "dawa-tts module needs compilation. Compile now? ")
        (dawa-tts--compile-module)
      (error "dawa-tts: Module not compiled. Run `M-x dawa-tts-compile` to compile manually"))))

;;;###autoload
(defun dawa-tts-compile ()
  "Manually compile the dawa-tts module."
  (interactive)
  (dawa-tts--compile-module))

;; Auto-compile and load module
(dawa-tts--ensure-module-compiled)
(require 'dawa-tts-module)
(require 'dawa-tts-lang)
(require 'dawa-tts-chunk)

;;; Configuration

(defgroup dawa-tts nil
  "Text-to-speech using Supertonic TTS."
  :group 'multimedia
  :prefix "dawa-tts-")

(defcustom dawa-tts-voice-style "F1"
  "Default voice style.
Available voices: M1, M2, M3, M4, M5 (male), F1, F2, F3, F4, F5 (female).
F5 & M5 are British."
  :type '(choice (const "M1") (const "M2") (const "M3") (const "M4") (const "M5")
                 (const "F1") (const "F2") (const "F3") (const "F4") (const "F5"))
  :group 'dawa-tts)

(defcustom dawa-tts-inference-steps 5
  "Number of diffusion inference steps (2-10).
Higher values produce better quality but slower synthesis.
Recommended values: 2-5 for speed, 5-10 for quality."
  :type 'integer
  :group 'dawa-tts)

(defcustom dawa-tts-speed 1.05
  "Speech speed multiplier (0.5-2.0).
1.0 = normal speed, < 1.0 = slower, > 1.0 = faster.
Recommended range: 0.9-1.5"
  :type 'float
  :group 'dawa-tts)

(defcustom dawa-tts-auto-play t
  "Automatically play generated audio after synthesis."
  :type 'boolean
  :group 'dawa-tts)

(defcustom dawa-tts-pre-buffer-count 2
  "Number of chunks to pre-synthesize before starting playback.
Set to -1 to pre-synthesize ALL chunks before playback begins.
With the default value of 2, the first two chunks are synthesized
before playback starts, eliminating the pause between sections.
Remaining chunks are synthesized on-demand during playback."
  :type 'integer
  :group 'dawa-tts)

(defcustom dawa-tts-assets-dir
  (expand-file-name "assets"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Path to assets directory containing ONNX models and voice styles."
  :type 'directory
  :group 'dawa-tts)

(defcustom dawa-tts-player-command "afplay"
  "Command to play WAV audio files.
On macOS: \"afplay\"
On Linux: \"aplay\" or \"paplay\" (PulseAudio)"
  :type 'string
  :group 'dawa-tts)

(defcustom dawa-tts-highlight-text t
  "Highlight text being spoken."
  :type 'boolean
  :group 'dawa-tts)

(defface dawa-tts-highlight-face
  '((t :background "yellow" :foreground "black"))
  "Face for highlighting text being spoken."
  :group 'dawa-tts)

;;; Internal State

(defvar dawa-tts--initialized nil
  "Whether TTS engine is initialized.")

(defvar dawa-tts--current-process nil
  "Current audio playback process.")

(defvar dawa-tts--temp-files nil
  "List of temporary WAV files to clean up.")

(defvar dawa-tts--current-overlay nil
  "Overlay highlighting the text being spoken.")

(defvar dawa-tts--source-buffer nil
  "Buffer containing the text being spoken.")

(defvar dawa-tts--text-position nil
  "Position (start . end) of text being spoken.")

(defvar dawa-tts--chunk-positions nil
  "List of chunk positions (start end text) for progressive highlighting.")

(defvar dawa-tts--current-chunk-index 0
  "Index of currently highlighted chunk.")

(defvar dawa-tts--highlight-timer nil
  "Timer for progressive chunk highlighting.
Deprecated: playback-driven highlighting is now used instead.")

(defvar dawa-tts--synthesized-wavs nil
  "Alist of (chunk-index . wav-path) for pre-synthesized chunks.")

;;; Helper Functions

(defun dawa-tts--make-overlay (start end)
  "Create overlay to highlight text from START to END."
  (dawa-tts--remove-overlay)
  (when (and dawa-tts-highlight-text
             (buffer-live-p (current-buffer)))
    (let ((ov (make-overlay start end)))
      (overlay-put ov 'face 'dawa-tts-highlight-face)
      (overlay-put ov 'dawa-tts t)
      (setq dawa-tts--current-overlay ov)
      (setq dawa-tts--source-buffer (current-buffer))
      (setq dawa-tts--text-position (cons start end)))))

(defun dawa-tts--remove-overlay ()
  "Remove the current highlight overlay."
  (when dawa-tts--current-overlay
    (delete-overlay dawa-tts--current-overlay)
    (setq dawa-tts--current-overlay nil)
    (setq dawa-tts--source-buffer nil)
    (setq dawa-tts--text-position nil)))

(defun dawa-tts--estimate-audio-duration (text)
  "Estimate audio duration in seconds for TEXT.
Based on typical speech rate and current speed setting."
  (let* ((char-count (length text))
         ;; Typical synthesis: ~1000 chars/sec at speed 1.0
         ;; Real-time factor: 0.012 (generates 1s audio in 0.012s)
         ;; Average speech rate: ~150 words/min = 2.5 words/sec
         ;; Average word length: ~5 chars, so ~12.5 chars/sec of audio
         (base-duration (/ char-count 12.5))
         ;; Adjust for speed setting
         (adjusted-duration (/ base-duration dawa-tts-speed)))
    adjusted-duration))

;;; Core Functions

;;;###autoload
(defun dawa-tts-init ()
  "Initialize the TTS engine.
Loads ONNX models and prepares the inference runtime.
This is called automatically on first use."
  (interactive)
  (unless dawa-tts--initialized
    (let ((onnx-dir (expand-file-name "onnx" dawa-tts-assets-dir)))
      (unless (file-directory-p onnx-dir)
        (error "ONNX models not found at %s. Please run: git clone https://huggingface.co/Supertone/supertonic assets" onnx-dir))

      (message "Initializing dawa-tts...")
      (if (dawa-tts-module-init onnx-dir)
          (progn
            (setq dawa-tts--initialized t)
            (dawa-tts-load-voice dawa-tts-voice-style)
            (message "dawa-tts initialized successfully with voice %s" dawa-tts-voice-style))
        (error "Failed to initialize dawa-tts. Check ONNX models in %s" onnx-dir)))))

;;;###autoload
(defun dawa-tts-load-voice (voice)
  "Load VOICE style (e.g., F1, M2).
Available voices: M1-M5 (male), F1-F5 (female)."
  (interactive (list (completing-read "Voice: " (dawa-tts-list-voices)
                                       nil t nil nil dawa-tts-voice-style)))
  (dawa-tts--ensure-initialized)
  (let ((voice-path (expand-file-name
                     (format "voice_styles/%s.json" voice)
                     dawa-tts-assets-dir)))
    (unless (file-exists-p voice-path)
      (error "Voice file not found: %s" voice-path))

    (message "Loading voice %s..." voice)
    (if (dawa-tts-module-load-voice voice-path)
        (progn
          (setq dawa-tts-voice-style voice)
          (message "Voice %s loaded successfully" voice))
      (error "Failed to load voice: %s" voice))))

(defun dawa-tts--normalize-language (lang)
  "Normalize language code LANG for Supertonic compatibility.
Maps 'zh' (Chinese) to 'na' (language-agnostic) since Chinese
is not officially supported by Supertonic v3."
  (if (equal lang "zh")
      "na"
    lang))

;;;###autoload
(defun dawa-tts-speak (text &optional lang)
  "Synthesize and speak TEXT in language LANG.
LANG defaults to auto-detected language or `dawa-tts-lang-default'.
Uses current voice style and synthesis parameters."
  (interactive "sText to speak: ")
  (dawa-tts--ensure-initialized)

  (when (string-empty-p text)
    (user-error "Text cannot be empty"))

  ;; Determine and normalize language
  (let ((language (dawa-tts--normalize-language
                   (or lang
                       dawa-tts-lang-override
                       (dawa-tts-lang-detect text)))))
    (message "Synthesizing speech (lang: %s)..." language)
    (let* ((wav-path (dawa-tts-module-synthesize
                      text
                      language
                      dawa-tts-inference-steps
                      dawa-tts-speed
                      nil))  ; nil = auto-generate temp path
           (success (and wav-path (stringp wav-path) (file-exists-p wav-path))))
      (if success
          (progn
            (push wav-path dawa-tts--temp-files)
            (message "Generated: %s" wav-path)
            (when dawa-tts-auto-play
              (dawa-tts-play-file wav-path)))
        (error "Failed to synthesize speech")))))

;;;###autoload
(defun dawa-tts-speak-word ()
  "Speak the word at point with visual highlighting."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'word)))
    (if bounds
        (progn
          (dawa-tts--make-overlay (car bounds) (cdr bounds))
          (dawa-tts-speak (thing-at-point 'word t)))
      (user-error "No word at point"))))

;;;###autoload
(defun dawa-tts-speak-sentence ()
  "Speak the sentence at point with visual highlighting."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'sentence)))
    (if bounds
        (progn
          (dawa-tts--make-overlay (car bounds) (cdr bounds))
          (dawa-tts-speak (thing-at-point 'sentence t)))
      (user-error "No sentence at point"))))

(defun dawa-tts--normalize-text (text buffer)
  "Normalize TEXT from BUFFER for TTS processing.
In org-mode buffers, hard-wrapped lines (single newlines within a
paragraph) are joined, while real paragraph breaks (two or more
consecutive newlines) are preserved."
  (with-current-buffer buffer
    (if (derived-mode-p 'org-mode)
        ;; Org-mode: join hard-wrapped lines, keep paragraph breaks
        (with-temp-buffer
          (insert text)
          (goto-char (point-min))
          ;; Replace sequences of 2+ newlines with a unique marker
          (while (re-search-forward "\n\n\n+" nil t)
            (replace-match "\n\n"))
          ;; Join hard-wrapped lines: single newline followed by non-empty,
          non-heading text
          (goto-char (point-min))
          (while (re-search-forward "\n" nil t)
            (save-excursion
              (let ((next-char (char-after)))
                (when (and next-char
                           (not (memq next-char '(?\n ?*)))
                           (not (looking-at-p "[ \t]*$")))
                  ;; This is a hard wrap, join with space
                  (delete-char -1)
                  ;; Don't add space if previous char is already whitespace
                  (unless (or (= (point) (point-min))
                              (memq (char-before (point)) '(?\s ?\t)))
                    (insert " "))))))
          (buffer-string))
      ;; Non-org-mode: collapse 3+ newlines to 2
      (replace-regexp-in-string "\n\n\n+" "\n\n" text))))

;;;###autoload
(defun dawa-tts-speak-region (start end)
  "Speak text in region from START to END with chunk highlighting."
  (interactive "r")
  (if (use-region-p)
      (let* ((text (dawa-tts--normalize-text
                    (buffer-substring-no-properties start end)
                    (current-buffer)))
             (lang (or dawa-tts-lang-override
                       (dawa-tts-lang-detect text)))
             (chunk-positions (dawa-tts-chunk-text text start (current-buffer) lang)))
        ;; Store source buffer before synthesis
        (setq dawa-tts--source-buffer (current-buffer))
        ;; Process chunks sequentially
        (if chunk-positions
            (dawa-tts--speak-chunks chunk-positions lang)
          ;; Fallback: speak entire text if no chunks
          (dawa-tts-speak text lang)))
    (user-error "No active region")))

;;;###autoload
(defun dawa-tts-speak-buffer ()
  "Speak entire buffer with chunk highlighting."
  (interactive)
  (let* ((text (dawa-tts--normalize-text (buffer-string) (current-buffer)))
         (lang (or dawa-tts-lang-override
                   (dawa-tts-lang-detect text)))
         (chunk-positions (dawa-tts-chunk-text text (point-min) (current-buffer) lang)))
    ;; Store source buffer before synthesis
    (setq dawa-tts--source-buffer (current-buffer))
    ;; Process chunks sequentially
    (if chunk-positions
        (dawa-tts--speak-chunks chunk-positions lang)
      ;; Fallback: speak entire text if no chunks
      (dawa-tts-speak text lang))))

(defun dawa-tts--speak-chunks (chunks lang)
  "Speak CHUNKS sequentially in language LANG with pre-synthesis.
Pre-synthesizes `dawa-tts-pre-buffer-count' chunks before playback
starts, then synthesizes remaining chunks on-demand during playback."
  (dawa-tts--ensure-initialized)
  (dawa-tts-stop)  ; Stop any current playback

  ;; Store chunks and language for sequential processing
  (setq dawa-tts--chunk-positions chunks)
  (setq dawa-tts--current-chunk-index 0)
  (setq dawa-tts--chunk-language lang)
  (setq dawa-tts--synthesized-wavs nil)

  ;; Determine how many chunks to pre-synthesize
  (let* ((total (length chunks))
         (pre-count (if (< dawa-tts-pre-buffer-count 0)
                        total
                      (min dawa-tts-pre-buffer-count total))))
    ;; Pre-synthesize first N chunks
    (dotimes (i pre-count)
      (let* ((chunk (nth i chunks))
             (text (nth 2 chunk))
             (norm-lang (dawa-tts--normalize-language lang))
             (wav (dawa-tts-module-synthesize
                   text norm-lang
                   dawa-tts-inference-steps dawa-tts-speed nil)))
        (if (and wav (stringp wav) (file-exists-p wav))
            (progn
              (push wav dawa-tts--temp-files)
              (push (cons i wav) dawa-tts--synthesized-wavs))
          (error "Failed to synthesize chunk %d" (1+ i)))))

    ;; Show status message
    (if (>= dawa-tts-pre-buffer-count 0)
        (message "Speaking %d chunks (pre-buffered %d)..."
                 total pre-count)
      (message "Speaking %d chunks (all pre-synthesized)..." total))

    ;; Start playback from chunk 0
    (dawa-tts--play-chunk-from-queue)))

(defvar dawa-tts--chunk-language nil
  "Language code for current chunk processing.")

(defun dawa-tts--play-chunk-from-queue ()
  "Play the next chunk from the synthesized queue.
If the chunk was pre-synthesized, play it immediately.
Otherwise, synthesize it first then play."
  (if (>= dawa-tts--current-chunk-index (length dawa-tts--chunk-positions))
      ;; All chunks done
      (progn
        (message "Finished speaking all chunks")
        (dawa-tts--remove-overlay))
    (let* ((idx dawa-tts--current-chunk-index)
           (wav (cdr (assoc idx dawa-tts--synthesized-wavs)))
           (chunk (nth idx dawa-tts--chunk-positions))
           (start (nth 0 chunk))
           (end (nth 1 chunk))
           (text (nth 2 chunk)))

      ;; Highlight current chunk, trimming leading/trailing whitespace
      (when (and dawa-tts-highlight-text
                 (buffer-live-p dawa-tts--source-buffer))
        (with-current-buffer dawa-tts--source-buffer
          (if (string-match "[^[:space:]]" text)
              (let* ((hl-start (+ start (match-beginning 0)))
                     ;; Greedy match up to last non-whitespace
                     (hl-end (+ start (if (string-match ".*[^[:space:]]" text)
                                          (match-end 0)
                                        (match-beginning 0)))))
                (dawa-tts--make-overlay hl-start hl-end))
            ;; All whitespace, skip highlight
            (message "Chunk %d is all whitespace, skipping" (1+ idx)))))

      (if wav
          ;; Already pre-synthesized, play immediately
          (progn
            (setq dawa-tts--synthesized-wavs
                  (assq-delete-all idx dawa-tts--synthesized-wavs))
            (setq dawa-tts--current-process
                  (start-process "dawa-tts-player" nil dawa-tts-player-command wav))
            (set-process-sentinel dawa-tts--current-process
                                  #'dawa-tts--chunk-player-sentinel))
        ;; Not yet synthesized - synthesize then play
        (let* ((text (nth 2 chunk))
               (lang (dawa-tts--normalize-language dawa-tts--chunk-language))
               (new-wav (dawa-tts-module-synthesize
                         text lang
                         dawa-tts-inference-steps dawa-tts-speed nil)))
          (if (and new-wav (stringp new-wav) (file-exists-p new-wav))
              (progn
                (push new-wav dawa-tts--temp-files)
                (setq dawa-tts--current-process
                      (start-process "dawa-tts-player" nil dawa-tts-player-command new-wav))
                (set-process-sentinel dawa-tts--current-process
                                      #'dawa-tts--chunk-player-sentinel))
            (error "Failed to synthesize chunk %d" (1+ idx))))))))

(defun dawa-tts--chunk-player-sentinel (process event)
  "Sentinel for chunk-by-chunk audio player PROCESS.
EVENT is the process event string."
  (when (memq (process-status process) '(exit signal))
    (setq dawa-tts--current-process nil)
    (setq dawa-tts--current-chunk-index (1+ dawa-tts--current-chunk-index))
    (dawa-tts--play-chunk-from-queue)))

(defun dawa-tts-play-file (wav-path)
  "Play WAV-PATH using system audio player."
  (dawa-tts-stop)  ; Stop any current playback
  (setq dawa-tts--current-process
        (start-process "dawa-tts-player" nil dawa-tts-player-command wav-path))
  (set-process-sentinel dawa-tts--current-process
                        #'dawa-tts--player-sentinel))

;;;###autoload
(defun dawa-tts-stop ()
  "Stop current audio playback and remove highlight."
  (interactive)
  (when (and dawa-tts--current-process
             (process-live-p dawa-tts--current-process))
    (kill-process dawa-tts--current-process)
    (setq dawa-tts--current-process nil))
  ;; Reset chunk processing state
  (setq dawa-tts--chunk-positions nil)
  (setq dawa-tts--current-chunk-index 0)
  (setq dawa-tts--chunk-language nil)
  (setq dawa-tts--synthesized-wavs nil)
  ;; Clean up highlighting
  (when dawa-tts--highlight-timer
    (cancel-timer dawa-tts--highlight-timer)
    (setq dawa-tts--highlight-timer nil))
  (dawa-tts--remove-overlay)
  (message "Stopped playback"))

(defun dawa-tts--player-sentinel (process event)
  "Sentinel for audio player PROCESS.
EVENT is the process event string."
  (when (memq (process-status process) '(exit signal))
    (setq dawa-tts--current-process nil)
    ;; Remove overlay when playback finishes
    (dawa-tts--remove-overlay)
    (when (string-match-p "finished" event)
      (message "Playback finished"))))

(defun dawa-tts--ensure-initialized ()
  "Ensure TTS engine is initialized."
  (unless dawa-tts--initialized
    (dawa-tts-init)))

;;;###autoload
(defun dawa-tts-list-voices ()
  "Return list of available voice styles."
  (dawa-tts--ensure-initialized)
  (let ((voice-dir (expand-file-name "voice_styles" dawa-tts-assets-dir)))
    (dawa-tts-module-list-voices voice-dir)))

;;;###autoload
(defun dawa-tts-cleanup-temp-files ()
  "Clean up temporary WAV files."
  (interactive)
  (dolist (file dawa-tts--temp-files)
    (when (file-exists-p file)
      (delete-file file)))
  (setq dawa-tts--temp-files nil)
  (message "Cleaned up %d temporary files" (length dawa-tts--temp-files)))

;;;###autoload
(defun dawa-tts-toggle-highlight ()
  "Toggle text highlighting during speech."
  (interactive)
  (setq dawa-tts-highlight-text (not dawa-tts-highlight-text))
  (message "Text highlighting %s" (if dawa-tts-highlight-text "enabled" "disabled")))

;;;###autoload
(defun dawa-tts-benchmark ()
  "Run a benchmark synthesis test."
  (interactive)
  (dawa-tts--ensure-initialized)
  (let* ((test-text "The quick brown fox jumps over the lazy dog.")
         (start-time (current-time))
         (wav-path (dawa-tts-module-synthesize
                    test-text
                    "en"  ; English for benchmark
                    dawa-tts-inference-steps
                    dawa-tts-speed
                    nil))
         (end-time (current-time))
         (elapsed (float-time (time-subtract end-time start-time))))
    (message "Synthesized %d characters in %.2f seconds (%.1f chars/sec)"
             (length test-text) elapsed (/ (length test-text) elapsed))
    (when wav-path
      (push wav-path dawa-tts--temp-files))))

;;; Cleanup on exit

(add-hook 'kill-emacs-hook
          (lambda ()
            (when dawa-tts--initialized
              (dawa-tts-module-cleanup)
              (dawa-tts-cleanup-temp-files))))

(provide 'dawa-tts)
;;; dawa-tts.el ends here
