const path = require("path")
const BluebirdPromise = require("bluebird-lst")
const copy = BluebirdPromise.promisify(require("fs").copyFile)

const windowsKitsDir = "/Volumes/[C] Windows 10.hidden/Program Files (x86)/Windows Kits/10"
const sourceDir = path.join(windowsKitsDir, "bin/10.0.17763.0")
const destination = path.join(__dirname, "../winCodeSign/windows-10")

// noinspection SpellCheckingInspection
const files = [
  "appxpackaging.dll",
  "makeappx.exe",
  "makecert.exe",

  "makecat.exe",
  "makecat.exe.manifest",

  "Microsoft.Windows.Build.Signing.mssign32.dll.manifest",
  "mssign32.dll",

  "Microsoft.Windows.Build.Appx.AppxSip.dll.manifest",
  "appxsip.dll",

  "Microsoft.Windows.Build.Signing.wintrust.dll.manifest",
  "wintrust.dll",

  "makepri.exe",
  "Microsoft.Windows.Build.Appx.AppxPackaging.dll.manifest",
  "Microsoft.Windows.Build.Appx.OpcServices.dll.manifest",
  "opcservices.dll",
  "signtool.exe",
  "signtool.exe.manifest",
  "pvk2pfx.exe"
]

function copyFiles(files, sourceDir, archWin, archNode) {
  return BluebirdPromise.map(files, file => copy(path.join(sourceDir, archWin, file), path.join(destination, archNode, file)))
}

Promise.all([
  copyFiles(files, sourceDir, "x86", "ia32"),
  copyFiles(files, sourceDir, "x64", "x64"),
])
  .catch(error => {
    process.exitCode = 1
    console.error(error)
  })

