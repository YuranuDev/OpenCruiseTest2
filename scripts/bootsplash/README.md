# Linux の起動画面(Plymouth)と自動起動

電源を入れてから OpenCruise の画面が出るまでを、アプリの起動画面と同じ見た目でつなぐための設定です(Debian 系)。

```
電源オン → (GRUB: メニューは隠す) → Plymouth: アプリの起動画面と同じ画像(黒の背景 + 中央のロゴ)
        → アプリが起動して Plymouth の画面を消さずに引き継ぐ → アプリの起動画面 → 注意事項(OK または 8 秒で次へ) → メイン画面
```

## 入れ方

アプリをビルドしてから、SSH などで(画面をほかのアプリが使っていない状態で)実行します。

```
sudo scripts/bootsplash/install.sh --touch /dev/input/event1
sudo reboot
```

- 起動画面の画像は、アプリの `--export-splash` で、この PC の画面の大きさで作ります。
  背景は完全な黒、ロゴ(`app/resources/images/YuranuDev_Brush_Script_Logo.png`)は画面の中央に、縦横比を保って画面の大きさに合わせて出します。
  昼夜テーマ・アクセント色には連動しないので、起動した時刻やテーマの設定に関わらず、Plymouth の画面とアプリの起動画面は同じ見た目です。
  ロゴの大きさ・位置や背景色を変えたら、もう一度 `install.sh` を実行してください。
- コンソールを使うとき:
  - アプリを終了すると(メニューの終了、または **Ctrl+Alt+F2**・Ctrl+Alt+Backspace など)、tty1 にログイン画面が出ます。
    アプリが落ち続けて起動をあきらめたときも同じです。SSH はいつでも使えます。
  - アプリに戻るときは `sudo systemctl start opencruise`(tty1 のログインは閉じられます)。
  - アプリが動いている間は画面(VT)を切り替えられない(アプリが画面とキーボードを使っている)ので、
    Ctrl+Alt+F1〜F6 は「アプリを終了してコンソールへ」になります。ログイン画面は tty1 に出ます。
- アプリを手で起動するときは、先に `sudo systemctl stop opencruise` で自動起動の分を止めます。
- ログは `journalctl -u opencruise` と、いつものログファイルに残ります。

- 起動中の画面が暗くならないよう、バックライトを起動時に最大にします(アプリが起動して保存済みの明るさを書き込むまで最大のまま)。
  udev のルール(`90-opencruise-backlight.rules`。initramfs にも入れるので Plymouth の画面から効く)と、
  前回の暗い明るさを復元してしまう `systemd-backlight` の停止(明るさの保存と復元はアプリが行う)で実現しています。
  入れたくないときは `--no-backlight`。

オプションは `install.sh --help` を参照してください(`--no-autostart`: 起動画面だけ、`--no-grub`: GRUB を変えない など)。

## 元に戻す

```
sudo scripts/bootsplash/uninstall.sh
```

## しくみ

| ファイル | 役割 |
|---|---|
| `opencruise.plymouth.in` / `opencruise.script.in` | Plymouth のテーマ。アプリが書き出した画像(黒の背景 + 中央のロゴ)を最初から全面に出す |
| `opencruise.service.in` | アプリを tty1 で自動起動(ログインのセッションとして動くので、音や入力の権限はログイン時と同じ) |
| `90-opencruise-backlight.rules` / `opencruise-backlight.hook` / `systemd-backlight-opencruise.conf` | 起動時にバックライトを最大にする(udev のルール・initramfs のフック・systemd-backlight の復元停止) |
| `opencruise-splash-fallback.*` | アプリが起動できなかったとき、90 秒後に起動画面を消してコンソールに戻す |

- 画面の引き継ぎ(Plymouth の操作は root でしかできないので、サービスが行います):
  1. アプリの起動前に `plymouth deactivate`(Plymouth は画面(DRM)を手放しますが、最後の画面は出したまま)
  2. アプリが画面を開いて最初の 1 枚を描き、systemd に準備完了を知らせる(`Type=notify`)
  3. その後で `plymouth quit --retain-splash`(画面はもうアプリのものなので、黒くなりません)

  アプリは `OPENCRUISE_SPLASH_HANDOFF=1` で起動され、起動画面(黒の背景 + 中央のロゴ)を
  フェードせずに最初から出すので、途切れて見えません。
- シャットダウン・再起動のとき(終了画面への引き継ぎ):
  1. systemd がアプリに SIGTERM を送ると、アプリは今の画面を Plymouth の画像(`background.png`)へ 0.3 秒で切り替え、
     描き終えてから終わる(3 秒たっても終われなければ、そのまま終わる。サービスの停止の待ちは 10 秒)
  2. アプリが止まってから(`Before=plymouth-poweroff.service` など)、Plymouth の終了画面が同じ画像を出す

  以前は、アプリがいきなり終わって最後の画が止まったまま残り(色がだんだんおかしくなる)、Plymouth の終了画面も
  サービスが止まったときに終わらせていた。変更を反映するには `install.sh` をもう一度実行する。
  3. アプリは終わるとき、Qt の後片付けが済んだ後で、tty1 をテキストモードに戻す(`main.cpp` の `resetConsoleForPlymouth`)。
     Plymouth は起動の引き継ぎで画面を出したまま(グラフィックスモード)にして、Qt はその状態を覚えて終わるときに戻すので、
     何もしないと端末がグラフィックスモードのまま残り、Plymouth の終了画面が出ない(ログイン画面を出すと、getty が
     端末を初期化するので出る)。戻す前の状態は `journalctl -u opencruise` の `console reset for Plymouth` の行で分かる。
     アプリを入れ替えるだけで反映される(`install.sh` は不要)。
- Plymouth の画面は起動の終わりに自動で消えないようにしています(`plymouth-quit.service` を止める)。消すのは自動起動のサービスです。
- カーネルの引数に `quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0` などを足して、起動中のメッセージを抑えます。
  重大なエラーは今まで通り画面に出ます。
