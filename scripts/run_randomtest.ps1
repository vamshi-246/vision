param(
  [Parameter(Mandatory = $true)][string]$Image,
  [string]$Name = "image",
  [string]$OutDir = "randomtests",
  [int]$ThrLo = 80,
  [int]$ThrHi = 200
)

$ErrorActionPreference = "Stop"
python -m model.rtl_image_test prepare $Image --outdir $OutDir --name $Name --thr-lo $ThrLo --thr-hi $ThrHi
if ($LASTEXITCODE -ne 0) { throw "Golden-vector preparation failed" }
New-Item -ItemType Directory -Force build | Out-Null
iverilog -g2012 -Wall -s tb_image_scoreboard -o build/tb_image_scoreboard rtl/linebuf.sv rtl/gauss.sv rtl/dir_decide.sv rtl/sobel.sv rtl/dirnms.sv rtl/classify_hist.sv rtl/top.sv tb/system/tb_image_scoreboard.sv
if ($LASTEXITCODE -ne 0) { throw "RTL compilation failed" }
vvp build/tb_image_scoreboard "+INPUT_HEX=$OutDir/$Name`_input.hex" "+OUT_HEX=$OutDir/$Name`_rtl_output.hex" "+THR_LO=$ThrLo" "+THR_HI=$ThrHi"
if ($LASTEXITCODE -ne 0) { throw "RTL simulation failed" }
python -m model.rtl_image_test report --outdir $OutDir --name $Name
if ($LASTEXITCODE -ne 0) { throw "RTL/golden comparison failed" }
