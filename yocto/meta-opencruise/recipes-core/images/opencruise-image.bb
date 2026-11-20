SUMMARY = "OpenCruise 専用イメージ(Qt アプライアンスのベース + OpenCruise アプリ)"
require recipes-core/images/qt-appliance-image.bb

IMAGE_INSTALL += "opencruise"
