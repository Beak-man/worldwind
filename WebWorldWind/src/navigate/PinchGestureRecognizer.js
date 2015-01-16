/*
 * Copyright (C) 2014 United States Government as represented by the Administrator of the
 * National Aeronautics and Space Administration. All Rights Reserved.
 */
/**
 * @exports PinchGestureRecognizer
 * @version $Id$
 */
define([
        '../navigate/GestureRecognizer'
    ],
    function (GestureRecognizer) {
        "use strict";

        /**
         * Constructs a pinch gesture recognizer.
         * @alias PinchGestureRecognizer
         * @constructor
         * @classdesc A concrete gesture recognizer subclass that looks for two finger pinch gestures.
         */
        var PinchGestureRecognizer = function (target) {
            GestureRecognizer.call(this, target);

            /**
             * 
             * @type {number}
             */
            this.scale = 1;

            /**
             *
             * @type {number}
             * @protected
             */
            this.scaleOffset = 1;

            /**
             *
             * @type {number}
             * @protected
             */
            this.threshold = 5;

            /**
             *
             * @type {number}
             * @protected
             */
            this.distance = 0;

            /**
             *
             * @type {number}
             * @protected
             */
            this.beginDistance = 0;

            /**
             *
             * @type {Array}
             * @protected
             */
            this.touchIdentifiers = [];
        };

        PinchGestureRecognizer.prototype = Object.create(GestureRecognizer.prototype);

        /**
         * 
         */
        PinchGestureRecognizer.prototype.reset = function () {
            GestureRecognizer.prototype.reset.call(this);

            this.scale = 1;
            this.scaleOffset = 1;
            this.distance = 0;
            this.beginDistance = 0;
            this.touchIdentifiers = [];
        };

        /**
         *
         * @param event
         * @returns {boolean}
         */
        PinchGestureRecognizer.prototype.shouldBeginWithTouchEvent = function (event) {
            return Math.abs(this.distance - this.beginDistance) > this.threshold
        };

        /**
         *
         * @returns {number}
         */
        PinchGestureRecognizer.prototype.touchDistance = function () {
            var touchA, touchB,
                dx, dy;

            if (this.touchIdentifiers.length < 2) {
                return 0;
            } else {
                touchA = this.touchWithIdentifier(this.touchIdentifiers[0]);
                touchB = this.touchWithIdentifier(this.touchIdentifiers[1]);
                dx = touchA.screenX - touchB.screenX;
                dy = touchA.screenY - touchB.screenY;

                return Math.sqrt(dx * dx + dy * dy);
            }
        };

        /**
         *
         * @param event
         */
        PinchGestureRecognizer.prototype.touchStart = function (event) {
            var touchesDown = event.changedTouches;

            if (this.touchIdentifiers.length < 2) {
                for (var i = 0; i < touchesDown.length && this.touchIdentifiers.length < 2; i++) {
                    this.touchIdentifiers.push(touchesDown.item(i).identifier);
                }

                if (this.touchIdentifiers.length == 2) {
                    this.beginDistance = this.touchDistance();
                    this.scaleOffset = this.scale;
                }
            }
        };

        /**
         *
         * @param event
         */
        PinchGestureRecognizer.prototype.touchMove = function (event) {
            if (this.touchIdentifiers.length == 2) {
                this.distance = this.touchDistance();
                this.scale = this.scaleOffset * (this.distance / this.beginDistance);
            }

            if (this.state == GestureRecognizer.POSSIBLE) {
                if (this.touchIdentifiers.length == 2) {
                    if (this.shouldBeginWithTouchEvent(event)) {
                        this.transitionToState(GestureRecognizer.BEGAN, event);
                    }
                }
            } else if (this.state == GestureRecognizer.BEGAN || this.state == GestureRecognizer.CHANGED) {
                this.transitionToState(GestureRecognizer.CHANGED, event);
            }
        };

        // TODO: Capture the common pattern in touchEnd and touchCancel

        /**
         *
         * @param event
         */
        PinchGestureRecognizer.prototype.touchEnd = function (event) {
            var touchesUp = event.changedTouches;

            for (var i = 0, count = touchesUp.length; i < count; i++) {
                this.removeTouch(touchesUp.item(i).identifier);
            }

            if (event.targetTouches.length == 0) {
                if (this.state == GestureRecognizer.BEGAN || this.state == GestureRecognizer.CHANGED) {
                    this.transitionToState(GestureRecognizer.ENDED, event);
                    this.reset();
                } else if (this.state == GestureRecognizer.FAILED) {
                    this.reset();
                }
            }
        };

        /**
         *
         * @param event
         */
        PinchGestureRecognizer.prototype.touchCancel = function (event) {
            var touchesUp = event.changedTouches;

            for (var i = 0, count = touchesUp.length; i < count; i++) {
                this.removeTouch(touchesUp.item(i).identifier);
            }

            if (event.targetTouches.length == 0) {
                if (this.state == GestureRecognizer.BEGAN || this.state == GestureRecognizer.CHANGED) {
                    this.transitionToState(GestureRecognizer.CANCELLED, event);
                    this.reset();
                } else if (this.state == GestureRecognizer.FAILED) {
                    this.reset();
                }
            }
        };


        PinchGestureRecognizer.prototype.removeTouch = function (identifier) {
            for (var i = 0, count = this.touchIdentifiers.length; i < count; i++) {
                if (this.touchIdentifiers[i] == identifier) {
                    this.touchIdentifiers.splice(i, 1);
                    break;
                }
            }
        };

        return PinchGestureRecognizer;
    });