// バックカメラの映像そのもの(Qt Multimedia の VideoOutput)。映像の流し込みは C++ の reverseCamera が行う
// (QMediaCaptureSession の出し先として、この VideoOutput を登録する)。
// QtMultimedia を使う所をこのファイルだけにしておく(QtMultimedia の QML モジュールが無い環境での確認用に差し替えやすいように)。
import QtQuick
import QtMultimedia

Item {
    id: root
    property bool mirror: false
    property bool fill: false

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: root.fill ? VideoOutput.PreserveAspectCrop : VideoOutput.PreserveAspectFit
        transform: Scale { origin.x: output.width / 2; xScale: root.mirror ? -1 : 1 }
        Component.onCompleted: reverseCamera.setVideoOutput(output)
    }
}
