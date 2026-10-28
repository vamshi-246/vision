param(
  [Parameter(Mandatory = $true)][string]$Image,
  [string]$Name = "image",
  [string]$OutDir = "randomtests",
  [int]$ThrLo = 80,
  [int]$ThrHi = 200
)

$ErrorActionPreference = "Stop"
python -m model.rtl_image_test prepare $Image --outdir $OutDir --name $Name --thr-lo $ThrLo --thr-hi $ThrHi
New-Item -ItemType Directory -Force build | Out-Null
iverilog -g2012 -Wall -s tb_image_scoreboard -o build/tb_image_scoreboard rtl/linebuf.sv rtl/gauss.sv rtl/sobel.sv rtl/dirnms.sv rtl/classify_hist.sv rtl/top.sv tb/system/tb_image_scoreboard.sv
vvp build/tb_image_scoreboard "+INPUT_HEX=$OutDir/$Name`_input.hex" "+OUT_HEX=$OutDir/$Name`_rtl_output.hex"
python -m model.rtl_image_test report --outdir $OutDir --name $Name
