;;; undo-hl.el --- Highlight undo/redo  -*- lexical-binding: t; -*-

;; Author: Yuan Fu <casouri@gmail.com>
;; URL: https://github.com/casouri/undo-hl
;; Version: 1.0
;; Keywords: undo
;; Package-Requires: ((emacs "26.0"))

;;; This file is NOT part of GNU Emacs

;;; Commentary:
;;
;; Sometimes in a long undo chain where Emacs jumps to a position, I
;; can’t tell whether the undo operation just moved to this position
;; or it has also deleted some text. This package is meant to
;; alleviate that confusion: it flashes the to-be-deleted text before
;; deleting so I know what is happening.
;;
;; This package is pretty efficient, I can hold down undo button and
;; the highlight doesn’t slow down the operation.
;;

;;; Code:
;;
;; I tried to use pulse.el but it wasn’t fast enough (eg, when holding
;; down C-.), so I used a more economical implementation. Instead of a
;; flash, the highlight will persist until the next command.
;;
;; Some package, like aggressive-indent, modifies the buffer when the
;; user makes modifications (in ‘post-command-hook’, timer, etc).
;; Their modification invokes ‘before-change-functions’ just like a
;; user modification. Naturally we don’t want to highlight those
;; automatic modifications made not by the user. How do we do that?
;; Essentially we generate a ticket for each command loop
;; (‘undo-hl--hook-can-run’). One user modification = one command loop
;; = one ticket = one highlight. Whoever runs first gets to use that
;; ticket, and all other subsequent invocation of
;; `undo-hl--before-change’ must not do anything. We only constraint
;; the before hooks, ie, deletion highlight because deletion highlight
;; is blocking, while insertion highlight is not. Consecutive
;; insertion highlight only shows the last one, but consecutive
;; deletion highlight will show every highlight for
;; ‘undo-hl-wait-duration’ and can be very annoying.

(defgroup undo-hl nil
  "Custom group for undo-hl."
  :group 'undo)

(defvar undo-hl-ov nil)

(defface undo-hl-delete '((t . (:inherit diff-refine-removed)))
  "Face used for highlighting the deleted text.")

(defface undo-hl-insert '((t . (:inherit diff-refine-added)))
  "Face used for highlighting the inserted text.")

(defcustom undo-hl-undo-commands '(undo undo-only undo-redo undo-fu-only-undo undo-fu-only-redo evil-undo evil-redo)
  "Commands in this list are considered undo commands.
Undo-hl only run before and after undo commands."
  :type '(list function))

(defcustom undo-hl-wait-duration 99
  "Undo-hl flashes the to-be-deleted text for this number of seconds.
Note that insertion highlight is not affected by this option."
  :type 'number)

(defcustom undo-hl-mininum-edit-size 2
  "Modifications smaller than this size is ignored.
This is a useful heuristic that avoids small text property
changes that often obstruct the real edit. Keep it at least 2."
  ;; How does text property change obstruct highlighting the real
  ;; edit: First, we only highlight one change every command loop;
  ;; second, a single undo could make multiple changes, including
  ;; moving point, changing text property, inserting/deleting text.
  ;; Both text prop change and ins/del invokes
  ;; ‘after/before-change-functions’, so if there is a text prop edit
  ;; before the real text edit in the undo history, undo-hl will
  ;; highlight the text prop change (often of size 1 at EOL) and
  ;; ignore the following text change. A simple check of size
  ;; eliminates most of such problems caused by both jit-lock and
  ;; ws-bulter.
  :type 'integer)

(defun undo-hl--after-change (beg end len)
  "Highlight the inserted region after an undo.
This is to be called from ‘after-change-functions’, see its doc
for BEG, END and LEN."
  (when (and (memq this-command undo-hl-undo-commands)
             ;; (eq len 0)
             (>= (- end beg) undo-hl-mininum-edit-size))
    ;; This makes sure all edits are highlighted
    ;; (run-with-timer nil nil
    ;;                 (lambda () (let ((ov (make-overlay beg end)))
    ;;                              (overlay-put ov 'face 'undo-hl-insert)
    ;;                              (sit-for undo-hl-wait-duration)
    ;;                              (delete-overlay ov))))
    (let ((ov (make-overlay beg end)))
      (overlay-put ov 'face 'undo-hl-insert)
      (overlay-put ov 'priority 999)
      (push ov undo-hl-ov))))

(defun undo-hl--before-change (beg end)
  "Highlight the to-be-deleted region before an undo.
This is to be called from ‘before-change-functions’, see its doc
for BEG and END."
  (when (and (memq this-command undo-hl-undo-commands)
             (>= (- end beg) undo-hl-mininum-edit-size))
    (let ((ov (make-overlay beg beg)))
      (overlay-put ov 'face 'undo-hl-delete)
      (overlay-put ov 'priority 999)
      (overlay-put ov 'before-string (propertize (buffer-substring-no-properties beg end) 'face 'undo-hl-delete))
      (push ov undo-hl-ov))))

(defun undo-hl--wait (&optional _)
  (when undo-hl-ov
    (sit-for undo-hl-wait-duration)
    (mapc 'delete-overlay undo-hl-ov)
    (setq undo-hl-ov nil)))

;;;###autoload
(define-minor-mode undo-hl-mode
  "Highlight undo. Note that this is a local minor mode.
I recommend only enabling this for text-editing modes."
  :lighter " UH"
  :group 'undo
  (if undo-hl-mode
      (progn
        (add-hook 'before-change-functions #'undo-hl--before-change -50 t)
        (add-hook 'after-change-functions #'undo-hl--after-change -50 t)
        (add-hook 'post-command-hook #'undo-hl--wait -49 t))
    (remove-hook 'before-change-functions #'undo-hl--before-change t)
    (remove-hook 'after-change-functions #'undo-hl--after-change t)
    (remove-hook 'post-command-hook #'undo-hl--wait t)
    ))

(provide 'undo-hl)

;;; undo-hl.el ends here
