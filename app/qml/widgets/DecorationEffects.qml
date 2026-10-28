// 飾りの画像の「パネル」の層で、角丸の切り抜きに使える効果(全ウィジェットで共通。最初に一度だけ調べる)。
//  kind: -1 = まだ調べていない / 0 = MultiEffect(Qt 6.5 以降)/ 1 = OpacityMask(Qt5Compat)/ 2 = どちらも無い(四角く切り抜く)
pragma Singleton
import QtQuick

QtObject {
    property int kind: -1
}
