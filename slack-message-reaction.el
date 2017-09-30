;;; slack-message-reaction.el --- adding, removing reaction from message  -*- lexical-binding: t; -*-

;; Copyright (C) 2015  yuya.minami

;; Author: yuya.minami <yuya.minami@yuyaminami-no-MacBook-Pro.local>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'slack-message)
(require 'slack-reaction)
(require 'slack-room)

(defconst slack-message-reaction-add-url "https://slack.com/api/reactions.add")
(defconst slack-message-reaction-remove-url "https://slack.com/api/reactions.remove")
(defvar slack-current-team-id)
(defvar slack-current-room-id)
(defcustom slack-invalid-emojis '("^:flag_" "tone[[:digit:]]:$" "-" "^[^:].*[^:]$" "\\Ca")
  "Invalid emoji regex. Slack server treated some emojis as Invalid."
  :group 'slack)

(defun slack-message-add-reaction ()
  (interactive)
  (let* ((ts (slack-get-ts))
         (reaction (slack-message-reaction-input))
         (team (slack-team-find slack-current-team-id))
         (room (slack-room-find slack-current-room-id
                                team)))
    (slack-message-reaction-add reaction ts room team)))

(defun slack-message-remove-reaction ()
  (interactive)
  (let* ((team (slack-team-find slack-current-team-id))
         (room (slack-room-find slack-current-room-id
                                team))
         (ts (slack-get-ts))
         (msg (slack-room-find-message room ts))
         (reactions (if (and
                         (slack-file-share-message-p msg)
                         (slack-get-file-comment-id))
                        (slack-message-reactions
                         (oref (oref msg file) initial-comment))
                      (slack-message-reactions msg)))
         (reaction (slack-message-reaction-select reactions)))
    (slack-message-reaction-remove reaction ts room team)))

(defun slack-message-show-reaction-users ()
  (interactive)
  (let* ((team (slack-team-find slack-current-team-id))
         (reaction (ignore-errors (get-text-property (point) 'reaction))))
    (if reaction
        (let ((user-names (slack-reaction-user-names reaction team)))
          (message "reacted users: %s" (mapconcat #'identity user-names ", ")))
      (message "Can't get reaction:"))))

(defun slack-message-reaction-select (reactions)
  (let ((list (mapcar #'(lambda (r)
                          (cons (oref r name)
                                (oref r name)))
                      reactions)))
    (slack-select-from-list
     (list "Select Reaction: ")
     selected)))

(defun slack-select-emoji ()
  (if (fboundp 'emojify-completing-read)
      (emojify-completing-read "Select Emoji: ")
    (read-from-minibuffer "Emoji: ")))

(defun slack-message-reaction-input ()
  (let ((reaction (slack-select-emoji)))
    (if (and (string-prefix-p ":" reaction)
             (string-suffix-p ":" reaction))
        (substring reaction 1 -1)
      reaction)))

(defmethod slack-message-get-param-for-reaction ((m slack-message))
  (cons "timestamp" (oref m ts)))

(defmethod slack-message-get-param-for-reaction ((m slack-file-comment-message))
  (cons "file_comment" (oref (oref m comment) id)))

(defun slack-message-reaction-add (reaction ts room team)
  (let ((message (or (slack-room-find-message room ts)
                     (slack-room-find-thread-message room ts))))
    (when message
      (cl-labels ((on-reaction-add
                   (&key data &allow-other-keys)
                   (slack-request-handle-error
                    (data "slack-message-reaction-add"))))
        (slack-request
         (slack-request-create
          slack-message-reaction-add-url
          team
          :type "POST"
          :params (list (cons "channel" (oref room id))
                        (slack-message-get-param-for-reaction message)
                        (cons "name" reaction))
          :success #'on-reaction-add))))))

(defun slack-message-reaction-remove (reaction ts room team)
  (let ((message (or (slack-room-find-message room ts)
                     (slack-room-find-thread-message room ts))))
    (when message
      (cl-labels ((on-reaction-remove
                   (&key data &allow-other-keys)
                   (slack-request-handle-error
                    (data "slack-message-reaction-remove"))))
        (slack-request
         (slack-request-create
          slack-message-reaction-remove-url
          team
          :type "POST"
          :params (list (cons "channel" (oref room id))
                        (slack-message-get-param-for-reaction message)
                        (cons "name" reaction))
          :success #'on-reaction-remove))))))

(defmethod slack-message-append-reaction ((m slack-file-share-message)
                                          reaction type)
  (if (string= type "file_comment")
      (if-let* ((old-reaction (slack-reaction-find (oref (oref m file) initial-comment)
                                                   reaction)))
          (slack-reaction-join old-reaction reaction)
        (slack-reaction-push (oref (oref m file) initial-comment) reaction))
    (if-let* ((old-reaction (slack-reaction-find m reaction)))
        (slack-reaction-join old-reaction reaction)
      (slack-reaction-push m reaction))))

(defmethod slack-message-append-reaction ((m slack-message) reaction _type)
  (if-let* ((old-reaction (slack-reaction-find m reaction)))
      (slack-reaction-join old-reaction reaction)
    (slack-reaction-push m reaction)))

(defmethod slack-message-pop-reaction ((m slack-file-share-message)
                                       reaction type)
  (if (string= type "file_comment")
      (if-let* ((old-reaction (slack-reaction-find (oref (oref m file) initial-comment)
                                                   reaction)))
          (slack-reaction-delete (oref (oref m file) initial-comment)
                                 reaction)
        (cl-decf (oref old-reaction count)))
    (if-let* ((old-reaction (slack-reaction-find m reaction)))
        (slack-reaction-delete m reaction)
      (cl-decf (oref old-reaction count)))))

(defmethod slack-message-pop-reaction ((m slack-message) reaction _type)
  (if-let* ((old-reaction (slack-reaction-find m reaction)))
      (slack-reaction-delete m reaction)
    (cl-decf (oref old-reaction count))))

(provide 'slack-message-reaction)
;;; slack-message-reaction.el ends here
