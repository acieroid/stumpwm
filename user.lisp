;; Copyright (C) 2003 Shawn Betts
;;
;;  This file is part of stumpwm.
;;
;; stumpwm is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
 
;; stumpwm is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
 
;; You should have received a copy of the GNU General Public License
;; along with this software; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
;; Boston, MA 02111-1307 USA

;; Commentary:
;;
;; Window Manager commands that users can use to manipulate stumpwm
;; and write custos.
;;
;; Code:

(in-package :stumpwm)

(defstruct command
  name args fn)

(defvar *command-hash* (make-hash-table :test 'equal)
  "A list of interactive stumpwm commands.")

(defmacro define-stumpwm-command (name (screen &rest args) &body body)
  `(setf (gethash ,name *command-hash*)
	 (make-command :name ,name
		       :args ',args
		       :fn (lambda (,screen ,@(mapcar 'first args))
			      ,@body))))

(defun set-key-binding (key mod cmd)
  "Bind KEY to the function FN."
  (setf (gethash (list key mod) *key-bindings*) cmd))

(defun focus-next-window (screen)
  (focus-forward screen (frame-sort-windows screen
					    (screen-current-frame screen))))

(defun focus-prev-window (screen)
  (focus-forward screen
		 (reverse
		  (frame-sort-windows screen
				      (screen-current-frame screen)))))

(define-stumpwm-command "next" (screen)
  (focus-next-window screen))

(define-stumpwm-command "prev" (screen)
  (focus-prev-window screen))

;; In the future, this window will raise the window into the current
;; frame.
(defun focus-forward (screen window-list)
 "Set the focus to the next item in window-list from the focused window."
  ;; The window with focus is the "current" window, so find it in the
  ;; list and give that window focus
  (let* ((w (xlib:input-focus *display*))
	 (wins (member w window-list))
	 nw)
    (print w)
    (print window-list)
    (print wins)
    ;;(assert wins)
    (setf nw (if (null (cdr wins))
		 ;; If the last window in the list is focused, then
		 ;; focus the first one.
		 (car window-list)
	       ;; Otherwise, focus the next one in the list.
	       (cadr wins)))
    (when nw
      (frame-raise-window screen (window-frame screen nw) nw))))

(defun delete-current-window (screen)
  "Send a delete event to the current window."
  (when (screen-current-window screen)
    (delete-window (screen-current-window screen))))

(define-stumpwm-command "delete" (screen)
  (delete-current-window screen))

(defun kill-current-window (screen)
  "Kill the client of the current window."
  (when (screen-current-window screen)
    (kill-window (screen-current-window screen))))

(define-stumpwm-command "kill" (screen)
  (kill-current-window screen))

(defun banish-pointer (screen)
  "Move the pointer to the lower right corner of the screen"
  (warp-pointer screen
		(1- (screen-width screen))
		(1- (screen-height screen))))

(define-stumpwm-command "banish" (screen)
  (banish-pointer screen))

(defun echo-windows (screen)
  "Print a list of the windows to the screen."
  (let* ((wins (sort-windows screen))
	 (highlight (position (screen-current-window screen) wins :test #'xlib:window-equal))
	 (names (mapcar (lambda (w)
			  (funcall *window-format-fn* screen w)) wins)))
    (if (null wins)
	(echo-string screen "No Managed Windows")
      (echo-string-list screen names highlight))))

(define-stumpwm-command "windows" (screen)
  (echo-windows screen))

(defun echo-date (screen)
  "Print the output of the 'date' command to the screen."
  (let* ((month-names
	  #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
	 (day-names
	  #("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun"))
	 (date-string (multiple-value-bind (sec min hour dom mon year dow)
			 (get-decoded-time)
		       (format nil "~A ~A ~A ~A:~2,,,'0@A:~2,,,'0@A ~A"
			       (aref day-names dow)
			       (aref month-names (- mon 1))
			       dom hour min sec year))))
    (echo-string screen date-string)))

(define-stumpwm-command "time" (screen)
  (echo-date screen))

(defun select-window (screen query)
  "Read input from the user and go to the selected window."
    (let (match)
      (labels ((match (win)
		      (let* ((wname (window-name win))
			     (end (min (length wname) (length query))))
			(string-equal wname query :end1 end :end2 end))))
	(unless (null query)
	  (setf match (find-if #'match (screen-mapped-windows screen))))
	(when match
	  (focus-window match)))))

(define-stumpwm-command "select" (screen (win :string "Select: "))
  (select-window screen win))

(defun select-window-number (screen num)
  (labels ((match (win)
		  (= (window-number screen win) num)))
    (let ((win (find-if #'match (screen-mapped-windows screen))))
      (when win
	(frame-raise-window screen (window-frame screen win) win)))))

(defun other-window (screen)
  (let* ((f (screen-current-frame screen))
	 (wins (frame-windows screen f))
	 (win (second wins)))
  (when win
    (frame-raise-window screen (window-frame screen win) win))))

(define-stumpwm-command "other" (screen)
  (other-window screen))

(defun run-shell-command (cmd)
  (run-prog *shell-program* :args (list "-c" cmd) :wait nil))

(define-stumpwm-command "exec" (screen (cmd :rest "/bin/sh -c "))
  (run-shell-command cmd))

(defun horiz-split-frame (screen)
  (split-frame screen (lambda (f) (split-frame-h screen f))))

(define-stumpwm-command "hsplit" (screen)
  (horiz-split-frame screen))

(defun vert-split-frame (screen)
  (split-frame screen (lambda (f) (split-frame-v screen f))))

(define-stumpwm-command "vsplit" (screen)
  (vert-split-frame screen))

(defun remove-split (screen)
  (let* ((s (sibling (screen-frame-tree screen)
		    (screen-current-frame screen)))
	 ;; grab a leaf from the sibling
	 (l (tree-accum-fn s (lambda (x y) x) (lambda (x) x))))
    ;; Only remove the current frame if it has a sibling
    (format t "~S~%" s)
    (when s
      (format t "~S~%" l)
      ;; Move the windows from the removed frame to it's sibling
      (migrate-frame-windows screen (screen-current-frame screen) l)
      ;; If the frame has no window, give it the current window of
      ;; the current frame.
      (unless (frame-window l)
	(setf (frame-window l)
	      (frame-window (screen-current-frame screen))))
      ;; Unsplit
      (setf (screen-frame-tree screen)
	    (remove-frame screen
			  (screen-frame-tree screen)
			  (screen-current-frame screen)))
      ;; update the current frame and sync it's windows
      (setf (screen-current-frame screen) l)
      (sync-frame-windows screen l)
      (frame-raise-window screen l (frame-window l)))))

(define-stumpwm-command "remove" (screen)
  (remove-split screen))

(define-stumpwm-command "only" (screen)
  ())

(defun focus-frame-sibling (screen)
  (let* ((sib (sibling (screen-frame-tree screen)
		      (screen-current-frame screen))))
    (when sib
      (focus-frame screen (tree-accum-fn sib (lambda (x y) x) 'identity)))))

(define-stumpwm-command "sibling" (screen)
  (focus-frame-sibling screen))

(defun choose-frame-by-number (screen)
  "show a number in the corner of each frame and wait for the user to
select one. Returns the selected frame or nil if aborted."
  (let* ((wins (draw-frame-numbers screen))
	 (ch (read-one-char screen))
	 (num (read-from-string (string ch))))
    (format t "read ~S ~S~%" ch num)
    (mapc #'xlib:destroy-window wins)
    (when (and (char>= ch #\0)
	       (char<= ch #\9))
      (find-if (lambda (x)
		 (= num (frame-number x)))
	       (screen-frames screen)))))

(define-stumpwm-command "fselect" (screen (f :frame))
  (focus-frame screen f))

(defun eval-line (screen cmd)
  (echo-string screen
	       (handler-case (prin1-to-string (eval (read-from-string cmd)))
			     (error (c)
				    (format nil "~A" c)))))

(define-stumpwm-command "eval" (screen (cmd :rest "Eval: "))
  (eval-line screen cmd))

;; Simple command & arg parsing
(defun split-by-one-space (string)
  "Returns a list of substrings of string divided by ONE space each.
Note: Two consecutive spaces will be seen as if there were an empty
string between them."
  (loop for i = 0 then (1+ j)
	as j = (position #\Space string :start i)
	collect (subseq string i j)
	while j))

(defun parse-and-run-command (input screen)
  "Parse the command and its arguments given the commands argument
specifications then execute it. Returns a string or nil if user
aborted."
  (macrolet ((skip-spaces (string-list)
			  ;; A nice'n'gross side-effect loop
			  `(do ((s #1=(car ,string-list) #1#))
			       ((or (null s)
				    (string/= s "")) ,string-list)
			     (pop ,string-list)))
	     (pop-or-read (l prompt scrn)
			  `(or (pop ,l)
			       ;; If prompt is nil, then the argument is
			       ;; considered optional.
			       (unless (null ,prompt)
				 (or (read-one-line ,scrn ,prompt)
				     ;; read-one-line returns nil when the user aborts
				     (throw 'error "Abort."))))))
    (let (str cmd arg-specs args)
      ;; Catch parse errors
      (catch 'error
	;; Setup the input
	(setf str (split-by-one-space input))
	;; Make sure we have a valid command
	(skip-spaces str)
	(setf cmd (gethash (pop str) *command-hash*))
	(if cmd
	    (setf arg-specs (command-args cmd))
	  (throw 'error "Command not found."))
	;; Create a list of args to pass to the function. If str is
	;; snarfed and we have more args, then prompt the user for a
	;; value.
	(format t "str: ~A~%" str)
	(setf args (mapcar (lambda (spec)
			     (let ((type (second spec))
				   (prompt (third spec)))
			       (skip-spaces str)
			       (case type
				 (:number 
				  (let ((n (pop-or-read str prompt screen)))
				    (when n
				      (parse-integer n))))
				 (:string 
				  (pop-or-read str prompt screen))
				 (:frame
				  (let ((arg (pop str)))
				    (if arg
					(let ((num (parse-integer arg)))
					  (or (find-if (lambda (x)
							 (= num (frame-number x)))
						       (screen-frames screen))
					      (throw 'error "Frame not found.")))
				      (or (choose-frame-by-number screen)
					  (throw 'error "Abort.")))))
				  (:rest
				      (if (null str)
					  (when prompt
					    (or (read-one-line screen prompt)
						(throw 'error "Abort.")))
					(prog1
					    (format nil "~{~A~^ ~}" str)
					  (setf str nil))))
				 (t (throw 'error "Bad argument type")))))
			     arg-specs))
	;; Did the whole string get parsed? (get rid of trailing
	;; spaces)
	(format t "arguments: ~S~%" args)
	(unless (null (skip-spaces str))
	  (throw 'error (format nil "Trailing garbage: ~{~A~^ ~}" str)))
	;; Success
	(apply (command-fn cmd) screen args)))))

(defun interactive-command (cmd screen)
  "exec cmd and echo the result."
  (let ((result (handler-case (parse-and-run-command cmd screen)
			      (error (c)
				     (format nil "~A" c)))))
    (when (stringp result)
      (echo-string screen result))))

(define-stumpwm-command "colon" (screen (cmd :rest ": "))
  (interactive-command cmd screen))

(defun pull-window-by-number (screen n)
  "Pull window N from another frame into the current frame and focus it."
  (labels ((match (win)
		  (= (window-number screen win) n)))
    (let ((win (find-if #'match (screen-mapped-windows screen))))
      (when win
	(setf (window-frame screen win) (screen-current-frame screen))
	(sync-frame-windows screen (screen-current-frame screen))
	(frame-raise-window screen (screen-current-frame screen) win)))))

(define-stumpwm-command "pull" (screen (n :number "Pull: "))
  (pull-window-by-number screen n))

(defun send-meta-key (screen)
  "Send the prefix key"
  (send-fake-key (screen-current-window screen) *prefix-key* *prefix-modifiers*))

(define-stumpwm-command "meta" (screen)
  (send-meta-key screen))

(defun renumber (screen nt)
  "Renumber the current window"
  (let ((nf (window-number screen (screen-current-window screen)))
	(win (find-if #'(lambda (win)
			  (= (window-number screen win) nt))
		      (screen-mapped-windows screen))))
    ;; Is it already taken?
    (if win
	(progn
	  ;; swap the window numbers
	  (setf (window-number screen win) nf)
	  (setf (window-number screen (screen-current-window screen)) nt))
      ;; Just give the window the number
      (setf (window-number screen (screen-current-window screen)) nt)))
  (echo-string screen "Number expected"))

(define-stumpwm-command "number" (screen (n :number "Number: "))
  (renumber screen n))

(define-stumpwm-command "reload" (screen)
  (echo-string screen "Reloading StumpWM...")
  (asdf:operate 'asdf:load-op :stumpwm)
  (echo-string screen "Reloading StumpWM...Done."))

;; Trivial function
(define-stumpwm-command "abort" (screen))

;;(define-stumpwm-command "escape"

(defun set-default-bindings ()
  "Put the default bindings in the key-bindings hash table."
  (set-key-binding #\c '() "xterm")
  (set-key-binding #\e '() "exec emacs")
  (set-key-binding #\n '() "next")
  (set-key-binding #\n '(:control) "next")
  (set-key-binding #\Space '() "next")
  (set-key-binding #\p '() "prev")
  (set-key-binding #\p '(:control) "prev")
  (set-key-binding #\w '() "windows")
  (set-key-binding #\w '(:control) "windows")
  (set-key-binding #\k '() "delete")
  (set-key-binding #\k '(:control) "delete")
  (set-key-binding #\K '() "kill")
  (set-key-binding #\b '() "banish")
  (set-key-binding #\b '(:control) "banish")
  (set-key-binding #\a '() "time")
  (set-key-binding #\a '(:control) "time")
  (set-key-binding #\' '() "select")
  (set-key-binding #\t '(:control) "other")
  (set-key-binding #\! '() "exec")
  (set-key-binding #\g '(:control) "abort")
  (set-key-binding #\0 '() "pull 0")
  (set-key-binding #\1 '() "pull 1")
  (set-key-binding #\2 '() "pull 2")
  (set-key-binding #\3 '() "pull 3")
  (set-key-binding #\4 '() "pull 4")
  (set-key-binding #\5 '() "pull 5")
  (set-key-binding #\6 '() "pull 6")
  (set-key-binding #\7 '() "pull 7")
  (set-key-binding #\8 '() "pull 8")
  (set-key-binding #\9 '() "pull 9")
  (set-key-binding #\r '() "remove")
  (set-key-binding #\s '() "hsplit")
  (set-key-binding #\S '() "vsplit")
  (set-key-binding #\o '() "sibling")
  (set-key-binding #\f '() "fselect")
  (set-key-binding #\t '() "meta")
  (set-key-binding #\N '(:control) "number")
  (set-key-binding #\; '() "colon")
  (set-key-binding #\: '() "eval"))