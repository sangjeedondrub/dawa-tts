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

;;; Configuration

(defgroup dawa-tts nil
  "Text-to-speech using Supertonic TTS."
  :group 'multimedia
  :prefix "dawa-tts-")

(defcustom dawa-tts-voice-style "F1"
  "Default voice style.
Available voices: M1, M2, M3, M4, M5 (male), F1, F2, F3, F4, F5 (female)."
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

(defvar dawa-tts--sentence-positions nil
  "List of sentence positions (start . end) for progressive highlighting.")

(defvar dawa-tts--current-sentence-index 0
  "Index of currently highlighted sentence.")

(defvar dawa-tts--highlight-timer nil
  "Timer for progressive sentence highlighting.")

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

(defun dawa-tts--parse-sentence-positions (text start)
  "Parse TEXT into sentence positions starting from START.
Returns a list of (sentence-start . sentence-end) cons cells.
Uses Emacs built-in sentence navigation for accurate parsing."
  (let ((positions nil))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((sentence-start (+ start (1- (point)))))
          (forward-sentence)
          (let ((sentence-end (+ start (1- (point)))))
            (when (> sentence-end sentence-start)
              (push (cons sentence-start sentence-end) positions))))))
    (nreverse positions)))

(defun dawa-tts--parse-sentence-positions-with-text (text start buffer)
  "Parse TEXT into sentence positions with text content.
START is the starting position in BUFFER.
Returns a list of (start end . text) elements for progressive highlighting."
  (let ((positions nil))
    (with-current-buffer buffer
      (save-excursion
        (goto-char start)
        (let ((text-end (+ start (length text))))
          (while (and (< (point) text-end) (not (eobp)))
            (let ((sentence-start (point)))
              (forward-sentence)
              (let* ((sentence-end (min (point) text-end))
                     (sentence-text (buffer-substring-no-properties sentence-start sentence-end)))
                (when (> sentence-end sentence-start)
                  (push (list sentence-start sentence-end sentence-text) positions))))))))
    (nreverse positions)))

(defun dawa-tts--estimate-sentence-duration (sentence-text)
  "Estimate audio duration in seconds for a single SENTENCE-TEXT.
Based on character count and speech rate."
  (let* ((char-count (length sentence-text))
         ;; Average speech rate: ~12.5 chars/sec of audio
         (base-duration (/ char-count 12.5))
         ;; Adjust for speed setting
         (adjusted-duration (/ base-duration dawa-tts-speed)))
    (max 0.5 adjusted-duration)))  ; Minimum 0.5s per sentence

(defun dawa-tts--start-progressive-highlight (sentence-positions-with-text)
  "Start progressive sentence highlighting.
SENTENCE-POSITIONS-WITH-TEXT is a list of (start . end . text) elements,
where each element contains the start position, end position, and text content
of a sentence. Each sentence's duration is estimated individually for better accuracy."
  (dawa-tts--stop-progressive-highlight)
  (when (and sentence-positions-with-text dawa-tts-highlight-text
             (buffer-live-p dawa-tts--source-buffer))
    (setq dawa-tts--sentence-positions sentence-positions-with-text)
    (setq dawa-tts--current-sentence-index 0)
    ;; Highlight first sentence immediately
    (dawa-tts--highlight-current-sentence)
    ;; Schedule remaining sentences based on individual durations
    (dawa-tts--schedule-next-sentence)))

(defun dawa-tts--schedule-next-sentence ()
  "Schedule the next sentence highlighting based on current sentence duration."
  (when (and dawa-tts--sentence-positions
             (< dawa-tts--current-sentence-index (length dawa-tts--sentence-positions)))
    (let* ((current-sentence (nth dawa-tts--current-sentence-index dawa-tts--sentence-positions))
           (sentence-text (nth 2 current-sentence))  ; Third element is the text
           (duration (dawa-tts--estimate-sentence-duration sentence-text)))
      ;; Schedule next sentence after estimated duration
      (setq dawa-tts--highlight-timer
            (run-at-time duration nil #'dawa-tts--highlight-next-sentence)))))

(defun dawa-tts--highlight-current-sentence ()
  "Highlight the sentence at current index."
  (when (and dawa-tts--sentence-positions
             (< dawa-tts--current-sentence-index (length dawa-tts--sentence-positions))
             (buffer-live-p dawa-tts--source-buffer))
    (with-current-buffer dawa-tts--source-buffer
      (let* ((sentence-pos (nth dawa-tts--current-sentence-index dawa-tts--sentence-positions))
             (start (nth 0 sentence-pos))
             (end (nth 1 sentence-pos)))
        (dawa-tts--make-overlay start end)))))

(defun dawa-tts--highlight-next-sentence ()
  "Advance to next sentence and highlight it."
  (setq dawa-tts--current-sentence-index (1+ dawa-tts--current-sentence-index))
  (if (< dawa-tts--current-sentence-index (length dawa-tts--sentence-positions))
      (progn
        (dawa-tts--highlight-current-sentence)
        (dawa-tts--schedule-next-sentence))
    ;; Done with all sentences, stop the timer
    (dawa-tts--stop-progressive-highlight)))

(defun dawa-tts--stop-progressive-highlight ()
  "Stop progressive highlighting timer."
  (when dawa-tts--highlight-timer
    (cancel-timer dawa-tts--highlight-timer)
    (setq dawa-tts--highlight-timer nil))
  (setq dawa-tts--sentence-positions nil)
  (setq dawa-tts--current-sentence-index 0))

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

;;;###autoload
(defun dawa-tts-speak (text)
  "Synthesize and speak TEXT.
Uses current voice style and synthesis parameters."
  (interactive "sText to speak: ")
  (dawa-tts--ensure-initialized)

  (when (string-empty-p text)
    (user-error "Text cannot be empty"))

  (message "Synthesizing speech...")
  (let* ((wav-path (dawa-tts-module-synthesize
                    text
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
      (error "Failed to synthesize speech"))))

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

;;;###autoload
(defun dawa-tts-speak-region (start end)
  "Speak text in region from START to END with progressive sentence highlighting."
  (interactive "r")
  (if (use-region-p)
      (let* ((text (buffer-substring-no-properties start end))
             (sentence-positions (dawa-tts--parse-sentence-positions-with-text
                                 text start (current-buffer))))
        ;; Store source buffer before synthesis
        (setq dawa-tts--source-buffer (current-buffer))
        ;; Start progressive sentence highlighting
        (when sentence-positions
          (dawa-tts--start-progressive-highlight sentence-positions))
        ;; Speak the text
        (dawa-tts-speak text))
    (user-error "No active region")))

;;;###autoload
(defun dawa-tts-speak-buffer ()
  "Speak entire buffer with progressive sentence highlighting."
  (interactive)
  (let* ((text (buffer-string))
         (sentence-positions (dawa-tts--parse-sentence-positions-with-text
                             text (point-min) (current-buffer))))
    ;; Store source buffer before synthesis
    (setq dawa-tts--source-buffer (current-buffer))
    ;; Start progressive sentence highlighting
    (when sentence-positions
      (dawa-tts--start-progressive-highlight sentence-positions))
    ;; Speak the text
    (dawa-tts-speak text)))

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
    (setq dawa-tts--current-process nil)
    (dawa-tts--stop-progressive-highlight)
    (dawa-tts--remove-overlay)
    (message "Stopped playback")))

(defun dawa-tts--player-sentinel (process event)
  "Sentinel for audio player PROCESS.
EVENT is the process event string."
  (when (memq (process-status process) '(exit signal))
    (setq dawa-tts--current-process nil)
    ;; Stop progressive highlighting and remove overlay when playback finishes
    (dawa-tts--stop-progressive-highlight)
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
