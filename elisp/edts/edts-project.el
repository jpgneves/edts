;; Copyright 2012 Thomas Järvstrand <tjarvstrand@gmail.com>
;;
;; This file is part of EDTS.
;;
;; EDTS is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; EDTS is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Lesser General Public License for more details.
;;
;; You should have received a copy of the GNU Lesser General Public License
;; along with EDTS. If not, see <http://www.gnu.org/licenses/>.
;;
;; Rudimentary project support for edts so that we can relate buffers to
;; projects and communicate with the correct nodes.

(defcustom edts-project-auto-start-node t
  "If non-nil, automagically start an erlang node whenever erlang-mode is
activated for the first file that is located inside a project."
  :type 'boolean
  :group 'edts)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun edts-project-init ()
  "Buffer specific (not necessarily buffer-local) setup."
  (let* ((buffer  (current-buffer))
         (project (edts-project-buffer-project buffer)))
    (when (and project edts-project-auto-start-node)
      (edts-project-ensure-buffer-node-started buffer))))

(defun edts-project-ensure-buffer-node-started (buffer)
  "Start BUFFER's project's node if it is not already started."
  (edts-project-ensure-node-started (edts-project-buffer-project buffer)))

(defun edts-project-ensure-node-started (project)
  "Start BUFFER's project's node if it is not already started."
  (let ((node-name (edts-project-node-name project)))
    (if (edts-node-started-p node-name)
        (edts-register-node-when-ready node-name)
        (edts-project-start-node project))))

(defun edts-project-start-node (project)
  "Starts a new erlang node for PROJECT."
  (let* ((project-name (edts-project-name project))
         (node-name    (edts-project-node-name project))
         (buffer-name  (concat "*" project-name "*"))
         (command      (edts-project-build-project-command project))
         (pwd          (expand-file-name (edts-project-root project))))
    (edts-ensure-node-not-started node-name)
    (edts-project-make-comint-buffer buffer-name pwd command)
    (edts-register-node-when-ready node-name)
    (get-buffer buffer-name)))

(defun edts-project-build-project-command (project)
  "Build a command line for PROJECT"
  (let ((command (edts-project-start-command project)))
    (if command
          (delete "" (split-string command)) ; delete "" for xemacs.
        (let ((path (edts-project-code-path-expand project))
              (sname (edts-project-node-name project)))
          (append
           (list (executable-find "erl") "-sname" sname "-pa")
           path)))))

(defun edts-project-make-comint-buffer (buffer-name pwd command)
  "In a comint-mode buffer Starts a node with BUFFER-NAME by cd'ing to
PWD and running COMMAND."
  (let* ((cmd  (car command))
         (args (cdr command)))
    (with-current-buffer (get-buffer-create buffer-name) (cd pwd))
    (apply #'make-comint-in-buffer cmd buffer-name cmd nil args)))

(defun edts-project-buffer-node-started-p (buffer)
  "Returns non-nil if there is an edts-project erlang node started that
corresponds to BUFFER."
  (edts-node-started-p (edts-project-buffer-node-name buffer)))

(defun edts-project-name (project)
  "Returns the name of the edts-project PROJECT. No default value,
come on you have to do *something* yourself!"
  (edts-project-property 'name project))

(defun edts-project-root (project)
  "Returns the root directory of the edts-project PROJECT."
  (edts-project-property 'root project))

(defun edts-project-lib-dirs (project)
  "Returns the edts-project PROJECT's library directories. Defaults to
(\"lib\")"
  (or (edts-project-property 'lib-dirs project) '("lib")))

(defun edts-project-node-name (project)
  "Returns the edts-project PROJECT's erlang node-name. Currently only
short names are supported."
  (or (edts-project-property 'node-sname project) (edts-project-name project)))

(defun edts-project-start-command (project)
  "Returns the edts-project PROJECT's command for starting it's project
 node."
  (edts-project-property 'start-command project))

(defun edts-project-property (prop project)
  "Returns the value of the property of name PROP from PROJECT."
  (cdr (assoc prop project)))

(defun edts-project-code-path-expand (project)
  "Expands PROJECT's ebin and listed lib dirs to a full set of ebin and
test directories, treating every subdirectory of each lib dir a an OTP
application."
  (let ((root     (edts-project-root project))
        (lib-dirs (edts-project-lib-dirs project)))
     (apply #'append
            (list (edts-project-normalize-path (format "%s/ebin"  root))
                  (edts-project-normalize-path (format "%s/test"  root)))
            (mapcar #'(lambda (dir)
                        (edts-project-path-expand root dir)) lib-dirs))))

(defun edts-project-path-expand (root dir)
  "Returns a list of all existing directories in any folder directly
beneath ROOT/DIR expanded with <path>/ebin and <path>/test."
  (let* ((lib-path  (edts-project-normalize-path (format "%s/%s" root dir)))
         (app-dirs  (file-expand-wildcards (concat lib-path "*")))
         (app-paths (mapcar #'(lambda (path)
                                (list (concat path "/ebin")
                                      (concat path "/test")))
                            app-dirs)))
    (apply #'append app-paths)))

(defun edts-project-buffer-node-name (buffer)
  "Returns the erlang node-name of BUFFER's edts-project node."
  (edts-project-node-name (edts-project-buffer-project buffer)))

(defun edts-project-buffer-project (buffer)
  "Returns the edts-project that BUFFER is part of, if any,
otherwise nil."
  (edts-project-file-project (buffer-file-name buffer)))

(defun edts-project-file-project (file-name)
  "Returns the edts-project that the file with FILE-NAME is part of,
if any, otherwise nil."
  (find-if  #'(lambda (p) (edts-project-file-in-project-p p file-name))
            edts-projects))

(defun edts-project-file-in-project-p (project file-name)
  "Returns non-nil if the fully qualified FILE-NAME is located
inside the edts-project PROJECT."
  (edts-project-file-under-path-p (edts-project-root project) file-name))

(defun edts-project-file-under-path-p (path file-name)
  "Returns non-nil if the fully qualified file-name is located
underneath PATH."
  (string-prefix-p (edts-project-normalize-path path)
                   (expand-file-name file-name)))

(defun edts-project-normalize-path (path-str)
  "Badly named function. Only replaces duplicate /'s in PATH-STR and
make sure it ends with a '/'."
  (replace-regexp-in-string "//+" "/"
                            (concat (expand-file-name path-str) "/")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Unit tests

(when (member 'ert features)

  (defvar edts-project-test-project-1
    '((name          . "dev")
      (root          . "./foo")
      (node-sname    . "dev-node")
      (lib-dirs . ("lib" "test"))))

  ;; Incorrectly defined project
  (defvar edts-project-test-project-2
    '((start-command . "bin/start.sh -i")))

  (defvar edts-project-test-project-3
    '((name          . "dev")
      (root          . "./bar")
      (node-sname    . "dev-node")
      (lib-dirs . ("lib" "test"))))


  (ert-deftest edts-project-start-node-test ()
    (flet ((edts-node-started-p (node-name) t))
      (should-error (edt-project-start-node edts-project-test-project-1))))

  (ert-deftest edts-project-build-project-command-test ()
    (flet ((edts-project-code-path-expand (project)
                                          '("./foo/test" "./foo/ebin"))
           (executable-find (cmd) cmd))
      (should
       (equal
        '("erl" "-sname" "dev-node" "-pa" "./foo/test" "./foo/ebin")
        (edts-project-build-project-command edts-project-test-project-1))))
    (should
     (equal '("bin/start.sh" "-i")
            (edts-project-build-project-command edts-project-test-project-2))))

  (ert-deftest edts-project-make-comint-buffer-test ()
    (let ((buffer (edts-project-make-comint-buffer "edts-test" "." '("erl"))))
      (should (bufferp buffer))
      (should (string= "edts-test" (buffer-name buffer)))
      (should (string= "erl" (process-name (get-buffer-process buffer))))
      (set-process-query-on-exit-flag (get-buffer-process buffer) nil)
      (kill-process (get-buffer-process buffer))
      (kill-buffer buffer)))

  (ert-deftest edts-project-buffer-node-started-p-test ()
    (flet ((edts-node-started-p (node)
                                (if (string= node "dev-node")
                                    t
                                  (error "wrong node-name")))
           (edts-project-buffer-project (buffer) edts-project-test-project-1))
      (should (edts-project-buffer-node-started-p (current-buffer))))
    (flet ((edts-node-started-p (node)
                                (if (string= node "dev-node")
                                    nil
                                  (error "wrong node-name")))
           (edts-project-buffer-project (buffer) edts-project-test-project-1))
      (should-not (edts-project-buffer-node-started-p (current-buffer)))))

  (ert-deftest edts-project-project-name-test ()
    (should (string= "dev"
                     (edts-project-name edts-project-test-project-1)))
    (should (equal nil
                   (edts-project-name edts-project-test-project-2))))

  (ert-deftest edts-project-project-root-test ()
    (should (string= "./foo"
                     (edts-project-root edts-project-test-project-1)))
    (should (equal nil
                   (edts-project-root edts-project-test-project-2))))

  (ert-deftest edts-project-lib-dirs-test ()
    (should (equal '("lib" "test")
                   (edts-project-lib-dirs edts-project-test-project-1)))
    (should (equal '("lib")
                   (edts-project-lib-dirs edts-project-test-project-2))))

  (ert-deftest edts-project-node-name-test ()
    (should (string= "dev-node"
                     (edts-project-node-name edts-project-test-project-1)))
    (should (eq nil
                (edts-project-node-name edts-project-test-project-2))))

  (ert-deftest edts-project-start-command-test ()
    (should (eq nil (edts-project-start-command edts-project-test-project-1)))
    (should (string= "bin/start.sh -i"
                     (edts-project-start-command edts-project-test-project-2))))

  (ert-deftest edts-project-path-expand-test ()
    (let ((home (expand-file-name "~")))
      (flet ((file-expand-wildcards (path)
                                    (when (string= (concat home "/foo/lib/*")
                                                   path)
                                      (list (concat home "/foo/lib/bar")))))
        (should (equal (list
                        (concat home "/foo/lib/bar/ebin")
                        (concat home "/foo/lib/bar/test"))
                       (edts-project-path-expand "~/foo" "lib"))))))

  (ert-deftest edts-project-buffer-node-name-test ()
    (let ((edts-projects (list edts-project-test-project-1)))
      (flet ((buffer-file-name (buffer) "./foo/bar.el"))
        (should
         (string= "dev-node"
                  (edts-project-buffer-node-name (current-buffer)))))
      (flet ((buffer-file-name (buffer) "./bar/baz.el"))
        (should
         (eq nil
             (edts-project-buffer-node-name (current-buffer)))))))

  (ert-deftest edts-project-buffer-project-test ()
    (let ((edts-projects (list edts-project-test-project-1)))
      (flet ((buffer-file-name (buffer) "./foo/bar.el"))
        (should
         (eq edts-project-test-project-1
             (edts-project-buffer-project (current-buffer)))))
      (flet ((buffer-file-name (buffer) "./bar/baz.el"))
        (should
         (eq nil
             (edts-project-buffer-project (current-buffer)))))))

  (ert-deftest edts-project-file-project-test ()
    (let ((edts-projects (list edts-project-test-project-1)))
      (should
       (eq edts-project-test-project-1
           (edts-project-file-project "./foo/bar.el"))))
    (let ((edts-projects (list edts-project-test-project-3)))
      (should-not (edts-project-file-project "./foo/baz.el"))))

  (ert-deftest edts-project-file-in-project-p ()
    (should
     (not (null (edts-project-file-in-project-p
                 edts-project-test-project-1
                 "./foo/bar.el"))))
    (should
     (not (null (edts-project-file-in-project-p
                 edts-project-test-project-1
                 "./foo/bar/baz.el"))))
    (should
     (null (edts-project-file-in-project-p
            edts-project-test-project-1
            "/bar/foo/baz.el"))))

  (ert-deftest edts-project-file-under-path-p ()
    (should
     (not (null (edts-project-file-under-path-p "/foo" "/foo/bar/baz.el"))))
    (should
     (not (edts-project-file-under-path-p "/bar" "/foo/bar/baz.el"))))

  (ert-deftest edts-project-normalize-path-test ()
    (flet ((expand-file-name (file-name) (concat "./" file-name)))
      (should (string= "./foo/bar/" (edts-project-normalize-path "foo//bar")))
      (should (string= "./foo/bar/" (edts-project-normalize-path "foo/bar/"))))))


(provide 'edts-project)
