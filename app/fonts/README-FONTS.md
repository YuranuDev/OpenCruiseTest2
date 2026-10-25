# 同梱フォントとライセンス

すべて **SIL Open Font License 1.1 (OFL-1.1)**。無改変のまま、各フォルダの `OFL.txt` と著作権表示を添えて再配布している
(OFL 条件: ①著作権表示とライセンス全文を同梱 ②フォント単体で販売しない ③改変版は予約フォント名を使わない)。
フォントファイルは加工していない。ライセンスはフォントの name テーブル(著作権・ライセンス欄)でも OFL であることを確認済み。

| フォルダ | ファミリ名 | 太さ | 配布元 | 著作権表示 |
|---|---|---|---|---|
| NotoSansJP/ | Noto Sans JP | Thin, Light, DemiLight, Regular, Medium, Bold, Black | https://github.com/notofonts/noto-cjk `Sans/SubsetOTF/JP/` | © 2014-2021 Adobe (http://www.adobe.com/) |
| NotoSansCJKjp/ | Noto Sans CJK JP | Thin, Light, DemiLight, Regular, Medium, Bold, Black | https://github.com/notofonts/noto-cjk `Sans/OTF/Japanese/` | © 2014-2021 Adobe (http://www.adobe.com/) |
| IBMPlexSansJP/ | IBM Plex Sans JP | Thin, ExtraLight, Light, Regular, Text, Medium, SemiBold, Bold | https://github.com/IBM/plex `packages/plex-sans-jp/fonts/complete/otf/unhinted/` | Copyright © 2017 IBM Corp. with Reserved Font Name "Plex" |

- いずれも日本語(JP)字形版のみ。SC/TC/KR 版は含めない。
- Noto Sans JP は Noto Sans CJK JP の日本語サブセット版(字形は同一、収録文字数が少なくファイルが小さい)。
- 実行時は `<実行ファイルのあるフォルダ>/fonts/` から読み込む(ビルド時に自動コピー)。読み込みは `app/core/AppSettings.cpp`。
- 将来フォントを改変・サブセット化する場合は、OFL の予約フォント名("Plex" など)の扱いを再確認すること。

## アイコンフォント(リソースに埋め込み)

上の表とは別に、アイコン用のフォントを 2 つ、実行ファイルのリソース(qrc)に埋め込んでいる。どちらも **Apache License 2.0**、無改変。
表示は `app/qml/MaterialIcon.qml`(name に "mdi:" を付けると Material Design Icons を使う)。

| ファイル | 内容 | 配布元 | ライセンス文 |
|---|---|---|---|
| MaterialIcons-Regular.ttf | Google Material Icons | https://github.com/google/material-design-icons | LICENSE-MaterialIcons.txt |
| materialdesignicons-webfont.ttf | Pictogrammers Material Design Icons 7.4.47(車の警告灯に近いアイコンが多い) | npm `@mdi/font` 7.4.47 の `fonts/` | LICENSE-MaterialDesignIcons.txt |

- Material Design Icons のアイコン名 → 文字コードの表は `app/qml/MdiCodes.js`(`@mdi/font` の `scss/_variables.scss` から生成)。フォントを更新したら作り直すこと。
