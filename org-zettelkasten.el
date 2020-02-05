(require 'org-el-cache)
(require 'ts)

(require 'org-zk-titlecase)
(require 'org-zk-time)
(require 'org-zk-clocking)
(require 'org-zk-repeat)
(require 'org-zk-task-list)
(require 'org-zk-calendar)
(require 'org-zk-dashboard)
(require 'org-zk-projects)
(require 'org-zk-derived-tasks)

;;; Configuration

(defvar org-zk-gtd-states
  '("active"
    "someday"
    "planning"
    "cancelled"
    "done"))

(defvar org-zk-default-file-priority "B")
(defvar org-zk-default-file-priorities '("A" "B" "C"))
(defvar org-zk-default-file-state "active")

(defvar org-zk-gtd-state-keyword "GTD_STATE")

;;; Helper Functions / Macros

(defmacro org-zk-in-file (path &rest body)
  "If there is a buffer visiting PATH, use it to evaluate BODY,
If not, open PATH in the background, evaluate BODY, then save it."
  (declare (indent defun))
  `(let ((buffer (find-buffer-visiting ,path)))
     (if buffer
         (with-current-buffer buffer ,@body)
       (with-current-buffer (find-file-noselect ,path)
         ,@body
         (save-buffer)
         (kill-buffer)))))

(defun org-zk--skip-keywords ()
  "Move to the beginning of a files content."
  (goto-char (point-min))
  (while (looking-at-p "^#+")
    (forward-line)))

(defun org-zk--beginning-of-main-content (file)
  "Find point at the beginning of the main content of FILE."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (org-zk--skip-keywords)
      (point))))


(defun org-zk-file-title (file)
  "If FILE is in the org cache, return its title,
if not, return its filename."
  (let ((file (expand-file-name file)))
    (or (org-el-cache-file-keyword file "TITLE") file)))

;;; Category Setup

(defun org-zk-escape-filename (str)
  (setq str (replace-regexp-in-string " " "_" str))
  (setq str (replace-regexp-in-string
             (rx (not (in "a-zA-Z0-9" "-" "_"))) "" str))
  (setq str (downcase str))
  str)

(defun org-zk-default-name-fn (title)
  (org-zk-escape-filename title))

(defun org-zk-default-setup-fn (title)
  (insert "#+TITLE: " title "\n")
  (insert "#+CREATED: ")
  (org-insert-time-stamp (current-time) t t)
  (insert "\n\n"))

(defvar org-zk-file-blacklist '("./" "../" ".git/"))

(defun org-zk-category-path (p) (plist-get p :path))
(defun org-zk-category-ignore-p (p) (plist-get p :ignore))
(defun org-zk-category-name-fn (p)
  (plist-get p :name-fn 'org-zk-default-name-fn))
(defun org-zk-category-setup-fn (p)
  (getf plist-get p :setup-fn 'org-zk-default-setup-fn))

(defun org-zk-category-for-file (filename)
  "Find the (sub)category FILENAME belongs to.
Returns NIL if FILENAME is not managed by org-zettelkasten."
  (seq-find
   (lambda (category)
     (string-prefix-p
      (expand-file-name (org-zk-category-path category))
      (expand-file-name filename)))
   org-zk-categories))

(defun org-zk-select-category (action)
  "Select a category by its name,
then call ACTION with the category that was selected."
  (interactive)
  (let ((collection
         (mapcar
          (lambda (c) (cons (plist-get c :name) c))
          org-zk-categories)))
    (ivy-read "Category: " collection :action action)))

(def-org-el-cache-file-hook category (file _el)
  `(:category ,(org-zk-category-for-file file)))

;;; Cache Setup

(if (fboundp 'ace-window)
    (defadvice ace-window (before other-frame-now activate)
      (when buffer-file-name (org-el-cache-process-buffer))))

;;; File Selection

(defun org-zk-files-with-titles ()
  "Returns an alist of entries (title . filename)"
  (org-el-cache-mapcan-files
   (lambda (entry)
  (let ((category (plist-get entry :category))
           (title (or (org-el-cache-entry-keyword entry "TITLE")
                      (plist-get entry :file))))
       (if category
    (list
            (cons
             (format "%s (%s)" title (org-zk-category-name category))
             (plist-get entry :file))))))))

(defvar org-zk-ivy-histoy nil)

(defun org-zk-select-file (action)
  (ivy-read
   "File: "
   (org-zk-files-with-titles)
   :history 'org-zk-ivy-history
   :action action))

(defun org-zk-open-file ()
  "Select a file, then open it"
  (interactive)
  (org-zk-select-file (lambda (selection) (find-file (cdr selection)))))

;;; Linking Files

(org-link-set-parameters
 "zk_parent"
 :complete #'org-file-complete-link
 :follow #'find-file)

(org-link-set-parameters
 "zk_child"
 :complete #'org-file-complete-link
 :follow #'find-file)

(org-link-set-parameters
 "zk_friend"
 :complete #'org-file-complete-link
 :follow #'find-file)

(defun org-zk-make-link (target type &optional title)
  (concat
   "[[zk_" type ":" target "]["
   (or title (org-zk-file-title target))
   "]]"))

(defun org-zk-link-file (&optional type)
  "Select a file, then insert an org-mode link to it,
If `ivy-immediate-return' is used,
creates a file with that title in category of the current file."
  (interactive)
  (org-zk-select-file
   (lambda (selection)
     (if (stringp selection)
         (let* ((title (org-zk-titlecase (string-trim selection)))
                (target (org-zk-create-file
                         title
                         (org-zk-category-for-file (buffer-file-name)))))
           (insert (org-zk-make-link target (or type "friend") title)))
       (insert (org-zk-make-link
                (cdr selection)
                (or type "friend")
                (org-zk-file-title (cdr selection))))))))

(defun org-zk-link-parent ()
  (interactive)
  (org-zk-link-file "parent"))

(defun org-zk-link-child ()
  (interactive)
  (org-zk-link-file "child"))

(defun org-zk-link-friend ()
  (interactive)
  (org-zk-link-file "friend"))

;;;; Finding Linked Files

(defun org-zk-files-linking-to (file)
  "Generate a list of files linking to FILE."
  (let ((file (expand-file-name file)))
    (org-el-cache-filter-files
     (lambda (cache-entry)
  (--any (string=
               (expand-file-name (plist-get it :path))
               file)
              (plist-get cache-entry :links))))))

(defun org-zk-files-linking-here ()
  "Generate a list of files linking to the current buffer."
  (org-zk-files-linking-to (buffer-file-name)))

;;;; Updating / Deleting Links

(defvar org-zk-link-re
  (rx
   "[[zk_"
   (group-n 1 (or "parent" "child" "friend"))
   ":"
   (group-n 2 (* (not (any "]"))))
   "]["
   (group-n 3 (* (not (any "]"))))
   "]]")
  "Regex matching zettelkasten links.
Groups:
1. type
2. target
3. text / title")

(defvar org-zk-deleted-link-text "(deleted)")

;; TODO: Jump to file for manual fixes
;;
;; NOTE: It's easier to parse the buffer again instead of adding link bounds
;; to the org cache and dealing with cache-incoherence problems.
(defun org-zk-delete-link (target)
  "Replace links to TARGET with their description.
If a link has no description, replace it with
  `org-zk-deleted-link-text'.
Link targets are compared using their *absolute* path."
  (let (links
        (dir (file-name-directory (buffer-file-name))))
    (org-element-map
        (org-element-parse-buffer)
        'link
      (lambda (link)
        (if (string=
             (expand-file-name (org-element-property :path link))
             (expand-file-name target))
            (push link links))))
    ;; LINKS is already in reverse order so its save to delete links
    ;; by their bounds
    (dolist (link links)
      (if (org-element-contents link)
          (progn
            (goto-char (org-element-property :begin link))
            (delete-region
             (org-element-property :begin link)
             (org-element-property :end link))
            (insert
             (org-element-interpret-data
              (org-element-contents link)))
            ;; NOTE: There is some weird issue with :end being set incorrectly,
            ;; if the link doesn't end at the end of a line
            (unless (eolp) (insert " ")))
        (progn
          (goto-char (org-element-property :begin link))
          (delete-region
           (org-element-property :begin link)
           (org-element-property :end link))
          ;; NOTE: There is some weird issue with :end being set incorrectly
            ;; if the link doesn't end at the end of a line
          (insert
           org-zk-deleted-link-text)
          (unless (eolp) (insert " ")))))
    links))

(defun org-zk-update-link (target target-new desc-new)
  "Update links to TARGET to point to TARGET-NEW and change their description to DESC-NEW. DESC-NEW is set for links without a description, too.
Link targets are compared using their *absolute* path.
If either TARGET-NEW or DESC-NEW is nil, that part of the link is left unchanged."
  (let (links
        (dir (file-name-directory (buffer-file-name))))
    (org-element-map
        (org-element-parse-buffer)
        'link
      (lambda (link)
        (if (string=
             (expand-file-name (org-element-property :path link))
             (expand-file-name target))
            (push link links))))
    ;; LINKS is already in reverse order so its save to delete links
    ;; by their bounds
    (dolist (link links)
      (if desc-new
          (org-element-set-contents link desc-new))
      (if target-new
          (org-element-put-property link :path target-new))
      (goto-char (org-element-property :begin link))
      (delete-region
       (org-element-property :begin link)
       ;; Because of the way `org-element-interpret-data' work, there
       ;; is no need to use a -1 here
       (org-element-property :end link))
      (insert (org-element-interpret-data link)))
    links))

;;;; TODO Linking External Resources

;; TODO: Get title from url
;; TODO: Replace to add links to a resources heading
(defun org-zk-add-yank-link ()
  "Check if the element in the clipboard / kill-ring is an URL,
if so, insert a link to it in the edge list, prompting for a description."
  (interactive)
  (if-let ((res (with-temp-buffer
                  (yank)
                  (thing-at-point 'url (point)))))
      (org-zk-add-plain-link res (read-string "Description: "))
    (message "Kill-ring contents are not a URL")))
;;; Creating / Renaming Files

(defun org-zk-read-title ()
  "Read a string to use as document title."
  (org-zk-titlecase (string-trim (read-string "Title: "))))

(defun org-zk-new-file ()
  "Create a new org zettelkasten file.
Prompts for a title, and a project, then uses the projects
name-fn to generate a filename."
  (interactive)
  (org-zk-select-category
   (lambda (category)
     (let* ((category (cdr category))
            (title (org-zk-read-title))
            (name-fn (org-zk-category-name-fn category))
            (setup-fn (org-zk-category-setup-fn category))
            (name (funcall name-fn title))
            (file (expand-file-name
                   (concat name ".org")
                   (org-zk-category-path category))))
       (if (file-exists-p file)
           (error "Aborting, file already exists: %s" file))
       (find-file file)
       (funcall setup-fn title)
       (save-buffer)))))

(defun org-zk-create-file (title category)
  "Create a new org zettelkasten file given its category and title.
Returns the name of the new file"
  (let* ((name-fn (org-zk-category-name-fn category))
         (setup-fn (org-zk-category-setup-fn category))
         (name (funcall name-fn title))
         (file (expand-file-name
                (concat name ".org")
                (org-zk-category-path category))))
    (if (file-exists-p file)
        (error "Aborting, file already exists: %s" file))
    (with-current-buffer (find-file-noselect file)
      (funcall setup-fn title)
      (save-buffer)
      (kill-buffer))
    file))

(defun org-zk-rename (title)
  "Rename the current zettel, prompting for a new TITLE."
  (interactive (list (org-zk-read-title)))
  (org-zk-keywords-set-or-add "TITLE" title)
  (let ((target (buffer-file-name)))
    (dolist (file (org-zk-files-linking-here))
      (org-zk-in-file (car file)
        (org-zk-update-link target nil title)))))

;;; Deleting / Slurping Files

(defun org-zk-delete-file (file)
  "Delete FILE, removing all links to it."
  (let ((file (expand-file-name file)))
    (dolist (entry (org-zk-files-linking-to file))
      (org-zk-in-file (plist-get entry :file)
        (org-zk-delete-link file)
        (save-buffer)
        (kill-buffer))))
  (delete-file file))

(defun org-zk--file-to-headline (file)
  "Convert the contents of FILE to a headline in the current
buffer"
  (org-insert-heading nil nil t)
  (insert (org-zk-file-title file) "\n")
  (insert-file-contents
   file
   nil
   (org-zk--beginning-of-main-content file))
  (org-zk-delete-file file))

(defun org-zk-slurp ()
  "Select a file, then insert it as a headline in the current
buffer."
  (interactive)
  (org-zk-select-file
   (lambda (selection) (org-zk--file-to-headline (cdr selection)))))

;;; Agenda Hacks

(defun org-zk--agenda-files ()
  (mapcar
   (lambda (entry) (plist-get entry :file))
   (org-el-cache-filter-files
    (lambda (entry)
      (let ((state (org-el-cache-entry-keyword entry "GTD_STATE")))
        (or (and (null state) (org-zk-ql-has-todos entry))
            (string= state "active")))))))

(defun org-zk--todo-files ()
  (mapcar
   (lambda (entry) (plist-get entry :file))
   (org-el-cache-filter-files
    (lambda (entry)
      (let ((state (org-el-cache-entry-keyword entry "GTD_STATE")))
        (and (null state) (org-zk-ql-has-todos entry)))))))

(defun org-zk-agenda ()
  (interactive)
  (setq org-agenda-files (org-zk--agenda-files))
  (org-agenda))

(defun org-zk-agenda-list ()
  (interactive)
  (setq org-agenda-files (org-zk--agenda-files))
  (org-agenda-list))

(defun org-zk-todo-list ()
  (interactive)
  (setq org-agenda-files (org-zk--agenda-files))
  (org-todo-list))

(defun org-zk-ql-has-todos (entry)
  (let ((headlines (plist-get entry :headlines)))
    (plusp
     (count-if
      (lambda (hl) (or (string= (plist-get hl :todo-keyword) "NEXT")
                  (string= (plist-get hl :todo-keyword) "TODO")))
      headlines))))

(defun org-zk-ql-next ()
  (interactive)
  (org-ql-search
    (org-zk--agenda-files)
    '(todo "NEXT")))

(defun org-zk-slurp ()
  "Select a file, then insert it as a headline in the current
buffer."
  (interactive)
  (org-zk-select-file
   (lambda (selection) (org-zk--file-to-headline (cdr selection)))))

(defun org-zk-delete-file (file)
  "Delete FILE, removing all links to it."
  (let ((file (expand-file-name file)))
    (dolist (entry (org-zk-files-linking-to file))
      (org-zk-in-file (plist-get entry :file)
        (org-zk-delete-link file)
        (save-buffer)
        (kill-buffer))))
  (delete-file file))

;;; Exports

(provide 'org-zettelkasten)
