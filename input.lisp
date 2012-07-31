(in-package :ghostie)

(defun mouse-pos ()
  (glfw:get-mouse-pos))

(defun mouse-btn (btn-num)
  (eq (glfw:get-mouse-button btn-num) glfw:+press+))

(defun key-pressed (key state)
  ;; state == glfw:+release+ || glfw:+press+
  (declare (ignore key state)))

(def-c-callback key-pressed-cb :void ((key :int) (state :int))
  (key-pressed key state))

(defmacro key= (key)
  (let ((key (if (characterp key)
                 (char-int key)
                 key)))
    `(eql (glfw:get-key ,key) glfw:+press+)))

(defun key-handler (dt)
  (when (key= #\-)
    (decf (nth 2 (world-position *world*)) (* (coerce dt 'single-float) 10)))
  (when (key= #\=)
    (incf (nth 2 (world-position *world*)) (* (coerce dt 'single-float) 10)))
  (when (key= glfw:+key-up+)
    (decf (nth 1 (world-position *world*)) (* (coerce dt 'single-float) 10)))
  (when (key= glfw:+key-down+)
    (incf (nth 1 (world-position *world*)) (* (coerce dt 'single-float) 10)))
  (when (key= glfw:+key-left+)
    (move-actor (level-main-actor (world-level *world*)) -6))
  (when (key= glfw:+key-right+)
    (move-actor (level-main-actor (world-level *world*)) 6))
  (when (key= #\R)
    (setf (world-position *world*) '(0 0 -5))
    (sleep .1))
  (when (key= #\C)
    (recompile-shaders))
  (when (key= #\T)
    (test-gl-funcs))
  (when (key= #\L)
    (load-assets *world*))
  (when (or (key= glfw:+key-esc+) (key= #\Q))
    (setf *quit* t)))


