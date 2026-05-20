;;; dawa-tts-chunk.el --- Text chunking for dawa-tts -*- lexical-binding: t -*-

;; Copyright (C) 2025 Sangjee Dondrub

;; Author: Sangjee Dondrub
;; Keywords: multimedia, tts
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))

;;; Commentary:

;; Semantic text chunking for dawa-tts with language-aware boundaries.
;; Chunks text into manageable segments for synthesis and highlighting.

;;; Code:

(require 'dawa-tts-lang)

(defcustom dawa-tts-chunk-max-length 300
  "Maximum length of a text chunk in characters.
Shorter for CJK languages (120), longer for others (300)."
  :type 'integer
  :group 'dawa-tts)

(defcustom dawa-tts-chunk-min-length 50
  "Minimum length of a text chunk in characters.
Chunks shorter than this will be combined with adjacent chunks."
  :type 'integer
  :group 'dawa-tts)

(defun dawa-tts-chunk--get-max-length (lang)
  "Get maximum chunk length for LANG.
CJK languages (ko, ja, zh) use 120 chars, others use 300."
  (if (member lang '("ko" "ja" "zh"))
      120
    300))

(defun dawa-tts-chunk--split-by-paragraphs (text start buffer)
  "Split TEXT into paragraphs starting at START in BUFFER.
Returns list of (start end text) for each paragraph."
  (let ((paragraphs nil)
        (current-pos start))
    (with-current-buffer buffer
      (save-excursion
        (goto-char start)
        (let ((text-end (+ start (length text))))
          (while (< (point) text-end)
            (let ((para-start (point)))
              ;; Find next paragraph boundary (blank line)
              (if (re-search-forward "^[[:space:]]*$" text-end t)
                  (progn
                    (beginning-of-line)
                    (let* ((para-end (point))
                           (para-text (buffer-substring-no-properties para-start para-end)))
                      (when (string-match-p "[^[:space:]]" para-text)
                        (push (list para-start para-end para-text) paragraphs))
                      (forward-line 1)))
                ;; No more paragraph breaks, take rest of text
                (let* ((para-end text-end)
                       (para-text (buffer-substring-no-properties para-start para-end)))
                  (when (string-match-p "[^[:space:]]" para-text)
                    (push (list para-start para-end para-text) paragraphs))
                  (goto-char text-end))))))))
    (nreverse paragraphs)))

(defun dawa-tts-chunk--split-by-sentences (text start buffer)
  "Split TEXT into sentences starting at START in BUFFER.
Returns list of (start end text) for each sentence."
  (let ((sentences nil))
    (with-current-buffer buffer
      (save-excursion
        (goto-char start)
        (let ((text-end (+ start (length text))))
          (while (< (point) text-end)
            (let ((sent-start (point)))
              (forward-sentence)
              (let* ((sent-end (min (point) text-end))
                     (sent-text (buffer-substring-no-properties sent-start sent-end)))
                (when (> sent-end sent-start)
                  (push (list sent-start sent-end sent-text) sentences))))))))
    (nreverse sentences)))

(defun dawa-tts-chunk--combine-small-chunks (chunks min-length)
  "Combine adjacent CHUNKS that are smaller than MIN-LENGTH.
Returns new list of chunks with (start end text) format."
  (if (null chunks)
      nil
    (let ((result nil)
          (current-chunk (car chunks)))
      (dolist (next-chunk (cdr chunks))
        (let ((current-text (nth 2 current-chunk))
              (next-text (nth 2 next-chunk)))
          (if (< (length current-text) min-length)
              ;; Combine with next chunk
              (setq current-chunk
                    (list (nth 0 current-chunk)
                          (nth 1 next-chunk)
                          (concat current-text " " next-text)))
            ;; Current chunk is large enough, save it
            (push current-chunk result)
            (setq current-chunk next-chunk))))
      ;; Don't forget the last chunk
      (push current-chunk result)
      (nreverse result))))

(defun dawa-tts-chunk--split-long-chunk (chunk max-length)
  "Split CHUNK if it exceeds MAX-LENGTH.
CHUNK is (start end text). Returns list of chunks."
  (let ((start (nth 0 chunk))
        (end (nth 1 chunk))
        (text (nth 2 chunk)))
    (if (<= (length text) max-length)
        (list chunk)
      ;; Need to split - try to split at sentence boundaries
      (let ((chunks nil)
            (current-start start)
            (current-text "")
            (words (split-string text)))
        (dolist (word words)
          (let ((new-text (if (string-empty-p current-text)
                              word
                            (concat current-text " " word))))
            (if (<= (length new-text) max-length)
                (setq current-text new-text)
              ;; Would exceed max, save current and start new
              (when (not (string-empty-p current-text))
                (let ((chunk-end (+ current-start (length current-text))))
                  (push (list current-start chunk-end current-text) chunks)
                  (setq current-start chunk-end)))
              (setq current-text word))))
        ;; Save last chunk
        (when (not (string-empty-p current-text))
          (push (list current-start end current-text) chunks))
        (nreverse chunks)))))

(defun dawa-tts-chunk-text (text start buffer &optional lang)
  "Chunk TEXT starting at START in BUFFER for language LANG.
Returns list of (start end text) for each chunk.
Chunks are optimized for TTS synthesis and highlighting:
- Respect paragraph boundaries
- Split at sentence boundaries
- Combine small chunks
- Split overly long chunks
- Language-aware max length (120 for CJK, 300 for others)"
  (let* ((language (or lang (dawa-tts-lang-detect text)))
         (max-length (dawa-tts-chunk--get-max-length language))
         (min-length dawa-tts-chunk-min-length))

    ;; Strategy:
    ;; 1. Split by paragraphs first (preserve structure)
    ;; 2. For each paragraph, split by sentences
    ;; 3. Combine sentences into chunks up to max-length
    ;; 4. Combine chunks smaller than min-length
    ;; 5. Split chunks larger than max-length

    (let ((paragraphs (dawa-tts-chunk--split-by-paragraphs text start buffer))
          (all-chunks nil))

      (dolist (para paragraphs)
        (let* ((para-start (nth 0 para))
               (para-end (nth 1 para))
               (para-text (nth 2 para))
               (sentences (dawa-tts-chunk--split-by-sentences para-text para-start buffer))
               (para-chunks nil)
               (current-chunk-start nil)
               (current-chunk-text ""))

          ;; Combine sentences into chunks
          (dolist (sent sentences)
            (let ((sent-text (nth 2 sent)))
              (if (null current-chunk-start)
                  ;; Start new chunk
                  (setq current-chunk-start (nth 0 sent)
                        current-chunk-text sent-text)
                ;; Try to add to current chunk
                (let ((new-text (concat current-chunk-text " " sent-text)))
                  (if (<= (length new-text) max-length)
                      (setq current-chunk-text new-text)
                    ;; Would exceed max, save current and start new
                    (push (list current-chunk-start
                                (+ current-chunk-start (length current-chunk-text))
                                current-chunk-text)
                          para-chunks)
                    (setq current-chunk-start (nth 0 sent)
                          current-chunk-text sent-text))))))

          ;; Save last chunk
          (when current-chunk-start
            (push (list current-chunk-start
                        (+ current-chunk-start (length current-chunk-text))
                        current-chunk-text)
                  para-chunks))

          ;; Add paragraph chunks to all chunks
          (setq all-chunks (append all-chunks (nreverse para-chunks)))))

      ;; Post-processing: combine small chunks and split large ones
      (let ((processed-chunks (dawa-tts-chunk--combine-small-chunks all-chunks min-length)))
        (let ((final-chunks nil))
          (dolist (chunk processed-chunks)
            (setq final-chunks (append final-chunks
                                       (dawa-tts-chunk--split-long-chunk chunk max-length))))
          final-chunks)))))

(defun dawa-tts-chunk-estimate-duration (chunk-text lang)
  "Estimate audio duration in seconds for CHUNK-TEXT in LANG.
Uses language-specific speech rates."
  (let* ((char-count (length chunk-text))
         ;; Speech rates vary by language
         ;; CJK: ~10 chars/sec, Latin: ~12.5 chars/sec
         (chars-per-sec (if (member lang '("ko" "ja" "zh"))
                            10.0
                          12.5))
         (base-duration (/ char-count chars-per-sec)))
    (max 0.5 base-duration)))  ; Minimum 0.5s per chunk

(provide 'dawa-tts-chunk)
;;; dawa-tts-chunk.el ends here
