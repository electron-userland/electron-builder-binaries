const path = require("path")
const BluebirdPromise = require("bluebird-lst")
const copy = BluebirdPromise.promisify(require("fcopy-pre-bundled"))

const windowsKitsDir = "/Volumes/C/Program Files (x86)/Windows Kits/10"
const sourceDir = path.join(windowsKitsDir, "bin/10.0.15063.0")
const destination = path.join(__dirname, "../winCodeSign/windows-10")

// noinspection SpellCheckingInspection
const files = [
  "appxpackaging.dll",
  "makeappx.exe",
  "makecert.exe",
  "makepri.exe",
  "Microsoft.Windows.Build.Appx.AppxPackaging.dll.manifest",
  "Microsoft.Windows.Build.Appx.OpcServices.dll.manifest",
  "opcservices.dll",
  "signtool.exe"
]

function copyFiles(files, sourceDir, archWin, archNode) {
  return BluebirdPromise.map(files, file => copy(path.join(sourceDir, archWin, file), path.join(destination, archNode, file)))
}

BluebirdPromise.all([
  copyFiles(files, sourceDir, "x86", "ia32"),
  copyFiles(files, sourceDir, "x64", "x64"),
  // pvk2pfx not in the 10.0.15063.0 for unknown reason
  copyFiles(["pvk2pfx.exe",], path.join(windowsKitsDir, "bin"), "x86", "ia32"),
  copyFiles(["pvk2pfx.exe",], path.join(windowsKitsDir, "bin"), "x64", "x64"),
])
  .catch(error => {
    process.exitCode = 1
    console.error(error)
  })

