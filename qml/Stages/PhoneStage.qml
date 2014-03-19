/*
 * Copyright (C) 2014 Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import Ubuntu.Components 0.1
import Ubuntu.Gestures 0.1
import Unity.Application 0.1
import Utils 0.1
import "../Components"

Item {
    id: root

    // Controls to be set from outside
    property bool shown: false
    property bool moving: false
    property int dragAreaWidth

    // State information propagated to the outside
    readonly property bool painting: mainScreenshotImage.visible || fadeInScreenshotImage.visible || appSplash.visible || spreadView.visible
    property bool fullscreen: priv.focusedApplication ? priv.focusedApplication.fullscreen : false
    property bool locked: spreadView.visible

    // Not used for PhoneStage, only useful for SideStage and similar
    property bool overlayMode: false
    property int overlayWidth: 0

    onMovingChanged: {
        if (moving) {
            if (ApplicationManager.focusedApplicationId) {
                priv.requestNewScreenshot();
            } else {
                mainScreenshotImage.anchors.leftMargin = 0;
                mainScreenshotImage.src = ApplicationManager.get(0).screenshot;
                mainScreenshotImage.visible = true;
            }
        } else {
            mainScreenshotImage.visible = false;
        }
    }

    Connections {
        target: ApplicationManager

        onFocusRequested: {
            if (spreadView.visible) {
                spreadView.snapTo(priv.indexOf(appId));
            } else {
                priv.switchToApp(appId);
            }
        }

        onFocusedApplicationIdChanged: {
            if (ApplicationManager.focusedApplicationId.length > 0) {
                if (priv.secondApplicationStarting || priv.applicationStarting) {
                    appSplashTimer.start();
                } else {
                    var application = priv.focusedApplication;
                    root.fullscreen = application.fullscreen;
                    mainScreenshotImage.src = application.screenshot;
                }
            } else {
                spreadView.selectedIndex = -1;
                spreadView.stage = 0;
                spreadView.contentX = -spreadView.shift;
            }
        }

        onApplicationAdded: {
            if (!priv.focusedApplication) {
                mainScreenshotImage.src = "";
                mainScreenshotImage.visible = false;
                priv.applicationStarting = true;
            } else {
                mainScreenshotImage.src = "";
                priv.newFocusedAppId = appId;
                priv.secondApplicationStarting = true;
                priv.requestNewScreenshot();
            }

            if (spreadView.visible) {
                spreadView.snapTo(0);
            }
        }

        onApplicationRemoved: {
            if (ApplicationManager.count == 0) {
                mainScreenshotImage.src = ""
                mainScreenshotImage.visible = false;
            } else {
                mainScreenshotImage.src = ApplicationManager.get(0).screenshot;
            }
        }
    }

    QtObject {
        id: priv

        property string focusedAppId: ApplicationManager.focusedApplicationId
        property var focusedApplication: ApplicationManager.findApplication(focusedAppId)
        property url focusedScreenshot: focusedApplication ? focusedApplication.screenshot : ""

        property bool waitingForScreenshot: false

        property bool applicationStarting: false
        property bool secondApplicationStarting: false

        property string newFocusedAppId

        onFocusedScreenshotChanged: {
            if (root.moving && priv.waitingForScreenshot) {
                mainScreenshotImage.anchors.leftMargin = 0;
                mainScreenshotImage.src = priv.focusedScreenshot
                mainScreenshotImage.visible = true;
            } else if (priv.secondApplicationStarting && priv.waitingForScreenshot) {
                applicationSwitchingAnimation.start();
            }
            waitingForScreenshot = false;
        }

        function requestNewScreenshot() {
            waitingForScreenshot = true;
            ApplicationManager.updateScreenshot(focusedAppId);
        }

        function switchToApp(appId) {
            priv.newFocusedAppId = appId;
            root.fullscreen = ApplicationManager.findApplication(appId).fullscreen;
            applicationSwitchingAnimation.start();
        }

        function indexOf(appId) {
            for (var i = 0; i < ApplicationManager.count; i++) {
                if (ApplicationManager.get(i).appId == appId) {
                    return i;
                }
            }
            return -1;
        }

    }

    // FIXME: the signal connections seems to get lost.
    Connections {
        target: priv.focusedApplication
        onScreenshotChanged: priv.focusedScreenshot = priv.focusedApplication.screenshot
    }
    Binding {
        target: root
        property: "fullscreen"
        value: priv.focusedApplication ? priv.focusedApplication.fullscreen : false
    }

    Timer {
        id: appSplashTimer
        // This is to show the splash screen a bit longer.
        // Mir signals us that the newly started app has gotten focus before it paints something on the screen
        // This would result in the old app surface becoming visible for a bit.
        // FIXME: change appManager to only change the focusedApplicationId when the surface is ready to be shown.
        interval: 1500
        repeat: false
        onTriggered: {
            priv.applicationStarting = false;
            priv.secondApplicationStarting = false;
        }
    }

    SequentialAnimation {
        id: applicationSwitchingAnimation
        // setup
        PropertyAction { target: mainScreenshotImage; property: "anchors.leftMargin"; value: 0 }
        // FIXME: PropertyAction seems to fail when secondApplicationStarting and we didn't have another screenshot before
        ScriptAction { script: mainScreenshotImage.src = priv.focusedScreenshot }
        PropertyAction { targets: [mainScreenshotImage, fadeInScreenshotImage]; property: "visible"; value: true }
        PropertyAction { target: fadeInScreenshotImage; property: "source"; value: {
                var newFocusedApp = ApplicationManager.findApplication(priv.newFocusedAppId);
                return newFocusedApp ? newFocusedApp.screenshot : "" }
        }
        PropertyAction { target: fadeInScreenshotImage; property: "opacity"; value: 0 }
        PropertyAction { target: fadeInScreenshotImage; property: "scale"; value: .8 }


        // The actual animation
        ParallelAnimation {
            UbuntuNumberAnimation { target: mainScreenshotImage; property: "anchors.leftMargin"; to: root.width; duration: UbuntuAnimation.SlowDuration }
            UbuntuNumberAnimation { target: fadeInScreenshotImage; properties: "opacity,scale"; to: 1; duration: UbuntuAnimation.SlowDuration }
        }

        // restore stuff
        ScriptAction { script: ApplicationManager.focusApplication(priv.newFocusedAppId); }
        PropertyAction { target: fadeInScreenshotImage; property: "visible"; value: false }
        PropertyAction { target: mainScreenshotImage; property: "visible"; value: false }
    }

    // FIXME: Drop this and make the imageprovider show a splashscreen instead
    Rectangle {
        id: appSplash2
        anchors.fill: parent
        color: "white"
        visible: priv.secondApplicationStarting
    }
    Image {
        id: fadeInScreenshotImage
        anchors { left: parent.left; bottom: parent.bottom }
        width: parent.width
        scale: .7
        visible: false
    }

    Rectangle {
        id: appSplash
        anchors.fill: parent
        color: "white"
        visible: priv.applicationStarting
    }
    Image {
        id: mainScreenshotImage
        anchors { left: parent.left; bottom: parent.bottom }
        width: parent.width

        // FIXME: Workaround for bug: https://bugs.launchpad.net/ubuntu-ui-toolkit/+bug/1194778
        property string src
        source: src
        visible: false
    }

    EdgeDragArea {
        id: spreadDragArea
        direction: Direction.Leftwards
        enabled: ApplicationManager.count > 1 && spreadView.stage != 2

        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: root.dragAreaWidth

        property bool attachedToView: true

        property var gesturePoints: new Array()

        onTouchXChanged: {
            if (!dragging && !priv.waitingForScreenshot) {
                priv.requestNewScreenshot();
                spreadView.stage = 0;
                spreadView.contentX = -spreadView.shift;
            }
            if (dragging && attachedToView) {
                spreadView.contentX = -touchX - spreadView.shift;
            }
            if (attachedToView && spreadView.shiftedContentX >= spreadView.width * spreadView.positionMarker3) {
                attachedToView = false;
                spreadView.snap();
            }
            gesturePoints.push(touchX);
        }

        onStatusChanged: {
            if (status == DirectionalDragArea.Recognized) {
                attachedToView = true;
            }
        }

        onDraggingChanged: {
            var oneWayFlick = true;
            var smallestX = spreadDragArea.width;
            for (var i = 0; i < gesturePoints.length; i++) {
                if (gesturePoints[i] >= smallestX) {
                    oneWayFlick = false;
                    break;
                }
                smallestX = gesturePoints[i];
            }
            gesturePoints = [];

            if (oneWayFlick && spreadView.shiftedContentX > units.gu(2) && spreadView.shiftedContentX < spreadView.positionMarker1 * spreadView.width) {
                spreadView.snapTo(1);
            } else if (!dragging && attachedToView) {
                spreadView.snap();
            }
        }
    }

    Rectangle {
        id: coverFlipBackground
        anchors.fill: parent
        color: "black"
        visible: spreadView.visible
    }

    InputFilterArea {
        anchors.fill: root
        blockInput: spreadView.visible
    }

    Flickable {
        id: spreadView
        objectName: "spreadView"
        anchors.fill: parent
        visible: spreadDragArea.status == DirectionalDragArea.Recognized || stage > 1 || snapAnimation.running
        contentWidth: spreadRow.width - shift
        contentX: -shift

        // The flickable needs to fill the screen in order to get touch events all over.
        // However, we don't want to the user to be able to scroll back all the way. For
        // that, the beginning of the gesture starts with a negative value for contentX
        // so the flickable wants to pull it into the view already. "shift" tunes the
        // distance where to "lock" the content.
        property real shift: width / 2
        property real shiftedContentX: contentX + shift

        property int tileDistance: width / 4

        property real positionMarker1: 0.3
        property real positionMarker2: 0.45
        property real positionMarker3: 0.6
        property real positionMarker4: .9

        // This is where the first app snaps to when bringing it in from the right edge.
        property real snapPosition: 0.75

        // Stage of the animation:
        // 0: Starting from right edge, a new app (index 1) comes in from the right
        // 1: The app has reached the first snap position.
        // 2: The list is dragged further and snaps into the spread view when entering stage 2
        property int stage: 0

        property int selectedIndex: -1

        onShiftedContentXChanged: {
            switch (stage) {
            case 0:
                if (shiftedContentX > width * positionMarker2) {
                    stage = 1;
                }
                break;
            case 1:
                if (shiftedContentX < width * positionMarker2) {
                    stage = 0;
                } else if (shiftedContentX >= width * positionMarker4) {
                    stage = 2;
                }
            }
        }

        function snap() {
            if (shiftedContentX < positionMarker1 * width) {
                snapAnimation.targetContentX = -shift;
                snapAnimation.start();
            } else if (shiftedContentX < positionMarker2 * width) {
                snapTo(1)
            } else if (shiftedContentX < positionMarker3 * width) {
                snapTo(1)
            } else if (stage < 2){
                // Add 1 pixel to make sure we definitely hit positionMarker4 even with rounding errors of the animation.
                snapAnimation.targetContentX = width * positionMarker4 + 1 - shift;
                snapAnimation.start();
            }
        }
        function snapTo(index) {
            spreadView.selectedIndex = index;
            root.fullscreen = ApplicationManager.get(index).fullscreen;
            snapAnimation.targetContentX = -shift;
            snapAnimation.start();
        }

        SequentialAnimation {
            id: snapAnimation
            property int targetContentX: -spreadView.shift

            UbuntuNumberAnimation {
                target: spreadView
                property: "contentX"
                to: snapAnimation.targetContentX
                duration: UbuntuAnimation.FastDuration
            }

            ScriptAction {
                script: {
                    if (spreadView.selectedIndex >= 0) {
                        ApplicationManager.focusApplication(ApplicationManager.get(spreadView.selectedIndex).appId);
                        spreadView.selectedIndex = -1
                        spreadView.stage = 0;
                        spreadView.contentX = -spreadView.shift;
                    }
                    if (spreadView.shiftedContentX == spreadView.width * spreadView.positionMarker2) {
                        spreadView.stage = 4;
                        spreadView.stage = 0;
                        spreadView.contentX = -spreadView.shift;
                    }
                }
            }
        }

        Item {
            id: spreadRow
            width: Math.max(3, ApplicationManager.count) * spreadView.tileDistance + (spreadView.width - spreadView.tileDistance) * 1.5

            x: spreadView.contentX

            Repeater {
                id: spreadRepeater
                model: ApplicationManager
                delegate: TransformedSpreadDelegate {
                    id: appDelegate
                    objectName: "appDelegate" + index
                    startAngle: 45
                    endAngle: 5
                    startScale: 1.1
                    endScale: 0.7
                    startDistance: spreadView.tileDistance
                    endDistance: units.gu(.5)
                    width: spreadView.width
                    height: spreadView.height
                    selected: spreadView.selectedIndex == index
                    otherSelected: spreadView.selectedIndex >= 0 && !selected

                    z: index
                    x: index == 0 ? 0 : spreadView.width + (index - 1) * spreadView.tileDistance

                    // Each tile has a different progress value running from 0 to 1.
                    // A progress value of 0 means the tile is at the right edge. 1 means the tile has reched the left edge.
                    progress: {
                        var tileProgress = (spreadView.shiftedContentX - index * spreadView.tileDistance) / spreadView.width;
                        // Tile 1 needs to move directly from the beginning...
                        if (index == 1 && spreadView.stage < 2) {
                            tileProgress += spreadView.tileDistance / spreadView.width;
                        }
                        return tileProgress;
                    }

                    // This mostly is the same as progress, just adds the snapping to stage 1 for tiles 0 and 1
                    animatedProgress: {
                        if (spreadView.stage == 0 && index < 2) {
                            if (progress < spreadView.positionMarker1) {
                                return progress;
                            } else if (progress < spreadView.positionMarker1 + snappingCurve.period){
                                return spreadView.positionMarker1 + snappingCurve.value * 3;
                            } else {
                                return spreadView.positionMarker2;
                            }
                        }
                        return progress;
                    }

                    EasingCurve {
                        id: snappingCurve
                        type: EasingCurve.OutQuad
                        period: 0.05
                        progress: appDelegate.progress - spreadView.positionMarker1
                    }

                    onClicked: {
                        if (spreadView.stage == 2) {
                            if (ApplicationManager.focusedApplicationId == ApplicationManager.get(index).appId) {
                                spreadView.snapTo(index);
                            } else {
                                ApplicationManager.requestFocusApplication(ApplicationManager.get(index).appId);
                            }
                        }
                    }
                }
            }
        }
    }
}
