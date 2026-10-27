# Linux の起動画面(Plymouth)と自動起動

電源を入れてから OpenCruise の画面が出るまでを、アプリの起動画面と同じ見た目でつなぐための設定です(Debian 系)。

```
電源オン → (GRUB: メニューは隠す) → Plymouth: アプリの起動画面と同じ画像 + 進行バー
        → アプリが起動して Plymouth の画面を消さずに引き継ぐ → アプリの起動画面 → メイン画面
```

## 入れ方

アプリをビルドしてから、SSH などで(画面をほかのアプリが使っていない状態で)実行します。

```
sudo scripts/bootsplash/install.sh --touch /dev/input/event1
sudo reboot
```

- 起動画面の画像は、アプリの `--export-splash` で、この PC の画面の大きさ・今のテーマの色で作ります。
  アプリの起動画面の色(テーマ・アクセント色)やレイアウトを変えたら、もう一度 `install.sh` を実行してください。
- 自動起動を入れると、tty1 のログイン画面は出なくなります。Ctrl+Alt+F2 などのほかの画面と SSH は今まで通り使えます。
- アプリを手で起動するときは、先に `sudo systemctl stop opencruise` で自動起動の分を止めます。
- ログは `journalctl -u opencruise` と、いつものログファイルに残ります。

オプションは `install.sh --help` を参照してください(`--no-autostart`: 起動画面だけ、`--no-grub`: GRUB を変えない など)。

## 元に戻す

```
sudo scripts/bootsplash/uninstall.sh
```

## しくみ

| ファイル | 役割 |
|---|---|
| `opencruise.plymouth.in` / `opencruise.script.in` | Plymouth のテーマ。アプリが書き出した画像を全面に出し、進行バーの塗りだけを描く |
| `opencruise.service.in` | アプリを tty1 で自動起動(ログインのセッションとして動くので、音や入力の権限はログイン時と同じ) |
| `opencruise-splash-fallback.*` | アプリが起動できなかったとき、90 秒後に起動画面を消してコンソールに戻す |

- 画面の引き継ぎ(Plymouth の操作は root でしかできないので、サービスが行います):
  1. アプリの起動前に `plymouth deactivate`(Plymouth は画面(DRM)を手放しますが、最後の画面は出したまま)
  2. アプリが画面を開いて最初の 1 枚を描き、systemd に準備完了を知らせる(`Type=notify`)
  3. その後で `plymouth quit --retain-splash`(画面はもうアプリのものなので、黒くなりません)

  アプリは `OPENCRUISE_SPLASH_HANDOFF=1` で起動され、起動画面の変わらない部分(背景・タイトル・進行バーの溝・警告)を
  フェードせずに最初から出すので、途切れて見えません。
- Plymouth の画面は起動の終わりに自動で消えないようにしています(`plymouth-quit.service` を止める)。消すのは自動起動のサービスです。
- カーネルの引数に `quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0` などを足して、起動中のメッセージを抑えます。
  重大なエラーは今まで通り画面に出ます。
