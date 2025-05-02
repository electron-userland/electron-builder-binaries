# How do update NSIS:
# 1. Download https://sourceforge.net/projects/nsis/files/NSIS%203/3.03/nsis-3.03.zip/download (replace 3.03 to new version)
# 2. Copy over nsis in this repo and copy nsis-lang-fixes to nsis/Contrib/Language files
# 3. Inspect changed and unversioned files — delete if need.
# 4. Download https://netix.dl.sourceforge.net/project/nsis/NSIS%203/3.03/nsis-3.03-strlen_8192.zip and copy over
# 5. brew install makensis --with-large-strings --with-advanced-logging && sudo cp /usr/local/Cellar/makensis/*/bin/makensis nsis/mac/makensis
# 6. See nsis-windows.sh
# 7. See nsis-mac.sh