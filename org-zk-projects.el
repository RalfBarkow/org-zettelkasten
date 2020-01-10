(require 'org-el-cache)

(defun org-zk-projects-by-state (state)
  (org-el-cache-filter-files
   (lambda (entry)
     (equal
      (org-el-cache-entry-keyword entry org-zk-gtd-state-keyword)
      state))))

(defun org-zk-projects-all ()
  (org-el-cache-filter-files
   (lambda (entry)
     (member
      (org-el-cache-entry-keyword entry org-zk-gtd-state-keyword)
      org-zk-gtd-states))))

(defun org-zk-projects-active ()
  (org-zk-projects-by-state "active"))

(defun org-zk-projects-someday ()
  (org-zk-projects-by-state "someday"))

(defun org-zk-projects-planning ()
  (org-zk-projects-by-state "planning"))

(defun org-zk-projects-cancelled ()
  (org-zk-projects-by-state "cancelled"))

(defun org-zk-projects-done ()
  (org-zk-projects-by-state "done"))

(defun org-zk-projects-buffer ()
  (get-buffer-create "*Org Projects*"))

(defvar org-zk-projects-format
  (vector
   (list "State, Pri" 12 t)
   (list "Title" 30 t)
   (list "NEXT" 4 t)
   (list "TODO" 4 t)))

(defun org-zk-projects-count-todo-keyword (entry keyword)
  (let ((headlines (plist-get entry :headlines)))
    (count-if
     (lambda (hl) (string= (plist-get hl :todo-keyword) keyword))
     headlines)))

(defun org-zk-projects-tabulate (cached-files)
  (mapcar
   (lambda (entry)
     (list
      entry
      (vector
       (concat
        (org-el-cache-entry-keyword entry "GTD_STATE" org-zk-default-file-state)
        " "
        (org-el-cache-entry-keyword entry "GTD_PRIORITY" org-zk-default-file-priority))
       (org-el-cache-entry-keyword entry "TITLE" (plist-get entry :file))
       (number-to-string (org-zk-projects-count-todo-keyword entry "NEXT"))
       (number-to-string (org-zk-projects-count-todo-keyword entry "TODO")))))
   cached-files))

(define-derived-mode org-zk-projects-mode tabulated-list-mode "Org Projects"
  "Major mode for listing org gtd projects"
  (hl-line-mode))

(defun org-zk-projects-blocked-p (cached-file)
  (= 0 (org-zk-projects-count-next cached-file)))

(defun org-zk-projects-filter-blocked (projects)
  (--filter (not (org-zk-projects-blocked-p it))
            projects))

(defun org-zk-projects ()
  (interactive)
  (let ((projects (org-zk-projects-filter-blocked (org-zk-projects-all))))
    (with-current-buffer (org-zk-projects-buffer)
      (setq tabulated-list-format org-zk-projects-format)
      (org-zk-projects-mode)
      (tabulated-list-init-header)
      (setq tabulated-list-entries (org-zk-projects-tabulate projects))
      (setq tabulated-list-sort-key (cons "State, Pri" nil))
      (tabulated-list-print)
      (switch-to-buffer (current-buffer)))))

(defun org-zk-projects-open ()
  "Open the file for the project under point"
  (interactive)
  (find-file (plist-get (tabulated-list-get-id) :file)))

(defun org-zk-projects-set-gtd-priority ()
  "Open the file for the project under point"
  (interactive)
  (org-zk-in-file (tabulated-list-get-id)
    (call-interactively 'org-zk-set-gtd-priority)))

(setq org-zk-projects-mode-map
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map tabulated-list-mode-map)
        (define-key map (kbd "RET") 'org-zk-projects-open)
        (define-key map (kbd ",") 'org-zk-projects-set-gtd-priority)
        map))

(provide 'org-zk-projects)
