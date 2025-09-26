;;; erc-x-hide.el --- Transient menus for erc-hide -*- lexical-binding: t; -*-

;; Copyright (C) 2024,2025 Alcor

;; Author: Alcor <alcor@tilde.club>
;; URL: https://github.com/fmqa/erc-x-hide
;; Keywords: erc irc
;; Version: 0.4
;; Package-Requires: ((emacs "29.1") (erc "5.6") (transient "0.4.3"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Installation via `use-package':

;; (use-package erc-x-hide
;;   :after erc
;;   :vc (:url "https://github.com/fmqa/erc-x-hide.git" :branch "main")
;;   :bind (:map erc-mode-map ("C-c h" . erc-x-hide))
;;   :config
;;   (setopt erc-modules (seq-union erc-modules '(x-hide))))

;; If you are using Emacs ≤ 30.0, you will need to update the built-in package
;; `transient'. By default, `package.el' will not upgrade a built-in package.
;; Set the customizable variable `package-install-upgrade-built-in' to `t' to
;; override this.

(require 'transient)
(require 'erc)

(defvar erc-x-hide-list nil "Erc network-channel-message trie specifying message types to hide")

(defun erc-x-hide--current-network ()
  "Return the name of the current network."
  (or (and (erc-network) (erc-network-name))
      (erc-shorten-server-name
       (or erc-server-announced-name
           erc-session-server))))

(defun erc-x-hide-list-p (command &optional channel network)
  "Query ERC-X-HIDE-LIST"
  (setq network (or network (erc-x-hide--current-network)))
  (setq channel (or channel (buffer-name)))
  (when-let* ((network-node (assoc network erc-x-hide-list))
              (channel-node (assoc channel (cdr network-node))))
    (and (member command (cdr channel-node)) command)))

(defun erc-x-hide-list-message-p (parsed)
  "Query ERC-X-HIDE-LIST whether to hide a recieved message."
  (erc-x-hide-list-p (erc-response.command parsed)
                     (car (erc-response.command-args parsed))))

(defun erc-x-hide--JOIN (obj)
  (oset obj value (erc-x-hide-list-p "JOIN")))

(defun erc-x-hide--PART (obj)
  (oset obj value (erc-x-hide-list-p "PART")))

(defun erc-x-hide--KICK (obj)
  (oset obj value (erc-x-hide-list-p "KICK")))

(defun erc-x-hide--QUIT (obj)
  (oset obj value (when-let* ((network (erc-x-hide--current-network))
                              (node (assoc network erc-network-hide-list)))
                    (member "QUIT" (cdr node)))))
;; Main transient menu
;;;###autoload (autoload 'erc-x-hide "erc-x-hide" nil t)
(transient-define-prefix erc-x-hide ()
  "Transient to hide message types in the current channel"
  [:class transient-row "Channel"
          ("J" "JOIN" "JOIN" :init-value erc-x-hide--JOIN)
          ("K" "KICK" "KICK" :init-value erc-x-hide--KICK)
          ("P" "PART" "PART" :init-value erc-x-hide--PART)]
  [:class transient-row "Network"
          ("Q" "QUIT" "QUIT" :init-value erc-x-hide--QUIT)]
  [("RET" "Apply" erc-x-hide-apply)])

(defun erc-x-hide-apply (&optional args)
  "Hide the given message types in the current channel."
  (interactive (list (transient-args 'erc-x-hide)))
  (when-let* ((network (erc-x-hide--current-network)))
    ;; Use `erc-network-hide-list' for QUIT
    (let* ((selection (member "QUIT" args))
           (network-node (or (assoc network erc-network-hide-list)
                             (and args (let ((entry (list network)))
                                         (push entry erc-network-hide-list)
                                         entry))))
           (current (member "QUIT" (cdr network-node))))
      (cond
       ((and selection (not current))
        (push "QUIT" (cdr network-node)))
       ((and (not selection) current)
        (setf (cdr network-node) (delete "QUIT" (cdr network-node)))))
      (when selection
        (setq args (delete "QUIT" args)))
      (when (and network-node (not (cdr network-node)))
        (setq erc-network-hide-list (delete network-node erc-network-hide-list))))
    ;; Use the `erc-x-hide-list' for channel-specific messages
    (let* ((network-node (or (assoc network erc-x-hide-list)
                             (and args (let ((entry (list network)))
                                         (push entry erc-x-hide-list)
                                         entry))))
           (channel-node (or (assoc (buffer-name) (cdr network-node))
                             (and args (let ((entry (list (buffer-name))))
                                         (push entry (cdr network-node))
                                         entry)))))
      (when channel-node
        (setf (cdr channel-node) args))
      (when (and channel-node (not (cdr channel-node)))
        (setf (cdr network-node) (delete channel-node (cdr network-node))))
      (when (and network-node (not (cdr network-node)))
        (setq erc-x-hide-list (delete network-node erc-x-hide-list))))))

;;;###autoload (autoload 'erc-x-hide-mode "erc-x-hide" nil t)
(define-erc-module erc-x-hide nil
  "Transient-based erc-hide interface."
  ((advice-add 'erc-hide-current-message-p :after-until 'erc-x-hide-list-message-p))
  ((advice-remove 'erc-hide-current-message-p 'erc-x-hide-list-message-p)))

(provide 'erc-x-hide)
;;; erc-x-hide.el ends here
