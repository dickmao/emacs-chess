;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Code shared by all chess displays
;;
;; $Revision$

;;; Code:

(require 'chess-session)
(require 'chess-game)
(require 'chess-algebraic)
(require 'chess-fen)

(defgroup chess-display nil
  "Common code used by chess displays."
  :group 'chess)

(defcustom chess-display-use-faces t
  "If non-nil, provide colored faces for ASCII displays."
  :type 'boolean
  :group 'chess-display)

(defface chess-display-black-face
  '((((class color) (background light)) (:foreground "Green"))
    (((class color) (background dark)) (:foreground "Green"))
    (t (:bold t)))
  "*The face used for black pieces on the ASCII display."
  :group 'chess-display)

(defface chess-display-white-face
  '((((class color) (background light)) (:foreground "Yellow"))
    (((class color) (background dark)) (:foreground "Yellow"))
    (t (:bold t)))
  "*The face used for white pieces on the ASCII display."
  :group 'chess-display)

(defface chess-display-highlight-face
  '((((class color) (background light)) (:background "#add8e6"))
    (((class color) (background dark)) (:background "#add8e6")))
  "Face to use for highlighting pieces that have been selected."
  :group 'chess-display)

(defvar chess-display-draw-function nil)
(defvar chess-display-highlight-function nil)

(make-variable-buffer-local 'chess-display-draw-function)
(make-variable-buffer-local 'chess-display-highlight-function)

(defvar chess-display-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map)
    (set-keymap-parent map nil)

    (define-key map [(control ?i)] 'chess-display-invert)
    (define-key map [tab] 'chess-display-invert)

    (define-key map [??] 'describe-mode)
    (define-key map [?C] 'chess-display-clear-board)
    (define-key map [?E] 'chess-display-edit-board)
    (define-key map [?G] 'chess-display-restore-board)
    (define-key map [?F] 'chess-display-set-from-fen)
    (define-key map [?I] 'chess-display-invert)
    (define-key map [?S] 'chess-display-send-board)
    (define-key map [?X] 'chess-display-quit)
    (define-key map [?M] 'chess-display-manual-move)

    (define-key map [?<] 'chess-display-move-backward)
    (define-key map [?,] 'chess-display-move-backward)
    (define-key map [(meta ?<)] 'chess-display-move-first)
    (define-key map [?>] 'chess-display-move-forward)
    (define-key map [?.] 'chess-display-move-forward)
    (define-key map [(meta ?>)] 'chess-display-move-last)

    (define-key map [(meta ?w)] 'chess-display-copy-board)
    (define-key map [(control ?y)] 'chess-display-paste-board)

    (define-key map [(control ?l)] 'chess-display-redraw)

    (dolist (key '(?a ?b ?c ?d ?e ?f ?g ?h
		      ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8
		      ?r ?n ?b ?q ?k ?o))
      (define-key map (vector key) 'chess-keyboard-shortcut))
    (define-key map [backspace] 'chess-keyboard-shortcut-delete)

;;    (let ((keys '(?  ?p ?r ?n ?b ?q ?k ?P ?R ?N ?B ?Q ?K)))
;;      (while keys
;;	(define-key map (vector (car keys)) 'chess-display-set-piece)
;;	(setq keys (cdr keys))))

    (define-key map [(control ?m)] 'chess-display-select-piece)
    (define-key map [return] 'chess-display-select-piece)
    (cond
     ((featurep 'xemacs)
      (define-key map [(button1)] 'chess-display-mouse-select-piece)
      (define-key map [(button2)] 'chess-display-mouse-select-piece))
     (t
      (define-key map [mouse-1] 'chess-display-mouse-select-piece)
      (define-key map [mouse-2] 'chess-display-mouse-select-piece)))
    map)
  "The mode map used in a chessboard display buffer.")

(defvar chess-display-game)
(defvar chess-display-game-index)
(defvar chess-display-position)
(defvar chess-display-perspective)
(defvar chess-display-mode-line "")

(make-variable-buffer-local 'chess-display-game)
(make-variable-buffer-local 'chess-display-game-index)
(make-variable-buffer-local 'chess-display-position)
(make-variable-buffer-local 'chess-display-perspective)
(make-variable-buffer-local 'chess-display-mode-line)

;;; Code:

;;;###autoload
(defun chess-display (session buffer event &rest args)
  "This display module presents a standard chessboard.
See `chess-display-type' for the different kinds of displays."
  (cond
   ((eq event 'initialize)
    (let ((buf (generate-new-buffer "*Chessboard*")))
      (with-current-buffer buf
	(setq cursor-type nil
	      chess-display-draw-function (car args)
	      chess-display-highlight-function (cadr args)
	      chess-display-perspective
	      (chess-session-data session 'my-color))
	(chess-display-mode)
	buf)))
   ((eq event 'shutdown)
    (ignore
     (if (buffer-live-p buffer)
	 (kill-buffer buffer))))
   (t
    (ignore
     (with-current-buffer buffer
       (cond
	((eq event 'setup)
	 (setq cursor-type nil
	       chess-display-game (car args)
	       chess-display-game-index (chess-game-index (car args))
	       chess-display-position (chess-game-pos (car args)))
	 (funcall chess-display-draw-function))

	((eq event 'highlight)
	 ;; if they are unselecting the piece, just redraw
	 (if (eq (nth 2 args) 'unselected)
	     (funcall chess-display-draw-function)
	   (apply chess-display-highlight-function args)))

	((eq event 'move)
	 (assert (eq chess-display-game
		     (chess-session-data session 'current-game)))
	 (setq chess-display-game-index (chess-game-index chess-display-game)
	       chess-display-position (chess-game-pos chess-display-game))
	 (funcall chess-display-draw-function))

	(t
	 (funcall chess-display-draw-function)))

       (chess-display-set-modeline))))))

(defun chess-display-mode ()
  "A mode for displaying and interacting with a chessboard.
The key bindings available in this mode are:
\\{chess-display-mode-map}"
  (interactive)
  (setq major-mode 'chess-display-mode mode-name "Chessboard")
  (use-local-map chess-display-mode-map)
  (buffer-disable-undo)
  (setq buffer-auto-save-file-name nil
	mode-line-format 'chess-display-mode-line))

(defun chess-display-set-modeline ()
  "Set the modeline to reflect the current game position."
  (let ((color (chess-pos-side-to-move chess-display-position))
	(index chess-display-game-index))
    (if (= index 1)
	(setq chess-display-mode-line
	      (format "   %s   START" (if color "White" "BLACK")))
      (setq chess-display-mode-line
	    (concat
	     "  " (if color "White" "BLACK")
	     "   " (int-to-string (if (> index 1)
				      (/ index 2) (1+ (/ index 2))))
	     ". " (if color "... ")
	     (chess-game-ply-to-algebraic chess-display-game))))))

(defsubst chess-display-current-p ()
  "Return non-nil if the displayed chessboard reflects the current game.
This means that no editing is being done."
  (eq chess-display-position
      (chess-game-pos chess-display-game)))

(defun chess-display-invert ()
  "Invert the perspective of the current chess board."
  (interactive)
  (setq chess-display-perspective (not chess-display-perspective))
  (funcall chess-display-draw-function))

(defun chess-display-edit-board ()
  "Setup the current board for editing."
  (interactive)
  (when (chess-display-current-p)
    (setq cursor-type t
	  chess-display-position
	  (chess-pos-copy (chess-game-pos chess-display-game)))
    (message "Now editing board, use S to send...")))

(defun chess-display-restore-board ()
  "Setup the current board for editing."
  (interactive)
  (setq cursor-type nil
	chess-display-position (chess-game-pos chess-display-game)
	chess-display-game-index (chess-game-index chess-display-game))
  (funcall chess-display-draw-function))

(defun chess-display-clear-board ()
  "Setup the current board for editing."
  (interactive)
  (when (y-or-n-p "Really clear the chessboard? ")
    (chess-display-edit-board)
    (dotimes (rank 8)
      (dotimes (file 8)
	(chess-pos-set-piece chess-display-position (cons rank file) ? )))
    (funcall chess-display-draw-function)))

(defun chess-display-set-from-fen (fen)
  "Send the current board configuration to the user."
  (interactive "sSet from FEN string: ")
  (setq chess-display-position (chess-fen-to-pos fen))
  (funcall chess-display-draw-function))

(defun chess-display-send-board ()
  "Send the current board configuration to the user."
  (interactive)
  (chess-session-event chess-current-session 'setup
		       (chess-game-create chess-display-position)))

(defun chess-display-copy-board ()
  "Send the current board configuration to the user."
  (interactive)
  (let* ((x-select-enable-clipboard t)
	 (fen (chess-fen-from-pos chess-display-position)))
    (kill-new fen)
    (message "Copied board: %s" fen)))

(defun chess-display-paste-board ()
  "Send the current board configuration to the user."
  (interactive)
  (let* ((x-select-enable-clipboard t)
	 (fen (current-kill 0)))
    ;; jww (2001-06-26): not yet implemented
    (message "Pasted board: %s" fen)))

(defun chess-display-redraw ()
  "Just redraw the current display."
  (interactive)
  (funcall chess-display-draw-function))

(defun chess-display-set-piece ()
  "Set the piece under point to command character, or space for clear."
  (interactive)
  (unless (chess-display-current-p)
    (chess-pos-set-piece chess-display-position
			 (get-text-property (point) 'chess-coord)
			 last-command-char)
    (funcall chess-display-draw-function)))

(defun chess-display-quit ()
  "Quit the current game."
  (interactive)
  (chess-session-event chess-current-session 'shutdown))

(defun chess-display-manual-move (move)
  "Move a piece manually, using chess notation."
  (interactive
   (list (read-string
	  (format "%s(%d): "
		  (if (chess-pos-side-to-move chess-display-position)
		      "White" "Black")
		  (1+ (/ chess-display-game-index 2))))))
  (chess-session-event chess-current-session 'move
		       (chess-game-algebraic-to-ply chess-display-game move)))

(defun chess-display-set-current (dir)
  "Change the currently displayed board.
Direction may be - or +, to move forward or back, or t or nil to jump
to the end or beginning."
  (let ((index (cond ((eq dir ?-) (1- chess-display-game-index))
		     ((eq dir ?+) (1+ chess-display-game-index))
		     ((eq dir t) nil)
		     ((eq dir nil) 1))))
    (setq chess-display-position
	  (or (chess-game-pos chess-display-game index)
	      (error "You are already at the first or last position"))
	  chess-display-game-index
	  (or index (chess-game-index chess-display-game)))
    (funcall chess-display-draw-function)
    (chess-display-set-modeline)
    (if (chess-display-current-p)
	(message "This is the current position")
      (message "Use G or M-> to return to the current position"))))

(defun chess-display-move-backward ()
  (interactive)
  (chess-display-set-current ?-))

(defun chess-display-move-forward ()
  (interactive)
  (chess-display-set-current ?+))

(defun chess-display-move-first ()
  (interactive)
  (chess-display-set-current nil))

(defun chess-display-move-last ()
  (interactive)
  (chess-display-set-current t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Allow for quick entry of algebraic moves via keyboard
;;

(defvar chess-move-string nil)
(defvar chess-legal-moves-pos nil)
(defvar chess-legal-moves nil)

(defun chess-keyboard-shortcut-delete ()
  (interactive)
  (setq chess-move-string
	(substring chess-move-string 0
		   (1- (length chess-move-string)))))

(defun chess-keyboard-shortcut (&optional display-only)
  (interactive)
  (unless (memq last-command '(chess-keyboard-shortcut
			       chess-keyboard-shortcut-delete))
    (setq chess-move-string nil))
  (unless display-only
    (setq chess-move-string
	  (concat chess-move-string
		  (char-to-string (downcase last-command-char)))))
  (unless (and chess-legal-moves
	       (eq chess-display-position chess-legal-moves-pos))
    (let ((search-func (chess-game-search-func chess-display-game)))
      (setq chess-legal-moves-pos chess-display-position
	    chess-legal-moves
	    (sort (mapcar (function
			   (lambda (ply)
			     (chess-ply-to-algebraic ply nil search-func)))
		   (chess-legal-plies chess-display-position search-func))
		  'string-lessp))))
  (let ((moves
	 (mapcar (function
		  (lambda (move)
		    (let ((i 0) (x 0)
			  (l (length move))
			  (xl (length chess-move-string))
			  (match t))
		      (unless (or (and (equal chess-move-string "ok")
				       (equal move "O-O"))
				  (and (equal chess-move-string "oq")
				       (equal move "O-O-O")))
			(while (and (< i l) (< x xl))
			  (if (= (aref move i) ?x)
			      (setq i (1+ i)))
			  (if (/= (downcase (aref move i))
				  (aref chess-move-string x))
			      (setq match nil i l)
			    (setq i (1+ i) x (1+ x)))))
		      (if match move))))
		 chess-legal-moves)))
    (setq moves (delq nil moves))
    (cond
     ((= (length moves) 1)
      (chess-session-event
       chess-current-session 'move
       (chess-algebraic-to-ply chess-display-position (car moves)
			       (chess-game-search-func chess-display-game)))
      (setq chess-move-string nil
	    chess-legal-moves nil
	    chess-legal-moves-pos nil))
     ((null moves)
      (setq chess-move-string
	    (substring chess-move-string 0
		       (1- (length chess-move-string)))))
     (t
      (message "[%s] %s" chess-move-string
	       (mapconcat 'identity moves " "))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Manage a face cache for textual displays
;;

(defvar chess-display-face-cache '((t . t)))

(defsubst chess-display-get-face (color)
  (or (cdr (assoc color chess-display-face-cache))
      (let ((face (make-face 'chess-display-highlight)))
	(set-face-attribute face nil :background color)
	(add-to-list 'chess-display-face-cache (cons color face))
	face)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Mousing around on the chess-display
;;

(defvar chess-display-last-selected nil)

(make-variable-buffer-local 'chess-display-last-selected)

(defun chess-display-select-piece ()
  "Select the piece under the cursor.
Clicking once on a piece selects it; then click on the target location."
  (interactive)
  (let ((coord (get-text-property (point) 'chess-coord)))
    (when coord
      (if chess-display-last-selected
	  (let ((last-sel chess-display-last-selected)
		move-error)
	    ;; if they select the same square again, just deselect it
	    (if (/= (point) (car last-sel))
		(if (chess-display-current-p)
		    (chess-session-event
		     chess-current-session 'move
		     (chess-ply-create chess-display-position
				       (cadr last-sel) coord))
		  (chess-pos-move chess-display-position
				  (cadr last-sel) coord)
		  (funcall chess-display-draw-function))
	      ;; put the board back to rights
	      (funcall chess-display-draw-function))
	    (setq chess-display-last-selected nil)
	    (when move-error
	      (funcall chess-display-draw-function)
	      (error (error-message-string move-error))))
	(setq chess-display-last-selected (list (point) coord))
       ;; just as in a normal chess game, if you touch the piece, your
	;; opponent will see this
	(if (chess-display-current-p)
	    (chess-session-event chess-current-session
				 'highlight (point) coord 'selected)
	  (funcall chess-display-highlight-function
		   (point) coord 'selected))))))

(defun chess-display-mouse-select-piece (event)
  "Select the piece the user clicked on."
  (interactive "e")
  (cond ((fboundp 'event-window)	; XEmacs
	 (set-buffer (window-buffer (event-window event)))
	 (and (event-point event) (goto-char (event-point event))))
	((fboundp 'posn-window)		; Emacs
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))))
  (chess-display-select-piece))

(provide 'chess-display)

;;; chess-display.el ends here
