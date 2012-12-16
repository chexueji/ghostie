(defpackage :ghostie-event
  (:use :cl)
  (:export #:trigger
           #:bind
           #:unbind
           #:disable-binding
           #:enable-binding))
(in-package :ghostie-event)

(defclass binding ()
  ((event-type :accessor binding-event :initarg :event-type :initform nil)
   (types :accessor binding-types :initarg :types :initform nil)
   (function :accessor binding-fn :initarg :fn :initform nil)
   (name :accessor binding-name :initarg :name :initform nil)
   (enabled :accessor binding-enabled :initarg :enabled :initform t))
  (:documentation "Describes a binding of a function to an event."))

;(defvar *events* (make-instance 'jpl-queues:unbounded-fifo-queue)
;  "Holds all events in the ghostie system.")
(defvar *events* nil)

(defvar *event-bindings* nil
  "Holds the functions bound to event/types/args.")

(defun make-event (event-type args)
  "Make an event, along with the arguments it fires."
  (list :type event-type :args args))

(defun dispatch-event (event)
  "Given an event object, call all matching function bound to that event and its
   corresponding types for each argument."
  ;; pull our info about the event and the arguments (and their types)
  (let* ((event-type (getf event :type))
         (args (getf event :args))
         (arg-types (loop for arg in args collect (type-of arg))))
    ;; loop over every binding, looking for matching functions
    (dolist (binding *event-bindings*)
      (let* ((bind-event (binding-event binding))
             (bind-types (binding-types binding))
             (bind-fn (binding-fn binding))
             (bind-enabled (binding-enabled binding))
             ;; check if the binding is, in fact, enabled (ie either enabled is
             ;; T OR the disabled-time has expired)
             (enabled (cond ((numberp bind-enabled)
                             (<= bind-enabled (get-internal-real-time)))
                            (t
                             bind-enabled))))
        ;; if the binding isn't disabled, make sure it's just set to T for fast
        ;; processing next loop
        (when enabled (setf (binding-enabled binding) t))

        (block skip-binding
          ;; make sure we have a matching event type (easiest test)
          (when (and enabled
                     (eq event-type bind-event)
                     (= (length args) (length bind-types)))
            ;; loop over the binding types and the argument types and make sure
            ;; the subtypep matches
            (loop for arg-type in arg-types
                  for bind-type in bind-types do
              (unless (or (null bind-type) (subtypep arg-type bind-type))
                ;; bad match, skip the binding
                (return-from skip-binding nil)))
            ;; loop matched all types, dispatch...
            (apply bind-fn args)))))))

(defun find-binding (event-type binding)
  "Given an event type"
  (let ((find-fn (if (functionp binding)
                     (lambda (bind) (eq binding (binding-fn bind)))
                     (lambda (bind) (equal binding (binding-name bind))))))
    (find-if (lambda (bind)
               (and (eq event-type (binding-event bind))
                    (funcall find-fn bind)))
             *event-bindings*)))

(defun process-events ()
  "Process all queued events."
  ;(loop
  ;  (when (jpl-queues:empty? *events*) (return))
  ;  (dispatch-event (jpl-queues:dequeue *events*)))
  (dolist (event (reverse *events*))
    (dispatch-event event))
  (setf *events* nil))

(defun trigger (event-type &rest args)
  "Trigger a ghostie event"
  (push (make-event event-type args) *events*)
  ;(jpl-queues:enqueue (make-event event-type args) *events*)
  (process-events))

(defun bind-event (event types/args fn &key binding-name)
  "Bind a function to an event and a set of types/arguments. The function will
   only be called if ther event, argument list, and types in the argument list
   match the provided bindings (somewhat like dispatching for defmethod)."
  ;; if a binding already exists with this name, remove it
  (when binding-name
    (setf *event-bindings*
          (remove-if (lambda (binding)
                       (and (eq event (binding-event binding))
                            (or (equal binding-name (binding-name binding))
                                (equal fn (binding-fn binding)))))
                     *event-bindings*)))

  ;; add the binding to the dispatch table
  (push (make-instance 'binding
                       :event-type event
                       :types (loop for arg in types/args
                                    if (listp arg)
                                       collect (cadr arg)
                                    else
                                       collect nil)
                       :fn fn
                       :name binding-name)
        *event-bindings*))

(defmacro bind (event-type-and-name (&rest types/args) &body body)
  "Wraps bind-event to make the syntax a bit nicer (and more like defmethod)."
  (let ((event-type (if (listp event-type-and-name)
                        (car event-type-and-name)
                        event-type-and-name))
        (binding-name (when (and (listp event-type-and-name)
                                 (cadr event-type-and-name))
                        (cadr event-type-and-name)))
        (fn-name (gensym "fn")))
    `(let ((,fn-name (lambda ,(loop for arg in types/args
                                    if (listp arg)
                                       collect (car arg)
                                    else
                                       collect arg)
                       ,@body)))
       (bind-event ,event-type ',types/args
                   ,fn-name
                   :binding-name ,binding-name)
       ,fn-name)))

(defun do-unbind (event-type remove-fn)
  (setf *event-bindings* (remove-if
                           (lambda (binding)
                             (and (or (null event-type)
                                      (eq event-type (binding-event binding)))
                                  (funcall remove-fn binding)))
                           *event-bindings*)))

(defgeneric unbind (event-type binding)
  (:documentation "Unbind a specific function from an event."))

(defmethod unbind ((event-type symbol) (fn function))
  (do-unbind event-type (lambda (binding) (equal fn (binding-fn binding)))))

(defmethod unbind ((event-type symbol) (name symbol))
  (do-unbind event-type (lambda (binding) (eq name (binding-name binding)))))

(defmethod unbind ((event-type symbol) (name string))
  (do-unbind event-type (lambda (binding) (string= name (binding-name binding)))))

(defun unbind-all (&optional event-type)
  "Remove all bindings from an event. If event is nil, unbinds all events, ever."
  (if event-type
      (do-unbind nil (lambda (binding) (eq event-type (binding-event binding))))
      (setf *event-bindings* nil)))


(defun disable-binding (event-type binding &key time)
  "Disable an event indefinitely (must be re-enabled manually) or by a number of
   seconds (specified by :time)."
  (let ((binding (find-binding event-type binding)))
    (when binding
      (let ((period (if time
                        (+ (get-internal-real-time)
                           (floor (* time internal-time-units-per-second)))
                        nil)))
        (setf (binding-enabled binding) period))
      binding)))

(defun enable-binding (event-type binding)
  "Enables a previously disabled binding."
  (let ((binding (find-binding event-type binding)))
    (when binding
      (setf (binding-enabled binding) t))))

