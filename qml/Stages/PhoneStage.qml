import QtQuick 2.0
import Ubuntu.Components 0.1
import Ubuntu.Gestures 0.1
import Unity.Application 0.1
import Utils 0.1
import "../Components"

/*

*/

Item {
    id: root

    // Controls to be set from outside
    property bool shown: false
    property bool moving: false
    property int dragAreaWidth

    // State information propagated to the outside
    readonly property bool painting: mainScreenshotImage.visible || fadeInScreenshotImage.visible || appSplash.visible
    onPaintingChanged: print("**********************+ painting changed", painting)

    onMovingChanged: {
        if (moving) {
            priv.requestNewScreenshot();
        } else {
            mainScreenshotImage.visible = false;
        }
    }

    Connections {
        target: ApplicationManager

        onFocusRequested: {
            priv.switchToApp(appId);
        }

        onFocusedApplicationIdChanged: {
            if (ApplicationManager.focusedApplicationId.length > 0) {
                if (priv.secondApplicationStarting || priv.applicationStarting) {
                    appSplashTimer.start();
                } else {
                    mainScreenshotImage.src = ApplicationManager.findApplication(ApplicationManager.focusedApplicationId).screenshot
                }
            }
        }

        onApplicationAdded: {
            if (!priv.focusedApplication) {
                mainScreenshotImage.src = "";
                mainScreenshotImage.visible = false;
                priv.applicationStarting = true;
            } else {
                mainScreenshotImage.src = "foobar";
                priv.newFocusedAppId = appId;
                priv.secondApplicationStarting = true;
                priv.requestNewScreenshot();
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
                mainScreenshotImage.src = ApplicationManager.findApplication(ApplicationManager.focusedApplicationId).screenshot;
                mainScreenshotImage.visible = true;
            } else if (priv.secondApplicationStarting && priv.waitingForScreenshot) {
                applicationSwitchingAnimation.start();
            }
            waitingForScreenshot = false;
        }

        function requestNewScreenshot() {
            waitingForScreenshot = true;
            ApplicationManager.updateScreenshot(ApplicationManager.focusedApplicationId);
        }

        function switchToApp(appId) {
            priv.newFocusedAppId = appId;
            applicationSwitchingAnimation.start();
            grantFocusTimer.start();
        }

    }

    Timer {
        id: grantFocusTimer
        // Delay the actual switch to be covered by the animation for sure.
        // 1) If we switch before starting the animation, the Mir event loop paints before the Qt event loop => flickering
        // 2) If we do the switch after the animation, the panel wouldn't fade in early enough.
        interval: UbuntuAnimation.SlowDuration / 4
        repeat: false
        onTriggered: {
            ApplicationManager.focusApplication(priv.newFocusedAppId);
        }
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
        // PropertyAction seems to fail when secondApplicationStarting and we didn't have another screenshot before
        ScriptAction { script: mainScreenshotImage.src = priv.focusedScreenshot }
        PropertyAction { target: mainScreenshotImage; property: "visible"; value: true }
        PropertyAction { target: fadeInScreenshotImage; property: "source"; value: ApplicationManager.findApplication(priv.newFocusedAppId).screenshot }
        PropertyAction { target: fadeInScreenshotImage; property: "visible"; value: true }
        PropertyAction { target: fadeInScreenshotImage; property: "opacity"; value: 0 }
        PropertyAction { target: fadeInScreenshotImage; property: "scale"; value: .8 }


        // The actual animation
        ParallelAnimation {
            UbuntuNumberAnimation { target: mainScreenshotImage; property: "anchors.leftMargin"; to: root.width; duration: UbuntuAnimation.SlowDuration }
            UbuntuNumberAnimation { target: fadeInScreenshotImage; property: "opacity"; to: 1; duration: UbuntuAnimation.SlowDuration }
            UbuntuNumberAnimation { target: fadeInScreenshotImage; property: "scale"; to: 1; duration: UbuntuAnimation.SlowDuration }
        }

        // restore stuff
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

        property string src
        source: src
        visible: false
    }

    EdgeDragArea {
        id: coverFlipDragArea
        direction: Direction.Rightwards

        //enabled: root.available
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: root.dragAreaWidth

        onTouchXChanged: {
            if (!dragging && !priv.waitingForScreenshot) {
                priv.requestNewScreenshot();
            }
            if (dragging && !priv.waitingForScreenshot) {
                coverFlickable.contentX = -touchX
            }
        }

        onDraggingChanged: {
            if (!dragging) {
                coverFlip.snap();
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "green"
            opacity: .4
        }
    }

    Rectangle {
        id: coverFlipBackground
        anchors.fill: parent
        color: "black"
        visible: coverFlip.visible
    }

    InputFilterArea {
        anchors.fill: root
        blockInput: coverFlip.visible
    }
    Flickable {
        id: coverFlickable
        anchors.fill: root
        contentHeight: height
        contentWidth: width * ApplicationManager.count
        flickableDirection: Qt.Horizontal
        enabled: coverFlip.visible

        onContentXChanged: {
//            print("contentX changed", contentX)
            var progress = contentX / width
            if (progress > coverFlip.progressMarker1) {
                progress += progress - coverFlip.progressMarker1
            }

            coverFlip.progress = progress;
//            print("progress is", coverFlip.progress)
        }
    }

    Row {
        id: coverFlip
        height: parent.height
        x: 0
        visible: progress > 0

        property real progress: 0
        property real startAngle: 45
        property int endAngle: 10

        property real maxScale: 1.4
        property real minScale: .6

        // Markers: relative screen position from left to right
        // marks the line where first application is finished moving in from the right
        property real progressMarker1: 0.5

        property real tileDistance: 0.1

        property bool animatingBack: false

        property real tileWidth: root.width

        property real oldProgress: 0
        onProgressChanged: {
            if (oldProgress <= coverFlip.progressMarker1 && progress > coverFlip.progressMarker1) {
                ApplicationManager.focusApplication(ApplicationManager.get(1).appId)
            } else if (oldProgress >= coverFlip.progressMarker1 && progress <= coverFlip.progressMarker1) {
                ApplicationManager.focusApplication(ApplicationManager.get(1).appId)
            }
            oldProgress = progress;
        }

        function snap() {
            if (coverFlip.progress < 0.25) {
                snapAnimation.targetContentX = 0
            } else if (coverFlip.progress < 0.6) {
                snapAnimation.targetContentX = root.width * coverFlip.progressMarker1
            } else {
                if (ApplicationManager.count == 3) {
                    snapAnimation.targetContentX = root.width * .8;
                } else {
                    snapAnimation.targetContentX = root.width * .9;
                }
            }
            snapAnimation.start();
        }

        function selectItem(index) {
            tileRepeater.itemAt(index).select();
        }

        SequentialAnimation {
            id: snapAnimation
            property var targetContentX

            UbuntuNumberAnimation {
                target: coverFlickable
                properties: "contentX"
                to: snapAnimation.targetContentX
            }
            ScriptAction {
                script: {
                    if (snapAnimation.targetContentX == root.width * coverFlip.progressMarker1) {
                        coverFlickable.contentX = 0;
                    }
                }
            }
        }

        Repeater {
            id: tileRepeater
            model: ApplicationManager

            Item {
                height: parent.height
                width: coverFlip.tileWidth

                Image {
                    id: appImage
                    anchors { left: parent.left; bottom: parent.bottom }
                    width: root.width
                    source: ApplicationManager.get(index).screenshot
                    scale: 1

                    // This is the main progress, of the gesture, the same for every tile
                    property real progress: coverFlip.progress
                    // The progress, translated for the second stage of the animation, after the first app switch has happened
                    // Additionally it speeds it up a bit, depending on the distance of the tile
                    property real translatedProgress: appImage.progress - coverFlip.progressMarker1 - (coverFlip.tileDistance * (index-1))

                    // Is this tile selected by a click?
                    property bool isSelected: false
                    // We need to remember some values when app is selected to be able to animate it to the foreground
                    property real selectedXTranslation: 0
                    property real selectedTranslatedProgress: 0
                    property real selectedAngle: 0
                    property real selectedXScale: 0

                    function select() {
                        print("selecting item, current translation:", appImage.xTranslation)
                        appImage.selectedXTranslation = appImage.xTranslation;
                        appImage.selectedAngle = appImage.angle;
                        appImage.selectedXScale = appImage.xScale;
                        appImage.selectedTranslatedProgress = appImage.translatedProgress;
                        print("set selected x translation", appImage.selectedXTranslation)
                        appImage.isSelected = true;
                        switchToAppAnimation.start();
                    }

                    property int xTranslation: {
                        var xTranslate = 0;
                        var minXTranslate = -index * root.width + index * units.dp(3);
                        switch (index) {
                        case 0:
                            if (appImage.progress < coverFlip.progressMarker1) {
                                var progress = appImage.progress
                                var progressDiff = coverFlip.progressMarker1
                                var translateDiff = -root.width * 0.25
                                // progress : progressDiff = translate : translateDiff
                                xTranslate = progress * translateDiff / progressDiff
                            }
                            break;
                        case 1:
                            if (appImage.progress < coverFlip.progressMarker1) {
                                var progress = appImage.progress;
                                var progressDiff = coverFlip.progressMarker1;
                                var translateDiff = -root.width;
                                // progress : progressDiff = translate : translateDiff
                                xTranslate = progress * translateDiff / progressDiff;
                                break;
                            }
                            // Intentionally no break here...
                        default:
                            if (appImage.progress > coverFlip.progressMarker1) {
                                xTranslate = xTranslateEasing.value * xTranslateEasing.period;

                                // make sure we stop at the left screen edge
//                                xTranslate = Math.max(xTranslate, minXTranslate)
                                break;
                            }
                        }
                        if (appImage.isSelected) {
                            var newTranslate = selectedXTranslateEasing.value * selectedXTranslateEasing.period
                            xTranslate = appImage.selectedXTranslation + newTranslate;
                        }

                        return xTranslate;
                    }

                    property real angle: {
                        var newAngle = 0;
                        switch (index) {
                        case 0:
                            if (appImage.progress <= coverFlip.progressMarker1) {
                                var progress = appImage.progress;
                                var angleDiff = coverFlip.endAngle;
                                var progressDiff = coverFlip.progressMarker1;
                                // progress : progressDiff = angle : angleDiff
                                newAngle = progress * angleDiff / progressDiff;
                            } else {
                                var progress = appImage.progress - coverFlip.progressMarker1;
                                var angleDiff = coverFlip.endAngle;
                                var progressDiff = 1 - coverFlip.progressMarker1;
                                // progress : progressDiff = angle : angleDiff
                                newAngle = progress * angleDiff / progressDiff;
                                newAngle = Math.min(coverFlip.endAngle, newAngle);
                            }
                            break;
                        case 1:
                            if (appImage.progress < coverFlip.progressMarker1) {
                                var progress = coverFlip.progress;
                                var angleDiff = coverFlip.startAngle;
                                var progressDiff = coverFlip.progressMarker1;
                                // progress : progressDiff = angle : angleDiff
                                var angle = progress * angleDiff / progressDiff;
                                newAngle = coverFlip.startAngle - angle;
                                break;
                            }
                            // Intentionally no break here...
                        default:
//                                        var progress = appImage.progress;
//                                        var angleDiff = coverFlip.startAngle - coverFlip.endAngle;
////                                        var progressDiff = coverFlip.progressMarker1 + index * 0.25 + 0.25
//                                        var progressDiff = index
//                                        // progress : progressDiff = angle : angleDiff
//                                        newAngle = progress * angleDiff / progressDiff;
//                                        newAngle = Math.max(coverFlip.endAngle, coverFlip.startAngle - newAngle)

                            newAngle = coverFlip.startAngle - (angleEasing.value * angleEasing.period);

                            // make sure we stop at the left screen edge
                            newAngle = Math.max(newAngle, coverFlip.endAngle);

                        }
                        if (appImage.isSelected) {
                            var selectedAngleTranslate = selectedAngleEasing.value * selectedAngleEasing.period
                            print("selectedAngle", appImage.selectedAngle, "translate", selectedAngleTranslate)
                            newAngle = appImage.selectedAngle - selectedAngleTranslate;
                        }

                        return newAngle;
                    }

                    property real xScale: {
                        var scale = 1;

                        switch (index) {
                        case 0:
                            if (appImage.progress > coverFlip.progressMarker1) {
                                var scaleDiff = coverFlip.maxScale - 1;
                                var progressDiff = 1.5 - coverFlip.progressMarker1;
                                // progress : progressDiff = scale : scaleDiff
                                scale = 1 - (appImage.progress - coverFlip.progressMarker1) * scaleDiff / progressDiff;
                            }
                            break;
                        case 1:
                            if (appImage.progress < coverFlip.progressMarker1) {
                                var scaleDiff = coverFlip.maxScale - 1
                                var progressDiff = coverFlip.progressMarker1
                                // progress : progressDiff = scale : scaleDiff
                                scale = coverFlip.maxScale - (appImage.progress * scaleDiff / progressDiff);
                                break;
                            }
                            // Intentionally no break
                        default:
//                                    var scaleDiff = coverFlip.maxScale - coverFlip.minScale
////                                    var progressDiff = coverFlip.progressMarker1 + index * 0.25 + 0.25
//                                    var progressDiff = index
//                                    // progress : progressDiff = scale : scaleDiff
//                                    scale = coverFlip.maxScale - (appImage.progress - coverFlip.progressMarker1) * scaleDiff / progressDiff
//                                    break;

                            scale = coverFlip.maxScale - scaleEasing.value * scaleEasing.period;
                        }

                        if (appImage.isSelected) {
                            var selectedScaleTranslate = selectedScaleEasing.value * selectedScaleEasing.period
                            scale = appImage.selectedXScale + selectedScaleTranslate;
                        }

                        return Math.min(coverFlip.maxScale, Math.max(coverFlip.minScale, scale));
                    }


                    EasingCurve {
                        id: xTranslateEasing
                        type: EasingCurve.OutQuad
                        period: index * -width
                        progress: appImage.translatedProgress
                    }
                    EasingCurve {
                        id: selectedXTranslateEasing
                        type: EasingCurve.Linear
                        period: xTranslateEasing.period - appImage.selectedXTranslation
                        progress: appImage.selectedTranslatedProgress - xTranslateEasing.progress
                    }
                    EasingCurve {
                        id: angleEasing
                        type: EasingCurve.InQuad
                        period: coverFlip.startAngle - coverFlip.endAngle
                        progress: appImage.translatedProgress
                    }
                    EasingCurve {
                        id: selectedAngleEasing
                        type: EasingCurve.Linear
                        period: appImage.selectedAngle
                        progress: appImage.selectedTranslatedProgress - angleEasing.progress
                    }
                    EasingCurve {
                        id: scaleEasing
                        type: EasingCurve.Linear
                        period: coverFlip.maxScale - coverFlip.minScale
                        progress: appImage.translatedProgress
                    }
                    EasingCurve {
                        id: selectedScaleEasing
                        type: EasingCurve.Linear
                        period: 1 - appImage.selectedXScale
                        progress: appImage.selectedTranslatedProgress - scaleEasing.progress
                    }

                    transform: [
                        Rotation {
                            origin { x: 0; y: coverFlip.height / 2 }
                            axis { x: 0; y: 1; z: 0 }
                            angle: appImage.angle
                        },
                        Translate {
                            x: appImage.xTranslation
                        },
                        Scale {
                            origin { x: appImage.xTranslation; y: root.height / 2 - (root.height - appImage.height)}
                            xScale: appImage.xScale
                            yScale: xScale
                        }
                    ]

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            print("clicked on index", index)
                            appImage.select()
                        }
                    }
                }

                SequentialAnimation {
                    id: switchToAppAnimation
                    ParallelAnimation {
                        UbuntuNumberAnimation { target: coverFlickable; property: "contentX"; to: 0}
                    }
                    ScriptAction {
                        script: {
                            ApplicationManager.focusApplication(ApplicationManager.get(index).appId);
                            appImage.isSelected = false;
                            coverFlip.progress = 0;
                        }
                    }
                }
            }
        }
    }
}
