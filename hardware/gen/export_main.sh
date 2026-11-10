#!/bin/bash
# export_main.sh : JLCPCB fab files + layer images for PWR-CTRL
set -e
P=/home/claude/pcb/pwrctrl; B=$P/pwrctrl.kicad_pcb; J=$P/jlc; T=/tmp/claude-0/exp
mkdir -p $J/gerber $T; rm -f $J/gerber/*
kicad-cli pcb export gerbers -o $J/gerber/ -l F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts --subtract-soldermask $B >/dev/null
kicad-cli pcb export drill -o $J/gerber/ --format excellon --excellon-separate-th --generate-map --map-format gerberx2 $B >/dev/null
(cd $J/gerber && rm -f ../pwrctrl_gerber_JLC.zip && zip -q ../pwrctrl_gerber_JLC.zip *)
python3 /home/claude/pcb/gen/bomcpl.py $B $J
# layer images (top / bottom mirrored)
kicad-cli pcb export svg -o $T/top.svg -l F.Cu,F.Silkscreen,Edge.Cuts --mode-single --fit-page-to-board --exclude-drawing-sheet $B >/dev/null
kicad-cli pcb export svg -o $T/bot.svg -l B.Cu,B.Silkscreen,Edge.Cuts --mode-single --fit-page-to-board --exclude-drawing-sheet --mirror $B >/dev/null
for s in top bot; do rsvg-convert -w 1980 -b white $T/$s.svg -o $T/$s.png; done
cp $T/top.png $P/layer_top.png; cp $T/bot.png $P/layer_bottom.png; cp $T/top.png $P/routing_tracks.png
kicad-cli pcb render -o $P/render_3d_top.png --side top -w 2384 -h 1376 --quality high $B >/dev/null 2>&1 || echo 'render failed'
echo export done
